import Foundation

enum DeathCause: String, Codable {
    case neglect   // 空腹や水の汚れで弱った
    case illness   // 病気が悪化した
    case oldAge    // 寿命

    var label: String {
        switch self {
        case .neglect: return String(localized: "お世話不足")
        case .illness: return String(localized: "病気")
        case .oldAge: return String(localized: "寿命")
        }
    }

    func message(name: String) -> String {
        switch self {
        case .neglect: return String(localized: "\(name)が弱って死んでしまいました")
        case .illness: return String(localized: "\(name)が病気で死んでしまいました")
        case .oldAge: return String(localized: "\(name)が寿命を迎えました")
        }
    }
}

enum GrowthStage {
    case fry, juvenile, adult

    var label: String {
        switch self {
        case .fry: return String(localized: "稚魚")
        case .juvenile: return String(localized: "若魚")
        case .adult: return String(localized: "成魚")
        }
    }
}

struct Fish: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var speciesID: String
    var name: String
    /// 満腹度 0〜100（100=満腹）。
    var fullness: Double = 80
    /// 体調 0〜100。
    var health: Double = 100
    var isAlive: Bool = true
    var diedAt: Date?
    var deathCause: DeathCause?
    var purchasedAt: Date = Date()
    /// 生まれた日時（年齢と寿命の計算に使う）。
    var bornAt: Date = Date()
    /// 成長 0〜1（1=成魚）。
    var growth: Double = 0.4
    var isSick: Bool = false
    /// 何代目か（お店の魚は1代目）。
    var generation: Int = 1
    /// まれに生まれる色違い。
    var isShiny: Bool = false
    /// 水槽内の位置（0〜1 の正規化座標）。
    var x: Double = 0.5
    var y: Double = 0.5

    var species: FishSpecies { Catalog.species(speciesID) }

    var stage: GrowthStage {
        if growth >= 1 { return .adult }
        if growth >= 0.34 { return .juvenile }
        return .fry
    }

    func ageDays(at now: Date = Date()) -> Double {
        max(0, now.timeIntervalSince(bornAt) / 86400)
    }

    /// 寿命のうちどれだけ生きたか（0〜1以上）。
    func lifeFraction(at now: Date = Date()) -> Double {
        ageDays(at: diedAt ?? now) / species.lifespanDays
    }

    func isElderly(at now: Date = Date()) -> Bool {
        isAlive && lifeFraction(at: now) >= Simulation.elderlyFraction
    }

    init(id: UUID = UUID(), speciesID: String, name: String, fullness: Double = 80, health: Double = 100,
         purchasedAt: Date = Date(), bornAt: Date? = nil, growth: Double = 0.4, x: Double = 0.5, y: Double = 0.5) {
        self.id = id
        self.speciesID = speciesID
        self.name = name
        self.fullness = fullness
        self.health = health
        self.purchasedAt = purchasedAt
        // お店の魚は、寿命の1割ほど育った若魚として迎える
        self.bornAt = bornAt ?? purchasedAt.addingTimeInterval(-Catalog.species(speciesID).lifespanDays * 0.1 * 86400)
        self.growth = growth
        self.x = x
        self.y = y
    }

    // 古い保存データに無い項目は既定値で読む
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        speciesID = try c.decode(String.self, forKey: .speciesID)
        name = try c.decode(String.self, forKey: .name)
        fullness = try c.decodeIfPresent(Double.self, forKey: .fullness) ?? 80
        health = try c.decodeIfPresent(Double.self, forKey: .health) ?? 100
        isAlive = try c.decodeIfPresent(Bool.self, forKey: .isAlive) ?? true
        diedAt = try c.decodeIfPresent(Date.self, forKey: .diedAt)
        deathCause = try c.decodeIfPresent(DeathCause.self, forKey: .deathCause)
        purchasedAt = try c.decodeIfPresent(Date.self, forKey: .purchasedAt) ?? Date()
        bornAt = try c.decodeIfPresent(Date.self, forKey: .bornAt)
            ?? purchasedAt.addingTimeInterval(-Catalog.species(speciesID).lifespanDays * 0.1 * 86400)
        growth = try c.decodeIfPresent(Double.self, forKey: .growth) ?? 0.4
        isSick = try c.decodeIfPresent(Bool.self, forKey: .isSick) ?? false
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 1
        isShiny = try c.decodeIfPresent(Bool.self, forKey: .isShiny) ?? false
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
    }
}

