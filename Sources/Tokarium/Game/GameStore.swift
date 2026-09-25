import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case window, desktop
    var id: String { rawValue }
    var label: String { self == .window ? String(localized: "ウィンドウ表示") : String(localized: "デスクトップ表示") }
}

enum DesktopScreens: String, Codable, CaseIterable, Identifiable {
    case main, all
    var id: String { rawValue }
    var label: String { self == .main ? String(localized: "メインのディスプレイのみ") : String(localized: "すべてのディスプレイ（同じ水槽を表示）") }
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
    /// 時間帯で水槽の明るさを変える。
    var timeOfDay = true
    /// 季節の浮遊物（花びら・葉・マリンスノー）。
    var seasons = true
    /// お世話のリマインド（分: 0〜1439）。
    var remindersEnabled = false
    var reminderTimes: [Int] = [9 * 60, 20 * 60]
    /// iCloud Drive で水槽を同期する。
    var iCloudSync = false
    /// この Mac の識別子（同期でどの Mac が保存したかを見分ける）。
    var machineID = UUID().uuidString
    /// バッテリーや低電力モードのとき、自動で動きを控えめにする。
    var autoPowerSaving = true
    /// 初回のチュートリアルを見終わった。
    var tutorialDone = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? d.onboarded
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? d.displayMode
        desktopScreens = try c.decodeIfPresent(DesktopScreens.self, forKey: .desktopScreens) ?? d.desktopScreens
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        enabledSources = try c.decodeIfPresent(Set<String>.self, forKey: .enabledSources) ?? d.enabledSources
        includeEstimated = try c.decodeIfPresent(Bool.self, forKey: .includeEstimated) ?? d.includeEstimated
        styleID = try c.decodeIfPresent(String.self, forKey: .styleID) ?? d.styleID
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        timeOfDay = try c.decodeIfPresent(Bool.self, forKey: .timeOfDay) ?? d.timeOfDay
        seasons = try c.decodeIfPresent(Bool.self, forKey: .seasons) ?? d.seasons
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        reminderTimes = try c.decodeIfPresent([Int].self, forKey: .reminderTimes) ?? d.reminderTimes
        iCloudSync = try c.decodeIfPresent(Bool.self, forKey: .iCloudSync) ?? d.iCloudSync
        machineID = try c.decodeIfPresent(String.self, forKey: .machineID) ?? d.machineID
        autoPowerSaving = try c.decodeIfPresent(Bool.self, forKey: .autoPowerSaving) ?? d.autoPowerSaving
        // すでに遊んでいる人にはチュートリアルを出さない
        tutorialDone = try c.decodeIfPresent(Bool.self, forKey: .tutorialDone) ?? onboarded
    }
}

struct BugReportRequest: Identifiable {
    let id = UUID()
    var crash: Diagnostics.CrashInfo?
}

@MainActor
@Observable
final class GameStore {
    fileprivate(set) var state: GameState
    var settings: AppSettings { didSet { if settings != oldValue { saveSettings(); settingsChanged(from: oldValue) } } }
    fileprivate(set) var ledger: UsageLedger
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
    /// 置き場所を決めている最中の装飾（買った直後や持ち物から出したとき）。
    var placingDecoration: UUID?

    @ObservationIgnored let engine = SwimEngine()
    let power = PowerMonitor()

    /// 省電力を考えたアニメーションの速さ。
    var effectiveFPS: Int { power.fps(base: settings.fps, auto: settings.autoPowerSaving) }
    @ObservationIgnored fileprivate let scanner: UsageScanner
    @ObservationIgnored let dir: URL
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onDisplaySettingsChanged: (() -> Void)?

    var style: AquariumStyle { AquariumStyles.style(settings.styleID) }

