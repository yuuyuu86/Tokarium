import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case window, desktop
    var id: String { rawValue }
    var label: String { self == .window ? "ウィンドウ表示" : "デスクトップ表示" }
}

enum DesktopScreens: String, Codable, CaseIterable, Identifiable {
    case main, all
    var id: String { rawValue }
    var label: String { self == .main ? "メインのディスプレイのみ" : "すべてのディスプレイ" }
}

struct AppSettings: Codable, Equatable {
    var onboarded = false
    var displayMode: DisplayMode = .window
    var desktopScreens: DesktopScreens = .main
    var fps: Int = 30
    var enabledSources: Set<String> = []
    var includeEstimated = false
    var styleID = "pixel"
    var notificationsEnabled = true
}

@MainActor
@Observable
final class GameStore {
    private(set) var state: GameState
    var settings: AppSettings { didSet { if settings != oldValue { saveSettings(); settingsChanged(from: oldValue) } } }
    private(set) var ledger: UsageLedger
    private(set) var sourceStatuses: [String: SourceStatus] = [:]
    private(set) var lastScanAt: Date?
    private(set) var isScanning = false
    private(set) var detectedSources: Set<String> = []
    /// 再開時に反映した内容のお知らせ。
    var resumeMessage: String?
    /// 画面に出す一時的なお知らせ。
    var toast: String?

    @ObservationIgnored let engine = SwimEngine()
    @ObservationIgnored private let scanner: UsageScanner
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onDisplaySettingsChanged: (() -> Void)?

    var style: AquariumStyle { AquariumStyles.style(settings.styleID) }

    var coins: Int { state.initialCoins + ledger.coinsEarned - state.coinsSpent }
    var livingFish: [Fish] { state.tank.fish.filter(\.isAlive) }
    var dangerFish: [Fish] { state.tank.fish.filter { $0.condition.isDanger } }

    init(directory: URL? = nil) {
        // 動作確認用に保存先を差し替えられる
        let override = ProcessInfo.processInfo.environment["TOKARIUM_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        let dir = directory ?? override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokarium", isDirectory: true)
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let loaded = (try? Data(contentsOf: dir.appendingPathComponent("game.json")))
            .flatMap { try? JSONDecoder.tokarium.decode(GameState.self, from: $0) }
        let state = loaded ?? GameState.newGame()
        self.state = state
        self.settings = (try? Data(contentsOf: dir.appendingPathComponent("settings.json")))
            .flatMap { try? JSONDecoder.tokarium.decode(AppSettings.self, from: $0) } ?? AppSettings()
        let scanner = UsageScanner(ledgerURL: dir.appendingPathComponent("usage-ledger.json"), startDate: state.createdAt)
        self.scanner = scanner
        self.ledger = UsageLedger(startDate: state.createdAt)
        self.detectedSources = scanner.detectedSources()
        if loaded == nil { save() }
        Task { self.ledger = await scanner.currentLedger }
    }

    // MARK: 起動・時間経過

    func start() {
        simulate()
        timers.append(Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.simulate() }
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
    }

    /// 経過時間を反映する。起動中・スリープ明け・再起動のすべてでこれを使う。
    func simulate(now: Date = Date()) {
        let before = state.tank.fish
        let report = Simulation.advance(&state, to: now)
        if report.isCatchUp && report.simulated > 30 * 60 {
            var msg = "離れていた間の \(Self.durationText(report.simulated)) を水槽に反映しました。"
            if report.skipped > 0 {
                msg += "（\(Self.durationText(Simulation.maxCatchUp)) を超えた分は反映していません）"
            }
            let hungry = state.tank.fish.filter { $0.isAlive && $0.condition != .healthy }.count
            if hungry > 0 { msg += " お世話が必要な魚が \(hungry) 匹います。" }
            resumeMessage = msg
        }
        announce(report)
        notifyChanges(before: before)
        save()
    }

    private func announce(_ report: Simulation.Report) {
        if !report.births.isEmpty {
            let name = report.births[0].species.name
            toast = "\(name)の稚魚が \(report.births.count) 匹生まれました"
            post(title: "稚魚が生まれました", body: "\(name)の稚魚が \(report.births.count) 匹生まれました。")
        }
        for f in report.newlySick {
            post(title: "\(f.name)が病気になりました", body: "お店で薬を買って、お世話画面であげてください。水換えも効果的です。")
        }
        if let f = report.grownUp.first {
            toast = "\(f.name)が成魚になりました"
        }
    }

