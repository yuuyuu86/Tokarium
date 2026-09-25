import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

@MainActor
@Observable
final class GameStore {
    /// 水槽の状態。書きかえは GameStore とその拡張からだけ行う（画面からは操作用の関数を使う）。
    var state: GameState
    var settings: AppSettings { didSet { if settings != oldValue { saveSettings(); settingsChanged(from: oldValue) } } }
    var ledger: UsageLedger
    private(set) var sourceStatuses: [String: SourceStatus] = [:]
    private(set) var lastScanAt: Date?
    private(set) var isScanning = false
    private(set) var detectedSources: Set<String> = []
    /// 再開時に反映した内容のお知らせ。
    var resumeMessage: String?
    /// 画面に出す一時的なお知らせ。
    var toast: String?
    /// 表示中の不具合報告。
    var bugReport: BugReportRequest?
    /// 「このアプリについて」を表示中。
    var showAbout = false
    /// メニューやショートカットからの画面操作（MainView が受け取って実行する）。
    var command: UICommand?
    /// 置き場所を決めている最中の装飾（買った直後や持ち物から出したとき）。
    var placingDecoration: UUID?

    @ObservationIgnored let engine = SwimEngine()
    let power = PowerMonitor()

    /// 省電力を考えたアニメーションの速さ。
    var effectiveFPS: Int { power.fps(base: settings.fps, auto: settings.autoPowerSaving) }
    @ObservationIgnored let scanner: UsageScanner
    @ObservationIgnored let dir: URL
    @ObservationIgnored var timers: [Timer] = []
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onDisplaySettingsChanged: (() -> Void)?

    var style: AquariumStyle { AquariumStyles.style(settings.styleID) }

    var coins: Int { state.initialCoins + ledger.coinsEarned + otherMacsEarned - state.coinsSpent }
    /// iCloud Drive で同期しているほかの Mac で得たコイン。
    var otherMacsEarned = 0
    @ObservationIgnored var lastPulledModified: Date?
    @ObservationIgnored var lastPushedAt: Date?
    @ObservationIgnored var lastEarnedRefreshAt: Date?
    /// 時間経過だけの保存を iCloud Drive に書く間隔。
    static let periodicPushInterval: TimeInterval = 180
    var livingFish: [Fish] { state.tank.fish.filter(\.isAlive) }
    var dangerFish: [Fish] { state.tank.fish.filter { $0.condition.isDanger } }