    var coins: Int { state.initialCoins + ledger.coinsEarned + otherMacsEarned - state.coinsSpent }
    /// iCloud Drive で同期しているほかの Mac で得たコイン。
    private(set) var otherMacsEarned = 0
    @ObservationIgnored private var lastPulledModified: Date?
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
        save()
    }

    private func announce(_ report: Simulation.Report) {
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
            if gained > 0 { self.toast = String(localized: "AIの利用で \(gained) コイン増えました") }
            self.evaluateProgress()
            self.save()
        }
    }

    func setSource(_ id: String, enabled: Bool) {
        if enabled { settings.enabledSources.insert(id) } else { settings.enabledSources.remove(id) }
    }

    // MARK: お世話

    /// コインも餌もないときの救済: 1日1回分だけ無料で餌をあげられる。
    var rescueFoodAvailable: Bool {
        let cheapest = Catalog.foodPacks.map(\.price).min() ?? 0
        return state.food == 0 && coins < cheapest && state.lastRescueDay != DayKey.key(Date()) && !livingFish.isEmpty
    }

    /// 餌やりができるか（餌があるか、救済の餌が使えるか）。
    var canFeed: Bool { state.food > 0 || rescueFoodAvailable }

    /// 餌を1つ使う。なければ知らせて false。
    private func useFood() -> Bool {
        if state.food == 0 && rescueFoodAvailable {
            state.lastRescueDay = DayKey.key(Date())
            toast = String(localized: "コインも餌もないので、今日の1回分は無料であげました。AIを使うとコインが貯まります")
            return true
        }
        guard state.food > 0 else {
            toast = String(localized: "餌がありません。お店で買えます")
            return false
        }
        state.food -= 1
        if state.food == 0 {
            post(title: String(localized: "餌がなくなりました"), body: String(localized: "お店で餌を買ってください。"))
        } else if state.food <= Catalog.lowFood {
            toast = String(localized: "餌が残り \(state.food) 回分です")
        }
        return true
    }

    func feed() {
        simulate()
        guard !livingFish.isEmpty else { toast = String(localized: "餌を食べる魚がいません"); return }
        guard useFood() else { return }
        Simulation.feed(&state, now: Date())
        state.stats.feedings += 1
        engine.dropFood(count: min(24, 4 + livingFish.count * 2))
        save()
    }

    /// 1匹だけに餌をあげる（その魚の近くに餌を落とす）。
    func feed(fish id: UUID) {
        simulate()
        guard let f = state.tank.fish.first(where: { $0.id == id }), f.isAlive else { return }
        guard useFood() else { return }
        Simulation.feed(&state, fish: id, now: Date())
        state.stats.feedings += 1
        engine.dropFood(count: 4, near: engine.position(of: id)?.x ?? f.x)
        toast = String(localized: "\(f.name)に餌をあげました")
        save()
    }

    func changeWater() {
        simulate()
        Simulation.changeWater(&state, now: Date())
        state.stats.waterChanges += 1
        toast = String(localized: "水をきれいにしました")
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.tank.fish[i].name = String(trimmed.prefix(20))
        save()
    }

    /// お気に入りの魚（主役は1匹）。
    var favoriteFish: Fish? { state.tank.fish.first { $0.isFavorite } }

    /// お気に入りにする（ほかの魚のお気に入りは外す）。もう一度押すと外す。
    func toggleFavorite(_ id: UUID) {
        let wasFavorite = state.tank.fish.first { $0.id == id }?.isFavorite ?? false
        for i in state.tank.fish.indices { state.tank.fish[i].isFavorite = !wasFavorite && state.tank.fish[i].id == id }
        if let f = favoriteFish { toast = String(localized: "\(f.name)をお気に入り（主役）にしました") }
        save()
    }

    /// 死んだ魚とお別れする（水槽から取り出す）。
    func farewell(_ id: UUID) {
        state.tank.fish.removeAll { $0.id == id && !$0.isAlive }
        state.notifiedDangerFish.remove(id)
        save()
    }

    // MARK: 図鑑・実績・ごほうび

    /// 実績・記念の魚・宝箱を確かめる。
    func evaluateProgress(now: Date = Date()) {
        let ctx = AchievementContext(state: state, coinsEarned: ledger.coinsEarned, now: now)
        for a in Achievements.all where state.achievements[a.id] == nil && a.isUnlocked(ctx) {
            state.achievements[a.id] = now
            var body = a.detail
            if let reward = a.reward {
                let kind = Catalog.decoration(reward)
                state.tank.decorations.append(Decoration(kindID: reward, isPlaced: false, x: 0.5))
                body += String(localized: "（ごほうび: \(kind.name) を持ち物に入れました）")
            }
            toast = String(localized: "実績「\(a.title)」を達成しました")
            post(title: String(localized: "実績「\(a.title)」を達成"), body: body)
        }

        // よく使うAIの記念の魚
        for m in MemorialFish.all where !state.memorialsGiven.contains(m.group) && ledger.coins(from: m.sources) >= MemorialFish.threshold {
            state.memorialsGiven.insert(m.group)
            let sp = Catalog.species(m.speciesID)
            if livingFish.count < state.tank.size.maxFish {
                state.addFish(Fish(speciesID: sp.id, name: sp.name, fullness: 80, purchasedAt: now, growth: 1,
                                   x: .random(in: 0.2...0.8), y: 0.3), at: now)
                toast = String(localized: "\(m.label) の記念に「\(sp.name)」がやってきました")
                post(title: String(localized: "記念の魚がやってきました"), body: String(localized: "\(m.label) をたくさん使った記念に、\(sp.name)が水槽に入りました。"))
            } else {
                // 水槽がいっぱいなら、空いたときにもう一度ためす
                state.memorialsGiven.remove(m.group)
            }
        }

        // AIをたくさん使った日は宝箱が流れてくる
        let today = DayKey.key(now)
        if state.lastTreasureDay != today, state.treasureX == nil, ledger.coins(on: today) >= Double(TreasureRule.dailyCoins) {
            state.lastTreasureDay = today
            state.treasureX = .random(in: 0.15...0.85)
            toast = String(localized: "今日はAIをたくさん使いました！ 宝箱が流れてきました")
        }
    }

    /// 宝箱を開ける。
    func openTreasure() {
        guard state.treasureX != nil else { return }
        state.treasureX = nil
        state.food += TreasureRule.rewardFood
        state.medicine += TreasureRule.rewardMedicine
        state.stats.treasures += 1
        toast = String(localized: "宝箱から餌 \(TreasureRule.rewardFood) 回分と薬 \(TreasureRule.rewardMedicine) 個が出てきました")
        evaluateProgress()
        save()
    }

    /// 水槽をたたく（魚が寄ってくる）。
    func touchWater(x: Double, y: Double) {
        engine.touch(x: x, y: y)
        state.stats.touches += 1
    }

    @discardableResult
    func buyEquipment(_ e: Equipment) -> PurchaseError? {
        guard !state.equipment.contains(e.id) else { return nil }
        guard coins >= e.price else { return .notEnoughCoins }
        state.coinsSpent += e.price
        state.equipment.insert(e.id)
        toast = String(localized: "\(e.name)を取りつけました")
        save()
        return nil
    }

    // MARK: お店

    enum PurchaseError: LocalizedError {
        case notEnoughCoins, tankFull, tooManyDecorations, maxSize
        var errorDescription: String? {
            switch self {
            case .notEnoughCoins: return String(localized: "コインが足りません")
            case .tankFull: return String(localized: "水槽がいっぱいです。お店で水槽を大きくできます")
            case .tooManyDecorations: return String(localized: "これ以上は置けません。持ち物に入りました。お店で水槽を大きくできます")
            case .maxSize: return String(localized: "これ以上大きな水槽はありません")
            }
        }
    }

    @discardableResult
    func buyFish(_ sp: FishSpecies) -> PurchaseError? {
        guard coins >= sp.price else { return .notEnoughCoins }
        guard livingFish.count < state.tank.size.maxFish else { return .tankFull }
        let n = state.tank.fish.filter { $0.speciesID == sp.id }.count + 1
        let fish = Fish(speciesID: sp.id, name: String(localized: "\(sp.name) \(n)号"), fullness: 70, purchasedAt: Date(),
                        x: .random(in: 0.2...0.8), y: sp.zone == .bottom ? 0.82 : 0.15)
        state.addFish(fish, at: Date())
        state.stats.fishBought += 1
        state.coinsSpent += sp.price
        toast = String(localized: "\(sp.name)を水槽に入れました")
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
        state.stats.decorationsBought += 1
        save()
        if !d.isPlaced { return .tooManyDecorations }
        // 置き場所はユーザーが水槽で決める
        placingDecoration = d.id
        return nil
    }

    @discardableResult
    func buyMedicine() -> PurchaseError? {
        guard coins >= Catalog.medicinePrice else { return .notEnoughCoins }
        state.coinsSpent += Catalog.medicinePrice
        state.medicine += 1
        toast = String(localized: "薬を買いました（持っている数: \(state.medicine)）")
        save()
        return nil
    }

    @discardableResult
    func buyFood(_ pack: FoodPack) -> PurchaseError? {
        guard coins >= pack.price else { return .notEnoughCoins }
        state.coinsSpent += pack.price
        state.food += pack.servings
        toast = String(localized: "餌を買いました（残り \(state.food) 回分）")
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
        toast = String(localized: "\(next.name)になりました（魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで）")
        save()
        return nil
    }

    func giveMedicine(_ id: UUID) {
        simulate()
        if Simulation.giveMedicine(&state, fish: id) {
            toast = String(localized: "薬をあげました")
            save()
        } else if state.medicine == 0 {
            toast = String(localized: "薬がありません。お店で買えます")
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
            toast = String(localized: "これ以上は置けません")
            return
        }
        state.tank.decorations[i].isPlaced = placed
        placingDecoration = placed ? id : (placingDecoration == id ? nil : placingDecoration)
        save()
    }

    /// 置き場所を決める。
    func finishPlacing() {
        guard let id = placingDecoration, let d = state.tank.decorations.first(where: { $0.id == id }) else { return }
        placingDecoration = nil
        toast = String(localized: "\(d.kind.name)を置きました")
        save()
    }

    /// 置くのをやめて持ち物にしまう。
    func cancelPlacing() {
        guard let id = placingDecoration else { return }
        setDecoration(id, placed: false)
        placingDecoration = nil
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
                post(title: String(localized: "\(f.name)が危険な状態です"), body: String(localized: "餌やりと水換えをしてあげてください。"))
            } else if f.condition != .critical && f.isAlive {
                state.notifiedDangerFish.remove(f.id)
            }
            if old?.isAlive == true && !f.isAlive {
                post(title: (f.deathCause ?? .neglect).message(name: f.name), body: String(localized: "お世話画面でお別れできます。"))
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
                toast = String(localized: "ログイン時の起動を設定できませんでした: \(error.localizedDescription)")
            }
        }
    }

    // MARK: 保存

    func save() {
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
        if settings.iCloudSync { pushToICloud() }
    }

    private func saveSettings() { write(settings, to: "settings.json") }

    fileprivate func write<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try JSONEncoder.tokarium.encode(value)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            AppLog.error("\(name) を保存できませんでした: \(error.localizedDescription)")
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
        if old.remindersEnabled != settings.remindersEnabled || old.reminderTimes != settings.reminderTimes
            || old.notificationsEnabled != settings.notificationsEnabled {
            scheduleReminders()
        }
        if settings.iCloudSync && !old.iCloudSync { startICloudSync() }
    }
}

