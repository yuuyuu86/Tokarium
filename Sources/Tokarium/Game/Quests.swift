import Foundation

// MARK: - 毎日・毎週のお題

/// お題で数えること。AIの利用量やコインの支払いは数えない（お題のためにAIを使いたくならないように）。
enum QuestKind: String, Codable {
    case feed, feedOne, waterChange, touch, cleanMinutes, placeDecoration, birth, grownUp, newVariant
}

struct QuestReward: Equatable {
    var xp = 0
    var food = 0
    var medicine = 0
    var fragments = 0

    var text: String {
        var parts: [String] = []
        if xp > 0 { parts.append(String(localized: "経験値 \(xp)")) }
        if food > 0 { parts.append(String(localized: "餌 \(food)")) }
        if medicine > 0 { parts.append(String(localized: "薬 \(medicine)")) }
        if fragments > 0 { parts.append(String(localized: "かけら \(fragments)")) }
        return parts.joined(separator: String(localized: "・"))
    }
}

struct QuestTemplate {
    enum Period: String { case daily, weekly }

    let id: String
    let period: Period
    let kind: QuestKind
    let target: Int
    let title: String
    let reward: QuestReward
}

/// その日（その週）のお題。
struct Quest: Identifiable, Equatable {
    let template: QuestTemplate
    /// 期間の識別（日付や週）。
    let periodKey: String
    var id: String { "\(template.period.rawValue):\(periodKey):\(template.id)" }

    static func == (a: Quest, b: Quest) -> Bool { a.id == b.id }
}

/// お題の進み具合。
struct QuestBook: Codable, Equatable {
    /// お題ID → 進み具合。
    var progress: [String: Int] = [:]
    /// ごほうびを受け取ったお題。
    var claimed: Set<String> = []
    /// これまでに達成したお題の数。
    var completedCount = 0
}

enum Quests {
    static let dailyCount = 3
    static let weeklyCount = 2

    static let daily: [QuestTemplate] = [
        QuestTemplate(id: "feed3", period: .daily, kind: .feed, target: 3, title: String(localized: "餌やりを3回する"),
                      reward: QuestReward(xp: 15, food: 3, fragments: 1)),
        QuestTemplate(id: "feedOne2", period: .daily, kind: .feedOne, target: 2, title: String(localized: "魚を選んで餌を2回あげる"),
                      reward: QuestReward(xp: 15, fragments: 1)),
        QuestTemplate(id: "water1", period: .daily, kind: .waterChange, target: 1, title: String(localized: "水換えをする"),
                      reward: QuestReward(xp: 15, food: 3, fragments: 1)),
        QuestTemplate(id: "touch10", period: .daily, kind: .touch, target: 10, title: String(localized: "水を10回たたいて魚と遊ぶ"),
                      reward: QuestReward(xp: 10, fragments: 1)),
        QuestTemplate(id: "clean6", period: .daily, kind: .cleanMinutes, target: 6 * 60, title: String(localized: "水質を6時間「きれい」に保つ"),
                      reward: QuestReward(xp: 20, fragments: 1)),
        QuestTemplate(id: "place1", period: .daily, kind: .placeDecoration, target: 1, title: String(localized: "装飾を置く・動かす"),
                      reward: QuestReward(xp: 10, food: 2, fragments: 1)),
    ]

    static let weekly: [QuestTemplate] = [
        QuestTemplate(id: "birth1", period: .weekly, kind: .birth, target: 1, title: String(localized: "稚魚を生まれさせる"),
                      reward: QuestReward(xp: 60, medicine: 1, fragments: 3)),
        QuestTemplate(id: "grown1", period: .weekly, kind: .grownUp, target: 1, title: String(localized: "魚を1匹、成魚に育てる"),
                      reward: QuestReward(xp: 50, food: 5, fragments: 3)),
        QuestTemplate(id: "clean72", period: .weekly, kind: .cleanMinutes, target: 72 * 60, title: String(localized: "水質を合計3日間「きれい」に保つ"),
                      reward: QuestReward(xp: 60, fragments: 3)),
        QuestTemplate(id: "feed14", period: .weekly, kind: .feed, target: 14, title: String(localized: "餌やりを14回する"),
                      reward: QuestReward(xp: 50, food: 10, fragments: 3)),
        QuestTemplate(id: "water4", period: .weekly, kind: .waterChange, target: 4, title: String(localized: "水換えを4回する"),
                      reward: QuestReward(xp: 50, medicine: 1, fragments: 3)),
        QuestTemplate(id: "variant1", period: .weekly, kind: .newVariant, target: 1, title: String(localized: "新しい品種を図鑑に登録する"),
                      reward: QuestReward(xp: 80, fragments: 5)),
    ]

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String { DayKey.key(date, calendar: calendar) }

    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = calendar.timeZone
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    /// 期間ごとに決まったお題を選ぶ（同じ日なら何度見ても同じ）。
    private static func pick(_ pool: [QuestTemplate], count: Int, key: String) -> [QuestTemplate] {
        var rng = SeededRandom(seed: key.stableSeed)
        return Array(pool.shuffled(using: &rng).prefix(count))
    }

    static func today(_ date: Date = Date(), calendar: Calendar = .current) -> [Quest] {
        let key = dayKey(date, calendar: calendar)
        return pick(daily, count: dailyCount, key: "d" + key).map { Quest(template: $0, periodKey: key) }
    }

    static func thisWeek(_ date: Date = Date(), calendar: Calendar = .current) -> [Quest] {
        let key = weekKey(date, calendar: calendar)
        return pick(weekly, count: weeklyCount, key: "w" + key).map { Quest(template: $0, periodKey: key) }
    }

    static func current(_ date: Date = Date(), calendar: Calendar = .current) -> [Quest] {
        today(date, calendar: calendar) + thisWeek(date, calendar: calendar)
    }
}

extension GameState {
    func progress(of quest: Quest) -> Int { min(quest.template.target, quests.progress[quest.id] ?? 0) }

    func isDone(_ quest: Quest) -> Bool { progress(of: quest) >= quest.template.target }

    func isClaimed(_ quest: Quest) -> Bool { quests.claimed.contains(quest.id) }

    /// 受け取れるごほうびの数。
    func claimableQuests(now: Date = Date()) -> [Quest] {
        Quests.current(now).filter { isDone($0) && !isClaimed($0) }
    }

    /// 行動をお題に数える。戻り値は、これで達成したお題。
    @discardableResult
    mutating func questEvent(_ kind: QuestKind, count: Int = 1, now: Date = Date()) -> [Quest] {
        let current = Quests.current(now)
        // 期間の過ぎたお題の記録は消す
        let ids = Set(current.map(\.id))
        quests.progress = quests.progress.filter { ids.contains($0.key) }
        quests.claimed = quests.claimed.filter { ids.contains($0) }
        var done: [Quest] = []
        for q in current where q.template.kind == kind && !isDone(q) {
            quests.progress[q.id, default: 0] += count
            if isDone(q) { done.append(q) }
        }
        return done
    }

    /// ごほうびを受け取る。
    @discardableResult
    mutating func claim(_ quest: Quest, now: Date = Date()) -> QuestReward? {
        guard isDone(quest), !isClaimed(quest), Quests.current(now).contains(quest) else { return nil }
        quests.claimed.insert(quest.id)
        quests.completedCount += 1
        let r = quest.template.reward
        food += r.food
        medicine += r.medicine
        fragments += r.fragments
        gainXP(.quest, amount: r.xp, now: now)
        return r
    }
}