struct Decoration: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kindID: String
    /// 配置済みか（false なら持ち物に入っている）。
    var isPlaced: Bool = true
    /// 砂の上の横位置（0〜1）。
    var x: Double = 0.5
    /// 手前/奥の重なり順。
    var layer: Int = 0

    var kind: DecorationKind { Catalog.decoration(kindID) }
}

struct Tank: Codable, Equatable {
    /// 水質 0〜100。
    var waterQuality: Double = 100
    var fish: [Fish] = []
    var decorations: [Decoration] = []
    /// 水槽の大きさ（拡張の段階）。
    var level: Int = 0

    var size: TankSize { Catalog.tankSize(level) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterQuality = try c.decodeIfPresent(Double.self, forKey: .waterQuality) ?? 100
        fish = try c.decodeIfPresent([Fish].self, forKey: .fish) ?? []
        decorations = try c.decodeIfPresent([Decoration].self, forKey: .decorations) ?? []
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
    }
}

struct GameState: Codable, Equatable {
    var version = 2
    /// 通貨付与の基準日時（確定: 初回起動日時）。
    var createdAt: Date = Date()
    /// シミュレーションを最後に進めた日時。
    var lastSimulatedAt: Date = Date()
    var tank = Tank()
    var coinsSpent: Int = 0
    var initialCoins: Int = Catalog.initialCoins
    var lastFedAt: Date?
    var lastWaterChangeAt: Date?
    /// 持っている薬の数。
    var medicine: Int = 0
    /// 持っている餌（回数）。
    var food: Int = Catalog.initialFood
    /// 最後に稚魚が生まれた日時。
    var lastBirthAt: Date?
    /// 危険通知を送った魚（重複通知を防ぐ）。
    var notifiedDangerFish: Set<UUID> = []
    /// 図鑑（種類ID → 記録）。
    var dex: [String: DexEntry] = [:]
    /// 達成した実績（ID → 日時）。
    var achievements: [String: Date] = [:]
    var stats = PlayStats()
    /// 持っている設備。
    var equipment: Set<String> = []
    var lastAutoFeedAt: Date?
    /// もらった記念の魚（AIのグループ）。
    var memorialsGiven: Set<String> = []
    /// 流れてきてまだ開けていない宝箱の横位置。
    var treasureX: Double?
    /// 宝箱が最後に流れてきた日。
    var lastTreasureDay: String?
    /// 最後に保存した日時と Mac（iCloud Drive 同期で新しい方を選ぶ）。
    var savedAt: Date?
    var savedBy: String?

    init(createdAt: Date = Date(), lastSimulatedAt: Date = Date()) {
        self.createdAt = createdAt
        self.lastSimulatedAt = lastSimulatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = 2
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastSimulatedAt = try c.decodeIfPresent(Date.self, forKey: .lastSimulatedAt) ?? Date()
        tank = try c.decodeIfPresent(Tank.self, forKey: .tank) ?? Tank()
        coinsSpent = try c.decodeIfPresent(Int.self, forKey: .coinsSpent) ?? 0
        initialCoins = try c.decodeIfPresent(Int.self, forKey: .initialCoins) ?? Catalog.initialCoins
        lastFedAt = try c.decodeIfPresent(Date.self, forKey: .lastFedAt)
        lastWaterChangeAt = try c.decodeIfPresent(Date.self, forKey: .lastWaterChangeAt)
        medicine = try c.decodeIfPresent(Int.self, forKey: .medicine) ?? 0
        food = try c.decodeIfPresent(Int.self, forKey: .food) ?? Catalog.initialFood
        lastBirthAt = try c.decodeIfPresent(Date.self, forKey: .lastBirthAt)
        notifiedDangerFish = try c.decodeIfPresent(Set<UUID>.self, forKey: .notifiedDangerFish) ?? []
        dex = try c.decodeIfPresent([String: DexEntry].self, forKey: .dex) ?? [:]
        achievements = try c.decodeIfPresent([String: Date].self, forKey: .achievements) ?? [:]
        stats = try c.decodeIfPresent(PlayStats.self, forKey: .stats) ?? PlayStats()
        equipment = try c.decodeIfPresent(Set<String>.self, forKey: .equipment) ?? []
        lastAutoFeedAt = try c.decodeIfPresent(Date.self, forKey: .lastAutoFeedAt)
        memorialsGiven = try c.decodeIfPresent(Set<String>.self, forKey: .memorialsGiven) ?? []
        treasureX = try c.decodeIfPresent(Double.self, forKey: .treasureX)
        lastTreasureDay = try c.decodeIfPresent(String.self, forKey: .lastTreasureDay)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
        savedBy = try c.decodeIfPresent(String.self, forKey: .savedBy)
        // 図鑑ができる前のデータは、いまいる魚から図鑑を作る
        if dex.isEmpty {
            for f in tank.fish { recordInDex(f, at: f.purchasedAt, born: false) }
        }
    }