    static func durationText(_ t: TimeInterval) -> String {
        let h = Int(t / 3600)
        if h >= 24 { return "\(h / 24)日\(h % 24 > 0 ? "\(h % 24)時間" : "")" }
        if h >= 1 { return "\(h)時間" }
        return "\(max(1, Int(t / 60)))分"
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
            self.sourceStatuses = snapshot.statuses
            self.lastScanAt = snapshot.scannedAt
            self.isScanning = false
            self.detectedSources = scanner.detectedSources()
            let gained = snapshot.ledger.coinsEarned - before
            if gained > 0 { self.toast = "AIの利用で \(gained) コイン増えました" }
        }
    }

    func setSource(_ id: String, enabled: Bool) {
        if enabled { settings.enabledSources.insert(id) } else { settings.enabledSources.remove(id) }
    }

    // MARK: お世話

    func feed() {
        simulate()
        guard !livingFish.isEmpty else { toast = "餌を食べる魚がいません"; return }
        Simulation.feed(&state, now: Date())
        engine.dropFood(count: min(24, 4 + livingFish.count * 2))
        save()
    }

    func changeWater() {
        simulate()
        Simulation.changeWater(&state, now: Date())
        toast = "水をきれいにしました"
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.tank.fish[i].name = String(trimmed.prefix(20))
        save()
    }

    /// 死んだ魚とお別れする（水槽から取り出す）。
    func farewell(_ id: UUID) {
        state.tank.fish.removeAll { $0.id == id && !$0.isAlive }
        state.notifiedDangerFish.remove(id)
        save()
    }

    // MARK: お店

    enum PurchaseError: LocalizedError {
        case notEnoughCoins, tankFull, tooManyDecorations, maxSize
        var errorDescription: String? {
            switch self {
            case .notEnoughCoins: return "コインが足りません"
            case .tankFull: return "水槽がいっぱいです。お店で水槽を大きくできます"
            case .tooManyDecorations: return "これ以上は置けません。持ち物に入りました。お店で水槽を大きくできます"
            case .maxSize: return "これ以上大きな水槽はありません"
            }
        }
    }

    @discardableResult
    func buyFish(_ sp: FishSpecies) -> PurchaseError? {
        guard coins >= sp.price else { return .notEnoughCoins }
        guard livingFish.count < state.tank.size.maxFish else { return .tankFull }
        let n = state.tank.fish.filter { $0.speciesID == sp.id }.count + 1
        let fish = Fish(speciesID: sp.id, name: "\(sp.name) \(n)号", fullness: 70, purchasedAt: Date(),
                        x: .random(in: 0.2...0.8), y: sp.zone == .bottom ? 0.82 : 0.15)
        state.tank.fish.append(fish)
        state.coinsSpent += sp.price
        toast = "\(sp.name)を水槽に入れました"
        save()
        return nil
    }

    @discardableResult
    func buyDecoration(_ kind: DecorationKind) -> PurchaseError? {
        guard coins >= kind.price else { return .notEnoughCoins }
        let placed = state.tank.decorations.filter(\.isPlaced).count
        let d = Decoration(kindID: kind.id, isPlaced: placed < state.tank.size.maxDecorations,
                           x: .random(in: 0.1...0.9), layer: Int.random(in: 0...1))
        state.tank.decorations.append(d)
        state.coinsSpent += kind.price
        save()
        if !d.isPlaced { return .tooManyDecorations }
        toast = "\(kind.name)を置きました"
        return nil
    }

    @discardableResult
    func buyMedicine() -> PurchaseError? {
        guard coins >= Catalog.medicinePrice else { return .notEnoughCoins }
        state.coinsSpent += Catalog.medicinePrice
        state.medicine += 1
        toast = "薬を買いました（持っている数: \(state.medicine)）"
        save()
        return nil
    }

    var nextTankSize: TankSize? {
        let next = state.tank.level + 1
        return next < Catalog.tankSizes.count ? Catalog.tankSizes[next] : nil
    }

    @discardableResult
    func buyTankUpgrade() -> PurchaseError? {
        guard let next = nextTankSize else { return .maxSize }
        guard coins >= next.price else { return .notEnoughCoins }
        state.coinsSpent += next.price
        state.tank.level = next.level
        toast = "\(next.name)になりました（魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで）"
        save()
        return nil
    }

    func giveMedicine(_ id: UUID) {
        simulate()
        if Simulation.giveMedicine(&state, fish: id) {
            toast = "薬をあげました"
            save()
        } else if state.medicine == 0 {
            toast = "薬がありません。お店で買えます"
        }
    }

    func moveDecoration(_ id: UUID, x: Double) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        state.tank.decorations[i].x = min(0.97, max(0.03, x))
    }

    func toggleDecorationLayer(_ id: UUID) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        state.tank.decorations[i].layer = state.tank.decorations[i].layer == 0 ? 1 : 0
        save()
    }

    func setDecoration(_ id: UUID, placed: Bool) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        if placed && state.tank.decorations.filter(\.isPlaced).count >= state.tank.size.maxDecorations {
            toast = "これ以上は置けません"
            return
        }
        state.tank.decorations[i].isPlaced = placed
        save()
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

    // MARK: 通知

    func requestNotificationPermission() {
        guard settings.notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyChanges(before: [Fish]) {
        for f in state.tank.fish {
            let old = before.first { $0.id == f.id }
            if f.condition.isDanger && !state.notifiedDangerFish.contains(f.id) {
                state.notifiedDangerFish.insert(f.id)
                post(title: "\(f.name)が危険な状態です", body: "餌やりと水換えをしてあげてください。")
            } else if f.condition != .critical && f.isAlive {
                state.notifiedDangerFish.remove(f.id)
            }
            if old?.isAlive == true && !f.isAlive {
                post(title: "\(f.name)が\((f.deathCause ?? .neglect).label)死んでしまいました", body: "お世話画面でお別れできます。")
            }
        }
    }

    private func post(title: String, body: String) {
        guard settings.notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: ログイン時の起動

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                toast = "ログイン時の起動を設定できませんでした: \(error.localizedDescription)"
            }
        }
    }

    // MARK: 保存

    func save() {
        // 泳いでいる位置も覚えておく
        for i in state.tank.fish.indices {
            if let pos = engine.position(of: state.tank.fish[i].id) {
                state.tank.fish[i].x = pos.x
                state.tank.fish[i].y = pos.y
            }
        }
        write(state, to: "game.json")
    }

    private func saveSettings() { write(settings, to: "settings.json") }

    private func write<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try JSONEncoder.tokarium.encode(value)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("Tokarium: \(name) を保存できませんでした: \(error)")
        }
    }

    private func settingsChanged(from old: AppSettings) {
        if old.displayMode != settings.displayMode || old.desktopScreens != settings.desktopScreens || old.fps != settings.fps
            || old.styleID != settings.styleID {
            onDisplaySettingsChanged?()
        }
        if old.enabledSources != settings.enabledSources || old.includeEstimated != settings.includeEstimated {
            scanNow()
        }
    }
}
