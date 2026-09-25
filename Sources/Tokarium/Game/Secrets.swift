import Foundation

// MARK: - 隠れた魚

/// 条件がそろうと、ときどき水槽に迷いこんでくる魚。
struct SecretFish {
    let speciesID: String
    /// 図鑑に出すヒント。
    let hint: String
    let isMet: (GameState, Date) -> Bool

    /// 条件がそろっているとき、1時間あたりに現れる確率。
    static let chancePerHour = 0.08

    static let glowing: Set<String> = ["gems", "starlamp", "lighthouse", "pumpkin", "glassfloat", "crystal", "stonelantern", "moonstone"]
    static let caves: Set<String> = ["arch", "ship", "castle", "goldcastle", "ryugu"]

    static let all: [SecretFish] = [
        SecretFish(speciesID: "hotaru", hint: String(localized: "夜、光るものが置いてある、きれいな水に…")) { s, now in
            let h = Calendar.current.component(.hour, from: now)
            return (h >= 21 || h < 5) && s.tank.waterQuality >= 70 && placed(s, glowing)
        },
        SecretFish(speciesID: "cavefish", hint: String(localized: "くぐれる場所があり、水がとてもきれいな水槽に…")) { s, _ in
            s.tank.waterQuality >= 85 && placed(s, caves)
        },
        SecretFish(speciesID: "rainbowmedaka", hint: String(localized: "いろいろな品種（5つ以上）を育てた人のもとに…")) { s, _ in
            s.variantsDiscovered >= 5
        },
        SecretFish(speciesID: "oarfish", hint: String(localized: "特大の水槽に、15匹以上の仲間がいると…")) { s, _ in
            s.tank.level >= Catalog.tankSizes.count - 1 && s.tank.fish.filter(\.isAlive).count >= 15
        },
        SecretFish(speciesID: "coelacanth", hint: String(localized: "ランク12以上。遺跡の柱と、天寿をまっとうした魚の記憶…")) { s, _ in
            s.rank >= 12 && placed(s, ["pillars"]) && s.dex.values.contains { $0.oldAge > 0 }
        },
    ]

    private static func placed(_ s: GameState, _ ids: Set<String>) -> Bool {
        s.tank.decorations.contains { $0.isPlaced && ids.contains($0.kindID) }
    }

    static func secret(_ speciesID: String) -> SecretFish? { all.first { $0.speciesID == speciesID } }
}

extension GameState {
    /// 図鑑に登録した品種の数（全種類の合計。原種は数えない）。
    var variantsDiscovered: Int { dex.values.reduce(0) { $0 + $1.variants.filter { $0 != .wild }.count } }

    /// 条件のそろった隠れた魚を、ときどき水槽に呼ぶ。まだ出会っていない魚だけ。
    mutating func visitSecretFish<R: RandomNumberGenerator>(hours: Double, now: Date, rng: inout R) -> Fish? {
        guard hours > 0, tank.fish.filter(\.isAlive).count < tank.size.maxFish else { return nil }
        let p = 1 - pow(1 - SecretFish.chancePerHour, min(hours, 6))
        for secret in SecretFish.all where dex[secret.speciesID] == nil && secret.isMet(self, now) {
            guard Double.random(in: 0..<1, using: &rng) < p else { continue }
            let sp = Catalog.species(secret.speciesID)
            let fish = Fish(speciesID: sp.id, name: sp.name, fullness: 70, purchasedAt: now, growth: 1,
                            x: .random(in: 0.2...0.8, using: &rng), y: 0.3)
            addFish(fish, at: now)
            return fish
        }
        return nil
    }
}

// MARK: - 殿堂（個体の記録）

/// お別れした魚の思い出。
struct FishMemory: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var speciesID: String
    var genotype: Genotype
    var isShiny: Bool
    var generation: Int
    var bornAt: Date
    var diedAt: Date
    var cause: DeathCause
    var size: Double
    var growth: Double
    var affection: Double
    var personality: Personality

    init(_ f: Fish) {
        id = f.id
        name = f.name
        speciesID = f.speciesID
        genotype = f.genotype
        isShiny = f.isShiny
        generation = f.generation
        bornAt = f.bornAt
        diedAt = f.diedAt ?? Date()
        cause = f.deathCause ?? .neglect
        size = f.size
        growth = f.growth
        affection = f.affection
        personality = f.personality
    }

    /// 思い出を魚の形に戻す（記録の比べやすさのため）。
    var asFish: Fish {
        var f = Fish(id: id, speciesID: speciesID, name: name, purchasedAt: bornAt, bornAt: bornAt, growth: growth)
        f.genotype = genotype
        f.isShiny = isShiny
        f.generation = generation
        f.isAlive = false
        f.diedAt = diedAt
        f.deathCause = cause
        f.size = size
        f.affection = affection
        f.personality = personality
        return f
    }
}

/// 殿堂に飾る記録。
struct HallRecord: Identifiable {
    let id: String
    let title: String
    let fish: Fish
    let value: String
}

enum Hall {
    /// 残しておく思い出の数。
    static let maxMemories = 100

    static func records(_ state: GameState, now: Date = Date()) -> [HallRecord] {
        let all = state.tank.fish + state.memories.map(\.asFish)
        guard !all.isEmpty else { return [] }
        var list: [HallRecord] = []
        if let f = all.max(by: { $0.ageDays(at: $0.diedAt ?? now) < $1.ageDays(at: $1.diedAt ?? now) }) {
            list.append(HallRecord(id: "age", title: String(localized: "いちばん長生き"), fish: f,
                                   value: String(localized: "\(Int(f.ageDays(at: f.diedAt ?? now)))日")))
        }
        if let f = all.max(by: { $0.lengthCM < $1.lengthCM }) {
            list.append(HallRecord(id: "size", title: String(localized: "いちばん大きい"), fish: f,
                                   value: String(format: String(localized: "%.1fcm"), f.lengthCM)))
        }
        if let f = all.max(by: { $0.generation < $1.generation }), f.generation > 1 {
            list.append(HallRecord(id: "generation", title: String(localized: "いちばん新しい世代"), fish: f,
                                   value: String(localized: "\(f.generation)代目")))
        }
        if let f = all.max(by: { $0.affection < $1.affection }), f.affection > 0 {
            list.append(HallRecord(id: "affection", title: String(localized: "いちばんのなかよし"), fish: f,
                                   value: String(localized: "なつき度 \(Int(f.affection))")))
        }
        return list
    }
}
