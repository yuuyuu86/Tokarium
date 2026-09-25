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

    var speciesSeen: Int { state.dex.keys.filter { !Catalog.species($0).hidden }.count }
    var shopSpeciesCount: Int { Catalog.fish.filter { !$0.hidden }.count }
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
    ]

    static func achievement(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

// MARK: - AIの記念の魚

/// よく使うAIごとに、コインがたまると記念の魚をもらえる。
struct MemorialFish {
    let group: String
    let speciesID: String
    /// どの取得元のコインを数えるか。
    let sources: [String]
    let label: String

    static let threshold = 100

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