// MARK: - お世話のリマインド

extension GameStore {
    /// 決まった時刻に「そろそろ餌の時間です」を知らせる（毎日くり返す）。
    func scheduleReminders() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let ids = (0..<10).map { "tokarium-reminder-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard settings.remindersEnabled, settings.notificationsEnabled else { return }
        requestNotificationPermission()
        for (i, minutes) in settings.reminderTimes.prefix(ids.count).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "そろそろ餌の時間です")
            content.body = String(localized: "水槽の魚たちが待っています。")
            var when = DateComponents()
            when.hour = minutes / 60
            when.minute = minutes % 60
            center.add(UNNotificationRequest(identifier: ids[i], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
    }
}

// MARK: - バックアップと復元

/// 書き出すデータ一式。
struct TokariumBackup: Codable {
    var format = 1
    var exportedAt: Date
    var appVersion: String
    var game: GameState
    var settings: AppSettings
    var ledger: UsageLedger
}

extension GameStore {
    func makeBackup() -> TokariumBackup {
        save()
        return TokariumBackup(exportedAt: Date(), appVersion: Diagnostics.appVersion, game: state, settings: settings, ledger: ledger)
    }

    func exportBackup(to url: URL) throws {
        let data = try JSONEncoder.tokarium.encode(makeBackup())
        try data.write(to: url, options: .atomic)
        toast = String(localized: "バックアップを書き出しました")
    }

