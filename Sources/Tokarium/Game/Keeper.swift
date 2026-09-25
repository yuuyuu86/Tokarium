import Foundation

// MARK: - 飼育員ランク

/// 経験値のもとになる行動。
enum XPEvent: String, Codable, CaseIterable {
    case feed, waterChange, birth, grownUp, newSpecies, newVariant, achievement, quest, oldAge, layout, secret

    /// 1回でもらえる経験値。
    var amount: Int {
        switch self {
        case .feed: return 2
        case .waterChange: return 5
        case .birth: return 15
        case .grownUp: return 10
        case .newSpecies: return 30
        case .newVariant: return 25
        case .achievement: return 50
        case .quest: return 0   // お題ごとに決まっている
        case .oldAge: return 20
        case .layout: return 0  // 評価の上がった分
        case .secret: return 60
        }
    }

    /// 1日にもらえる回数の上限（何度も押すだけで上がらないように）。
    var dailyLimit: Int? {
        switch self {
        case .feed: return 5
        case .waterChange: return 3
        default: return nil
        }
    }
}

enum KeeperRank {
    static let maxRank = 20

    /// そのランクになるのに必要な累計の経験値。
    static func xpRequired(for rank: Int) -> Int {
        guard rank > 1 else { return 0 }
        return Int((40 * pow(Double(rank - 1), 1.6)).rounded())
    }

    static func rank(forXP xp: Int) -> Int {
        var r = 1
        while r < maxRank && xp >= xpRequired(for: r + 1) { r += 1 }
        return r
    }

    /// 次のランクまでの進み具合（0〜1）。
    static func progress(xp: Int) -> Double {
        let r = rank(forXP: xp)
        guard r < maxRank else { return 1 }
        let lo = xpRequired(for: r), hi = xpRequired(for: r + 1)
        return Double(xp - lo) / Double(max(1, hi - lo))
    }

    static func title(_ rank: Int) -> String {
        switch rank {
        case ..<3: return String(localized: "見習い飼育員")
        case 3..<6: return String(localized: "飼育員")
        case 6..<10: return String(localized: "ベテラン飼育員")
        case 10..<14: return String(localized: "水族館の主任")
        case 14..<18: return String(localized: "水族館の館長")
        default: return String(localized: "伝説のアクアリスト")
        }
    }

    /// 値段からお店に並ぶランクを決める。
    static func required(price: Int) -> Int {
        switch price {
        case ...50: return 1
        case ...80: return 2
        case ...120: return 3
        case ...180: return 4
        case ...250: return 5
        case ...350: return 7
        case ...500: return 9
        case ...800: return 12
        default: return 14
        }
    }

    static func required(_ species: FishSpecies) -> Int {
        species.isRegular ? required(price: species.price) : 1
    }

    static func required(_ kind: DecorationKind) -> Int {
        kind.isRegular ? required(price: kind.price) : 1
    }

    /// 水槽の拡張と設備に必要なランク。
    static func required(tankLevel level: Int) -> Int { [1, 4, 8, 12][min(max(0, level), 3)] }
    static let equipmentRank = 3

    /// ランクが上がって新しく並ぶ魚と装飾の名前。
    static func unlocked(at rank: Int) -> [String] {
        Catalog.fish.filter { $0.isRegular && required($0) == rank }.map(\.name)
            + Catalog.decorations.filter { $0.isRegular && required($0) == rank }.map(\.name)
    }

    /// ランクができる前のデータの経験値を、これまでの記録から見積もる。
    static func estimatedXP(_ state: GameState) -> Int {
        let s = state.stats
        var xp = s.feedings * XPEvent.feed.amount + s.waterChanges * XPEvent.waterChange.amount
        xp += s.births * XPEvent.birth.amount
        xp += state.dex.count * XPEvent.newSpecies.amount
        xp += state.achievements.count * XPEvent.achievement.amount
        xp += state.dex.values.reduce(0) { $0 + $1.oldAge } * XPEvent.oldAge.amount
        return xp
    }
}

extension GameState {
    var rank: Int { KeeperRank.rank(forXP: xp) }

    /// 経験値を足す。戻り値は上がったランク（上がらなければ nil）。
    @discardableResult
    mutating func gainXP(_ event: XPEvent, amount: Int? = nil, now: Date = Date()) -> Int? {
        let today = DayKey.key(now)
        if xpDay != today {
            xpDay = today
            xpToday = [:]
        }
        if let limit = event.dailyLimit {
            guard xpToday[event.rawValue, default: 0] < limit else { return nil }
            xpToday[event.rawValue, default: 0] += 1
        }
        let before = rank
        xp += amount ?? event.amount
        return rank > before ? rank : nil
    }
}