    /// 魚を迎えたことを図鑑に書く。
    mutating func recordInDex(_ f: Fish, at date: Date, born: Bool) {
        var e = dex[f.speciesID] ?? DexEntry(firstSeenAt: date)
        e.owned += 1
        if born { e.born += 1 }
        e.maxGeneration = max(e.maxGeneration, f.generation)
        if f.isShiny { e.shiny += 1 }
        dex[f.speciesID] = e
    }

    /// 魚を水槽に入れる（図鑑にも書く）。
    mutating func addFish(_ f: Fish, at date: Date, born: Bool = false) {
        tank.fish.append(f)
        recordInDex(f, at: date, born: born)
    }

    static func newGame(now: Date = Date()) -> GameState {
        var state = GameState(createdAt: now, lastSimulatedAt: now)
        for (i, speciesID) in Catalog.initialFish.enumerated() {
            let sp = Catalog.species(speciesID)
            state.addFish(Fish(speciesID: speciesID, name: String(localized: "\(sp.name) \(i + 1)号"), fullness: 80, purchasedAt: now, x: 0.4, y: 0.45), at: now)
        }
        for (kindID, x) in Catalog.initialDecorations {
            state.tank.decorations.append(Decoration(kindID: kindID, x: x))
        }
        return state
    }
}

/// 魚の状態を言葉で表したもの（色だけに頼らない）。
enum FishCondition: Equatable {
    case healthy, hungry, sick, weak, critical, dead

    var label: String {
        switch self {
        case .healthy: return String(localized: "元気")
        case .hungry: return String(localized: "おなかがすいた")
        case .sick: return String(localized: "病気")
        case .weak: return String(localized: "弱っている")
        case .critical: return String(localized: "危険")
        case .dead: return String(localized: "死亡")
        }
    }

    var symbol: String {
        switch self {
        case .healthy: return "face.smiling"
        case .hungry: return "fork.knife"
        case .sick: return "cross.case"
        case .weak: return "bandage"
        case .critical: return "exclamationmark.triangle.fill"
        case .dead: return "xmark.circle"
        }
    }

    var isDanger: Bool { self == .critical }
}

extension Fish {
    var condition: FishCondition {
        if !isAlive { return .dead }
        if health < 25 { return .critical }
        if isSick { return .sick }
        if health < 60 { return .weak }
        if fullness < Simulation.hungryThreshold { return .hungry }
        return .healthy
    }
}

enum WaterCondition {
    case clean, slightlyDirty, dirty, veryDirty

    init(_ quality: Double) {
        switch quality {
        case 70...: self = .clean
        case 45..<70: self = .slightlyDirty
        case Simulation.dirtyWaterThreshold..<45: self = .dirty
        default: self = .veryDirty
        }
    }

    var label: String {
        switch self {
        case .clean: return String(localized: "きれい")
        case .slightlyDirty: return String(localized: "少しにごっている")
        case .dirty: return String(localized: "よごれている（病気になりやすい）")
        case .veryDirty: return String(localized: "とてもよごれている（魚が弱ります）")
        }
    }
}