    /// バックアップから復元する。この Mac の識別子と、この Mac でだけ意味のある設定は残す。
    func importBackup(from url: URL) throws {
        let backup = try JSONDecoder.tokarium.decode(TokariumBackup.self, from: Data(contentsOf: url))
        var newSettings = backup.settings
        newSettings.machineID = settings.machineID
        newSettings.displayMode = settings.displayMode
        newSettings.desktopScreens = settings.desktopScreens
        state = backup.game
        state.lastSimulatedAt = min(state.lastSimulatedAt, Date())
        engine.reset()
        settings = newSettings
        ledger = backup.ledger
        Task { await scanner.replaceLedger(backup.ledger) }
        save()
        toast = String(localized: "バックアップから復元しました")
    }
}

// MARK: - iCloud Drive で同期

extension GameStore {
    /// iCloud Drive の中の Tokarium フォルダ（iCloud Drive が使えなければ nil）。
    static var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Tokarium", isDirectory: true)
    }

    /// 同期を始める。iCloud Drive に新しい水槽があればそれを使い、なければこの Mac の水槽を置く。
    func startICloudSync() {
        guard let folder = Self.iCloudFolder else {
            settings.iCloudSync = false
            toast = String(localized: "iCloud Drive が見つかりません。システム設定で iCloud Drive をオンにしてください")
            return
        }
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("earned"), withIntermediateDirectories: true)
        lastPulledModified = nil
        if pullFromICloud() {
            toast = String(localized: "iCloud Drive の水槽を読み込みました")
        } else {
            pushToICloud()
            toast = String(localized: "この Mac の水槽を iCloud Drive に置きました")
        }
    }

    /// 他の Mac が保存した新しい水槽があれば読み込む。読み込んだら true。
    @discardableResult
    func pullFromICloud() -> Bool {
        guard let folder = Self.iCloudFolder else { return false }
        refreshOtherMacsEarned(folder)
        let url = folder.appendingPathComponent("game.json")
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              modified != lastPulledModified else { return false }
        lastPulledModified = modified
        guard let data = try? Data(contentsOf: url), let remote = try? JSONDecoder.tokarium.decode(GameState.self, from: data),
              remote.savedBy != settings.machineID, let remoteSaved = remote.savedAt,
              remoteSaved > (state.savedAt ?? .distantPast) else { return false }
        // 通貨の付与開始日時はこの Mac のものを使う（この Mac の利用記録の基準）
        let createdAt = state.createdAt
        state = remote
        state.createdAt = min(createdAt, remote.createdAt)
        write(state, to: "game.json")
        AppLog.info("iCloud Drive から水槽を読み込みました")
        return true
    }

    func pushToICloud() {
        guard let folder = Self.iCloudFolder else { return }
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("earned"), withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("game.json")
            try JSONEncoder.tokarium.encode(state).write(to: url, options: .atomic)
            lastPulledModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            // この Mac で得たコイン（ほかの Mac の残高に足される）
            let earned = ["coins": ledger.coinsEarned]
            try JSONEncoder.tokarium.encode(earned).write(to: folder.appendingPathComponent("earned/\(settings.machineID).json"), options: .atomic)
        } catch {
            AppLog.error("iCloud Drive に保存できませんでした: \(error.localizedDescription)")
        }
    }

    private func refreshOtherMacsEarned(_ folder: URL) {
        let dir = folder.appendingPathComponent("earned")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        otherMacsEarned = files.filter { $0.pathExtension == "json" && $0.deletingPathExtension().lastPathComponent != settings.machineID }
            .compactMap { try? JSONDecoder.tokarium.decode([String: Int].self, from: Data(contentsOf: $0))["coins"] }
            .reduce(0, +)
    }
}