    /// 保存先。動作確認用に TOKARIUM_DATA_DIR で差し替えられる。
    nonisolated static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TOKARIUM_DATA_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tokarium", isDirectory: true)
    }

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let (loaded, recovery) = Self.loadGame(in: dir)
        let state = loaded ?? GameState.newGame()
        self.state = state
        self.resumeMessage = recovery
        self.settings = (try? Data(contentsOf: dir.appendingPathComponent("settings.json")))
            .flatMap { try? JSONDecoder.tokarium.decode(AppSettings.self, from: $0) } ?? AppSettings()
        let scanner = UsageScanner(ledgerURL: dir.appendingPathComponent("usage-ledger.json"), startDate: state.createdAt)
        self.scanner = scanner
        self.ledger = UsageLedger(startDate: state.createdAt)
        self.detectedSources = scanner.detectedSources()
        if loaded == nil { save() }
        Task { self.ledger = await scanner.currentLedger }
    }

    /// 水槽のデータを読む。壊れていたら別名で残し、いちばん新しい自動バックアップから戻す。
    private static func loadGame(in dir: URL) -> (GameState?, String?) {
        let url = dir.appendingPathComponent("game.json")
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }
        if let state = try? JSONDecoder.tokarium.decode(GameState.self, from: data) { return (state, nil) }
        // 読めないデータは消さずに残す
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let broken = dir.appendingPathComponent("game.broken-\(f.string(from: Date())).json")
        try? FileManager.default.moveItem(at: url, to: broken)
        AppLog.error("水槽のデータを読めませんでした。\(broken.lastPathComponent) に残しました")
        for backup in AutoBackup.list(in: dir) {
            if let b = try? JSONDecoder.tokarium.decode(TokariumBackup.self, from: Data(contentsOf: backup.url)) {
                AppLog.info("自動バックアップ \(backup.url.lastPathComponent) から戻しました")
                return (b.game, String(localized: "水槽のデータが読めなかったため、\(backup.date.shortText) の自動バックアップから戻しました。"))
            }
        }
        return (nil, String(localized: "水槽のデータが読めず、バックアップもなかったため、新しい水槽で始めました。読めなかったデータは保存フォルダに残してあります。"))
    }

    // MARK: 起動・時間経過

    func start() {
        SoundPlayer.shared.config = settings.soundConfig
        // 魚が餌を食べたら「ぱくっ」
        engine.onEat = { SoundPlayer.shared.play(.eat, spontaneous: true) }
        simulate()
        autoBackupIfNeeded()
        timers.append(Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.simulate() }
        })
        // 1時間ごとに、前の自動バックアップから1日たったか確かめる
        timers.append(Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoBackupIfNeeded() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanNow() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.simulate()
                self?.scanNow()
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        })
        if settings.onboarded { scanNow() }
        if settings.iCloudSync { pullFromICloud() }
        scheduleReminders()
    }

    /// 経過時間を反映する。起動中・スリープ明け・再起動のすべてでこれを使う。
    func simulate(now: Date = Date()) {
        if settings.iCloudSync { pullFromICloud() }
        let before = state.tank.fish
        let report = Simulation.advance(&state, to: now)
        if report.isCatchUp && report.simulated > 30 * 60 {
            var msg = String(localized: "離れていた間の \(Self.durationText(report.simulated)) を水槽に反映しました。")
            if report.skipped > 0 {
                msg += String(localized: "（\(Self.durationText(Simulation.maxCatchUp)) を超えた分は反映していません）")
            }
            let hungry = state.tank.fish.filter { $0.isAlive && $0.condition != .healthy }.count
            if hungry > 0 { msg += String(localized: " お世話が必要な魚が \(hungry) 匹います。") }
            resumeMessage = msg
        }
        announce(report)
        notifyChanges(before: before)
        evaluateProgress()
        // 時間経過だけの保存は、iCloud Drive へは数分に1回にまとめる
        save(periodic: !report.isCatchUp && report.newlyDead.isEmpty && report.births.isEmpty)
    }

    func announce(_ report: Simulation.Report) {
        if !report.births.isEmpty { sfx(.birth, spontaneous: true) }
        else if !report.newlyDead.isEmpty { sfx(.sad, spontaneous: true) }
        else if !report.grownUp.isEmpty { sfx(.sparkle, spontaneous: true) }
        if report.autoFed > 0 {
            toast = String(localized: "自動給餌器が餌をあげました（残り \(state.food) 回分）")
        }
        if let shiny = report.births.first(where: \.isShiny) {
            post(title: String(localized: "色違いの稚魚が生まれました！"), body: String(localized: "\(shiny.name)がきらきら光っています。"))
        }
        if !report.births.isEmpty {
            let name = report.births[0].species.name
            toast = String(localized: "\(name)の稚魚が \(report.births.count) 匹生まれました")
            post(title: String(localized: "稚魚が生まれました"), body: String(localized: "\(name)の稚魚が \(report.births.count) 匹生まれました。"))
        }
        for f in report.newlySick {
            post(title: String(localized: "\(f.name)が病気になりました"), body: String(localized: "お店で薬を買って、お世話画面であげてください。水換えも効果的です。"))
        }
        if let f = report.grownUp.first {
            toast = String(localized: "\(f.name)が成魚になりました")
        }
    }

    static func durationText(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = t >= 86400 ? [.day, .hour] : t >= 3600 ? [.hour] : [.minute]
        f.maximumUnitCount = 2
        return f.string(from: max(60, t)) ?? ""
    }

    // MARK: 利用記録

    func scanNow() {
        guard settings.onboarded, !isScanning else { return }
        isScanning = true
        let enabled = settings.enabledSources, includeEstimated = settings.includeEstimated
        let before = ledger.coinsEarned
        Task {
            let snapshot = await scanner.scan(enabled: enabled, includeEstimated: includeEstimated)
            self.ledger = snapshot.ledger
            for (id, status) in snapshot.statuses where status != self.sourceStatuses[id] {
                if case .error(let message, _) = status { AppLog.error("読み取りエラー \(id): \(message)") }
            }
            self.sourceStatuses = snapshot.statuses
            self.lastScanAt = snapshot.scannedAt
            self.isScanning = false
            self.detectedSources = scanner.detectedSources()
            let gained = snapshot.ledger.coinsEarned - before
            if gained > 0 {
                self.toast = String(localized: "AIの利用で \(gained) コイン増えました")
                self.sfx(.coin, spontaneous: true)
            }
            self.evaluateProgress()
            self.save()
        }
    }

    func setSource(_ id: String, enabled: Bool) {
        if enabled { settings.enabledSources.insert(id) } else { settings.enabledSources.remove(id) }
    }

    // MARK: 初回設定

    func completeOnboarding(enabled: Set<String>, mode: DisplayMode) {
        var s = settings
        s.enabledSources = enabled
        s.displayMode = mode
        s.onboarded = true
        settings = s
        scanNow()
        requestNotificationPermission()
    }

    // MARK: ログイン時の起動

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                toast = String(localized: "ログイン時の起動を設定できませんでした: \(error.localizedDescription)")
            }
        }
    }

    // MARK: 保存

    /// 保存する。`periodic` は時間経過だけの定期的な保存（iCloud Drive へは間引く）。
    func save(periodic: Bool = false) {
        evaluateProgress()
        // 泳いでいる位置も覚えておく
        for i in state.tank.fish.indices {
            if let pos = engine.position(of: state.tank.fish[i].id) {
                state.tank.fish[i].x = pos.x
                state.tank.fish[i].y = pos.y
            }
        }
        state.savedAt = Date()
        state.savedBy = settings.machineID
        write(state, to: "game.json")
        if settings.iCloudSync {
            // 操作したときはすぐ、時間経過だけのときは数分に1回まで
            let due = lastPushedAt.map { Date().timeIntervalSince($0) >= Self.periodicPushInterval } ?? true
            if !periodic || due { pushToICloud() }
        }
    }

    func saveSettings() { write(settings, to: "settings.json") }

    func write<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try JSONEncoder.tokarium.encode(value)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            AppLog.error("\(name) を保存できませんでした: \(error.localizedDescription)")
        }
    }

    func settingsChanged(from old: AppSettings) {
        if old.displayMode != settings.displayMode || old.desktopScreens != settings.desktopScreens || old.fps != settings.fps
            || old.styleID != settings.styleID {
            onDisplaySettingsChanged?()
        }
        if old.enabledSources != settings.enabledSources || old.includeEstimated != settings.includeEstimated {
            scanNow()
        }
        if old.remindersEnabled != settings.remindersEnabled || old.reminderTimes != settings.reminderTimes
            || old.notificationsEnabled != settings.notificationsEnabled {
            scheduleReminders()
        }
        if settings.iCloudSync && !old.iCloudSync { startICloudSync() }
        SoundPlayer.shared.config = settings.soundConfig
    }

    /// 効果音を鳴らす。`spontaneous` は操作によらず起きたことで、水槽の窓が見えているときだけ鳴らす。
    func sfx(_ effect: SoundEffect, spontaneous: Bool = false) {
        SoundPlayer.shared.play(effect, spontaneous: spontaneous)
    }
}
