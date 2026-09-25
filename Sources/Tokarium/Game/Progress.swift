import CoreGraphics
import Foundation

// MARK: - 図鑑

/// 種類ごとの記録。
struct DexEntry: Codable, Equatable {
    var firstSeenAt: Date
    /// 迎えた数（買った・生まれた・もらった）。
    var owned = 0
    /// 水槽で生まれた数。
    var born = 0
    /// いちばん新しい世代（買った魚は1代目）。
    var maxGeneration = 1
    /// 寿命をまっとうした数。
    var oldAge = 0
    /// 色違いを迎えた数。
    var shiny = 0
    /// 迎えた品種。
    var variants: Set<FishVariant> = []

    init(firstSeenAt: Date) { self.firstSeenAt = firstSeenAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstSeenAt = try c.decode(Date.self, forKey: .firstSeenAt)
        owned = try c.decodeIfPresent(Int.self, forKey: .owned) ?? 0
        born = try c.decodeIfPresent(Int.self, forKey: .born) ?? 0
        maxGeneration = try c.decodeIfPresent(Int.self, forKey: .maxGeneration) ?? 1
        oldAge = try c.decodeIfPresent(Int.self, forKey: .oldAge) ?? 0
        shiny = try c.decodeIfPresent(Int.self, forKey: .shiny) ?? 0
        // 品種ができる前に迎えた魚は原種として数える
        variants = try c.decodeIfPresent(Set<FishVariant>.self, forKey: .variants) ?? [.wild]
    }
}

// MARK: - 数えておくこと

struct PlayStats: Codable, Equatable {
    var feedings = 0
    var waterChanges = 0
    var births = 0
    var deaths = 0
    var fishBought = 0
    var decorationsBought = 0
    var lastDeathAt: Date?
    var touches = 0
    var treasures = 0
    /// 里親に出した数。
    var adoptions = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedings = try c.decodeIfPresent(Int.self, forKey: .feedings) ?? 0
        waterChanges = try c.decodeIfPresent(Int.self, forKey: .waterChanges) ?? 0
        births = try c.decodeIfPresent(Int.self, forKey: .births) ?? 0
        deaths = try c.decodeIfPresent(Int.self, forKey: .deaths) ?? 0
        fishBought = try c.decodeIfPresent(Int.self, forKey: .fishBought) ?? 0
        decorationsBought = try c.decodeIfPresent(Int.self, forKey: .decorationsBought) ?? 0
        lastDeathAt = try c.decodeIfPresent(Date.self, forKey: .lastDeathAt)
        touches = try c.decodeIfPresent(Int.self, forKey: .touches) ?? 0
        treasures = try c.decodeIfPresent(Int.self, forKey: .treasures) ?? 0
        adoptions = try c.decodeIfPresent(Int.self, forKey: .adoptions) ?? 0
    }
}

// MARK: - 設備（一度買うとずっと働く）

struct Equipment: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let price: Int
    let symbol: String

    static let feeder = Equipment(id: "feeder", name: String(localized: "自動給餌器"),
                                  blurb: String(localized: "おなかをすかせた魚がいると、8時間に1回まで餌をあげます（餌を使います）。"),
                                  price: 300, symbol: "timer")
    static let filter = Equipment(id: "filter", name: String(localized: "ろ過フィルター"),
                                  blurb: String(localized: "水の汚れる速さが半分になります。"),
                                  price: 250, symbol: "wind")
    static let all = [feeder, filter]
}

// MARK: - 実績

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// もらえる限定の装飾。
    let reward: String?
    let isUnlocked: (AchievementContext) -> Bool
}

/// 実績の判定に使う情報。
struct AchievementContext {
    let state: GameState
    let coinsEarned: Int
    let now: Date

    var speciesSeen: Int { state.dex.keys.filter { Catalog.species($0).isRegular }.count }
    var shopSpeciesCount: Int { Catalog.fish.filter(\.isRegular).count }
    var daysWithoutDeath: Double {
        now.timeIntervalSince(state.stats.lastDeathAt ?? state.createdAt) / 86400
    }
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "first_feed", title: String(localized: "はじめての餌やり"), detail: String(localized: "魚に餌をあげた"), reward: nil) {
            $0.state.stats.feedings >= 1
        },
        Achievement(id: "species_5", title: String(localized: "にぎやかな水槽"), detail: String(localized: "5種類の魚を迎えた"), reward: "goldshell") {
            $0.speciesSeen >= 5
        },
        Achievement(id: "first_fry", title: String(localized: "はじめての稚魚"), detail: String(localized: "水槽で稚魚が生まれた"), reward: "flowercoral") {
            $0.state.stats.births >= 1
        },
        Achievement(id: "gen3", title: String(localized: "三代目"), detail: String(localized: "3代目の魚が生まれた"), reward: "familystone") {
            $0.state.dex.values.contains { $0.maxGeneration >= 3 }
        },
        Achievement(id: "no_death_7", title: String(localized: "やさしい飼い主"), detail: String(localized: "7日間、1匹も死なせなかった"), reward: nil) {
            $0.daysWithoutDeath >= 7
        },
        Achievement(id: "no_death_30", title: String(localized: "名人の水槽"), detail: String(localized: "30日間、1匹も死なせなかった"), reward: "rainbowcoral") {
            $0.daysWithoutDeath >= 30
        },
        Achievement(id: "old_age", title: String(localized: "天寿をまっとう"), detail: String(localized: "魚が寿命まで生きた"), reward: "memorial") {
            $0.state.dex.values.contains { $0.oldAge > 0 }
        },
        Achievement(id: "shiny", title: String(localized: "きらめく出会い"), detail: String(localized: "色違いの魚を迎えた"), reward: "starlamp") {
            $0.state.dex.values.contains { $0.shiny > 0 }
        },
        Achievement(id: "species_15", title: String(localized: "魚博士"), detail: String(localized: "15種類の魚を迎えた"), reward: "treasurepile") {
            $0.speciesSeen >= 15
        },
        Achievement(id: "dex_complete", title: String(localized: "図鑑コンプリート"), detail: String(localized: "お店のすべての魚を迎えた"), reward: "goldcastle") {
            $0.speciesSeen >= $0.shopSpeciesCount
        },
        Achievement(id: "feed_100", title: String(localized: "餌やり名人"), detail: String(localized: "餌やりを100回した"), reward: nil) {
            $0.state.stats.feedings >= 100
        },
        Achievement(id: "water_50", title: String(localized: "きれい好き"), detail: String(localized: "水換えを50回した"), reward: nil) {
            $0.state.stats.waterChanges >= 50
        },
        Achievement(id: "tank_max", title: String(localized: "大水族館"), detail: String(localized: "水槽をいちばん大きくした"), reward: nil) {
            $0.state.tank.level >= Catalog.tankSizes.count - 1
        },
        Achievement(id: "coins_1000", title: String(localized: "AIと二人三脚"), detail: String(localized: "AIの利用で1000コインを得た"), reward: "aimonument") {
            $0.coinsEarned >= 1000
        },
        Achievement(id: "treasure", title: String(localized: "宝さがし"), detail: String(localized: "流れてきた宝箱を開けた"), reward: nil) {
            $0.state.stats.treasures >= 1
        },
        Achievement(id: "variant_first", title: String(localized: "ブリーダー"), detail: String(localized: "原種ではない品種を迎えた"), reward: nil) {
            $0.state.variantsDiscovered >= 1
        },
        Achievement(id: "variant_10", title: String(localized: "品種コレクター"), detail: String(localized: "品種を合わせて10見つけた"), reward: "crystal") {
            $0.state.variantsDiscovered >= 10
        },
        Achievement(id: "variant_all", title: String(localized: "品種マスター"), detail: String(localized: "1種類の魚で、すべての品種をそろえた"), reward: nil) {
            $0.state.dex.values.contains { $0.variants.count >= FishVariant.allCases.count }
        },
        Achievement(id: "combo_variant", title: String(localized: "かけあわせの妙"), detail: String(localized: "2つの色を組み合わせた品種を迎えた"), reward: nil) {
            $0.state.dex.values.contains { $0.variants.contains { $0.isCombination } }
        },
        Achievement(id: "secret", title: String(localized: "秘境の探検家"), detail: String(localized: "隠れた魚に出会った"), reward: nil) { ctx in
            SecretFish.all.contains { ctx.state.dex[$0.speciesID] != nil }
        },
        Achievement(id: "secret_all", title: String(localized: "幻の魚ハンター"), detail: String(localized: "隠れた魚すべてに出会った"), reward: nil) { ctx in
            SecretFish.all.allSatisfy { ctx.state.dex[$0.speciesID] != nil }
        },
        Achievement(id: "rank10", title: String(localized: "水族館の主任"), detail: String(localized: "飼育員ランク10になった"), reward: nil) {
            $0.state.rank >= 10
        },
        Achievement(id: "rank20", title: String(localized: "伝説のアクアリスト"), detail: String(localized: "飼育員ランク20になった"), reward: nil) {
            $0.state.rank >= KeeperRank.maxRank
        },
        Achievement(id: "quests_30", title: String(localized: "働き者"), detail: String(localized: "ミッションを30回達成した"), reward: nil) {
            $0.state.quests.completedCount >= 30
        },
        Achievement(id: "layout_80", title: String(localized: "アクアスケーパー"), detail: String(localized: "レイアウトの評価で80点をとった"), reward: nil) {
            $0.state.bestLayoutScore >= 80
        },
        Achievement(id: "affection_max", title: String(localized: "大のなかよし"), detail: String(localized: "なつき度が最大の魚がいる"), reward: nil) {
            $0.state.tank.fish.contains { $0.isAlive && $0.affection >= Affection.max }
        },
        Achievement(id: "memorial_5000", title: String(localized: "AIの親友"), detail: String(localized: "記念の魚の最上位をもらった"), reward: nil) {
            $0.state.memorialsGiven.contains { $0.hasSuffix("@5000") }
        },
    ]

    static func achievement(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

// MARK: - AIの記念の魚

/// よく使うAIごとに、コインがたまると記念の魚をもらえる。1000・5000 コインで上位版。
struct MemorialFish {
    let group: String
    let speciesID: String
    /// どの取得元のコインを数えるか。
    let sources: [String]
    let label: String

    static let threshold = 100

    struct Tier {
        let threshold: Int
        let speciesID: String
        /// もらったことを覚えておく鍵（最初の段階は昔のデータと同じ鍵）。
        let key: String
    }

    var tiers: [Tier] {
        [Tier(threshold: Self.threshold, speciesID: speciesID, key: group),
         Tier(threshold: 1000, speciesID: speciesID + "2", key: group + "@1000"),
         Tier(threshold: 5000, speciesID: speciesID + "3", key: group + "@5000")]
    }

    static let all: [MemorialFish] = [
        MemorialFish(group: "claude", speciesID: "m_claude", sources: ["claude-code", "claude-desktop-cowork"], label: "Claude"),
        MemorialFish(group: "codex", speciesID: "m_codex", sources: ["codex"], label: "Codex"),
        MemorialFish(group: "gemini", speciesID: "m_gemini", sources: ["gemini-cli", "qwen-code"], label: "Gemini / Qwen"),
        MemorialFish(group: "other", speciesID: "m_other", sources: ["opencode", "copilot-cli", "ollama"], label: "OpenCode / Copilot / Ollama"),
    ]
}

// MARK: - ご褒美の宝箱

enum TreasureRule {
    /// 1日にこれだけAIでコインを得ると、宝箱が流れてくる。
    static let dailyCoins = 30
    static let rewardFood = 10
    static let rewardMedicine = 1
}

/// 日付ごとの集計に使う日付の文字列（その Mac の時刻で）。
enum DayKey {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
