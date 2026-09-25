import Foundation
import Testing
@testable import Tokarium

// MARK: - 遊びの数値の見直し用のシミュレーション
//
// TOKARIUM_BALANCE=1 swift test --filter balanceReport
// 1日あたりのコインがちがう3人のプレイヤーが60日遊んだときの、ランク・図鑑・品種・お題の進み方を表にする。

struct BalancePlayer {
    let name: String
    let coinsPerDay: Int
}

struct BalanceDay {
    var day: Int
    var rank: Int
    var xp: Int
    var coins: Int
    var fish: Int
    var species: Int
    var variants: Int
    var quests: Int
    var births: Int
    var tankLevel: Int
    var secrets: Int
    var achievements: Int
}

/// ゲームの仕組み（GameState と Simulation）をそのまま使い、ふつうの遊び方をまねる。
enum BalanceSim {
    static func run(_ player: BalancePlayer, days: Int, seed: UInt64 = 1) -> (days: [BalanceDay], xpBySource: [String: Int]) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        var s = GameState.newGame(now: start)
        var rng = SeededRandom(seed: seed)
        var earned = 0
        var xpBySource: [String: Int] = [:]
        var result: [BalanceDay] = []

        func xp(_ e: XPEvent, _ amount: Int? = nil, _ now: Date) {
            let before = s.xp
            s.gainXP(e, amount: amount, now: now)
            xpBySource[e.rawValue, default: 0] += s.xp - before
        }
        func coins() -> Int { s.initialCoins + earned - s.coinsSpent }
        func progress(_ now: Date) {
            let ctx = AchievementContext(state: s, coinsEarned: earned, now: now)
            for a in Achievements.all where s.achievements[a.id] == nil && a.isUnlocked(ctx) {
                s.achievements[a.id] = now
                if let r = a.reward { s.tank.decorations.append(Decoration(kindID: r, isPlaced: false)) }
            }
            let c = s.currentXPCounts
            if c.species > s.xpCounted.species { xp(.newSpecies, (c.species - s.xpCounted.species) * XPEvent.newSpecies.amount, now) }
            if c.variants > s.xpCounted.variants {
                xp(.newVariant, (c.variants - s.xpCounted.variants) * XPEvent.newVariant.amount, now)
                s.questEvent(.newVariant, count: c.variants - s.xpCounted.variants, now: now)
            }
            if c.achievements > s.xpCounted.achievements {
                xp(.achievement, (c.achievements - s.xpCounted.achievements) * XPEvent.achievement.amount, now)
            }
            if c.oldAge > s.xpCounted.oldAge { xp(.oldAge, (c.oldAge - s.xpCounted.oldAge) * XPEvent.oldAge.amount, now) }
            s.xpCounted = c
        }
        func claimAll(_ now: Date) {
            for q in s.claimableQuests(now: now) {
                let before = s.xp
                s.claim(q, now: now)
                xpBySource["quest", default: 0] += s.xp - before
            }
        }
        func shop(_ now: Date) {
            // 水槽の拡張 → まだ図鑑にない魚 → 装飾、の順に買う
            if s.tank.level + 1 < Catalog.tankSizes.count {
                let next = Catalog.tankSizes[s.tank.level + 1]
                if s.rank >= KeeperRank.required(tankLevel: next.level) && coins() >= next.price {
                    s.coinsSpent += next.price
                    s.tank.level = next.level
                }
            }
            if s.rank >= KeeperRank.equipmentRank {
                for e in Equipment.all where !s.equipment.contains(e.id) && coins() >= e.price + 50 {
                    s.coinsSpent += e.price
                    s.equipment.insert(e.id)
                }
            }
            let living = s.tank.fish.filter(\.isAlive).count
            if living < s.tank.size.maxFish - 1,
               let sp = Catalog.fish.filter({ $0.isRegular && s.dex[$0.id] == nil && s.rank >= KeeperRank.required($0) && coins() >= $0.price })
                .min(by: { $0.price < $1.price }) {
                s.coinsSpent += sp.price
                s.addFish(Fish(speciesID: sp.id, name: sp.name, purchasedAt: now, x: 0.5, y: 0.5), at: now)
                s.stats.fishBought += 1
                // 同じ種類をもう1匹（繁殖のため）
                if coins() >= sp.price && living + 1 < s.tank.size.maxFish {
                    s.coinsSpent += sp.price
                    s.addFish(Fish(speciesID: sp.id, name: sp.name, purchasedAt: now, x: 0.5, y: 0.5), at: now)
                }
            }
            let placed = s.tank.decorations.filter(\.isPlaced).count
            if placed < s.tank.size.maxDecorations,
               let kind = Catalog.decorations.filter({ k in k.isRegular && s.rank >= KeeperRank.required(k) && coins() >= k.price * 2
                    && !s.tank.decorations.contains { $0.kindID == k.id } }).min(by: { $0.price < $1.price }) {
                s.coinsSpent += kind.price
                s.tank.decorations.append(Decoration(kindID: kind.id, x: .random(in: 0.1...0.9, using: &rng), layer: Int.random(in: 0...1, using: &rng)))
                s.questEvent(.placeDecoration, now: now)
                let score = Layout.score(s.tank).total
                if score > s.bestLayoutScore {
                    xp(.layout, score - s.bestLayoutScore, now)
                    s.bestLayoutScore = score
                }
            }
            // 同じ色の遺伝子を持つ2匹をペアにする（お世話の画面で遺伝子が見える）
            for (_, group) in Dictionary(grouping: s.tank.fish.filter(\.isAlive), by: \.speciesID) where group.count >= 2 {
                guard !group.contains(where: { $0.partnerID != nil }) else { continue }
                outer: for i in group.indices {
                    for j in group.indices where j > i {
                        let shared = Set(group[i].genotype.genes).intersection(group[j].genotype.genes).subtracting([.wild])
                        if !shared.isEmpty {
                            if let a = s.tank.fish.firstIndex(where: { $0.id == group[i].id }),
                               let b = s.tank.fish.firstIndex(where: { $0.id == group[j].id }) {
                                s.tank.fish[a].partnerID = group[j].id
                                s.tank.fish[b].partnerID = group[i].id
                            }
                            break outer
                        }
                    }
                }
            }
            // 水槽がいっぱいなら、原種で数の多い魚を1匹里親に出す
            let alive = s.tank.fish.filter(\.isAlive)
            if alive.count >= s.tank.size.maxFish - 1 {
                let counts = Dictionary(grouping: alive, by: \.speciesID).mapValues(\.count)
                if let f = alive.filter({ $0.variant == .wild && $0.partnerID == nil && (counts[$0.speciesID] ?? 0) > 2 })
                    .min(by: { $0.bornAt < $1.bornAt }) {
                    s.tank.fish.removeAll { $0.id == f.id }
                    s.stats.adoptions += 1
                    xp(.adoption, nil, now)
                }
            }
            // 余裕があれば今日の入荷（品種の魚）も買う
            for offer in DailyStock.offers(on: now, rank: s.rank) where !s.stockBought.contains(offer.id)
                && coins() >= offer.price + 100 && s.tank.fish.filter(\.isAlive).count < s.tank.size.maxFish {
                s.coinsSpent += offer.price
                let gene = ColorGene(rawValue: offer.variant.rawValue) ?? .gold
                var f = Fish(speciesID: offer.speciesID, name: offer.name, purchasedAt: now, x: 0.5, y: 0.5)
                f.genotype = Genotype(a: gene, b: gene)
                s.addFish(f, at: now)
                s.stockBought.insert(offer.id)
            }
            // かけらがたまったら交換
            if let kind = Catalog.questDecorations.first(where: { k in (k.fragmentPrice ?? 0) <= s.fragments && !s.tank.decorations.contains { $0.kindID == k.id } }) {
                s.fragments -= kind.fragmentPrice ?? 0
                s.tank.decorations.append(Decoration(kindID: kind.id, isPlaced: false))
            }
            // 死んだ魚とはお別れする
            for f in s.tank.fish where !f.isAlive { s.memories.insert(FishMemory(f), at: 0) }
            s.tank.fish.removeAll { !$0.isAlive }
            // 食べ物が少なくなったら買う
            if s.food < 10, coins() >= 12 {
                s.coinsSpent += 12
                s.food += 30
            }
        }

        for day in 0..<days {
            for hour in 1...24 {
                let now = start.addingTimeInterval(Double(day * 24 + hour) * 3600)
                let report = Simulation.advance(&s, to: now, rng: &rng)
                if !report.births.isEmpty {
                    xp(.birth, nil, now)
                    s.questEvent(.birth, now: now)
                }
                for _ in report.grownUp { xp(.grownUp, nil, now) }
                if !report.grownUp.isEmpty { s.questEvent(.grownUp, count: report.grownUp.count, now: now) }
                if s.tank.waterQuality >= 70 { s.questEvent(.cleanMinutes, count: 60, now: now) }
                if let visitor = s.visitSecretFish(hours: 1, now: now, rng: &rng) {
                    _ = visitor
                    xp(.secret, nil, now)
                }
                let clock = cal.component(.hour, from: now)
                // 朝と夜に水槽を開く
                if clock == 9 || clock == 21 {
                    if s.food > 0 {
                        Simulation.feed(&s, now: now)
                        s.food -= 1
                        s.stats.feedings += 1
                        xp(.feed, nil, now)
                        s.questEvent(.feed, now: now)
                    }
                    if let f = s.tank.fish.first(where: \.isAlive), clock == 21 {
                        Simulation.feed(&s, fish: f.id, now: now)
                        s.questEvent(.feedOne, now: now)
                        s.questEvent(.feed, now: now)
                    }
                    s.questEvent(.touch, count: 6, now: now)
                    if clock == 21 {
                        if day % 2 == 1 {
                            Simulation.changeWater(&s, now: now)
                            s.stats.waterChanges += 1
                            xp(.waterChange, nil, now)
                            s.questEvent(.waterChange, now: now)
                        }
                        earned += player.coinsPerDay
                        shop(now)
                    }
                    progress(now)
                    claimAll(now)
                }
            }
            result.append(BalanceDay(day: day + 1, rank: s.rank, xp: s.xp, coins: coins(), fish: s.tank.fish.filter(\.isAlive).count,
                                     species: s.dex.keys.filter { Catalog.species($0).isRegular }.count, variants: s.variantsDiscovered,
                                     quests: s.quests.completedCount, births: s.stats.births, tankLevel: s.tank.level,
                                     secrets: SecretFish.all.filter { s.dex[$0.speciesID] != nil }.count, achievements: s.achievements.count))
        }
        return (result, xpBySource)
    }
}

@Test func balanceReport() {
    guard ProcessInfo.processInfo.environment["TOKARIUM_BALANCE"] != nil else { return }
    let players = [BalancePlayer(name: "ライト（10/日）", coinsPerDay: 10),
                   BalancePlayer(name: "ふつう（50/日）", coinsPerDay: 50),
                   BalancePlayer(name: "ヘビー（250/日）", coinsPerDay: 250)]
    for p in players {
        let (days, sources) = BalanceSim.run(p, days: 60)
        print("\n== \(p.name) ==")
        print("日  ランク 経験値 コイン 魚 図鑑 品種 お題 誕生 水槽 隠れ 実績")
        for d in days where [1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60].contains(d.day) {
            print(String(format: "%2d  %4d %6d %6d %3d %3d %4d %4d %4d %3d %3d %3d", d.day, d.rank, d.xp, d.coins, d.fish, d.species, d.variants,
                         d.quests, d.births, d.tankLevel, d.secrets, d.achievements))
        }
        let total = max(1, sources.values.reduce(0, +))
        print("経験値の内訳: " + sources.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value * 100 / total)%" }.joined(separator: ", "))
    }
}

/// 数値を変えたときに、ふつうの遊び方で進み方が極端にならないことを確かめる。
@Test func balanceStaysReasonable() {
    let (days, _) = BalanceSim.run(BalancePlayer(name: "ふつう", coinsPerDay: 50), days: 30)
    let week = days[6], month = days[29]
    // 1週間で数ランクは上がり、1か月でもまだ最高ランクには届かない
    #expect(week.rank >= 3)
    #expect(month.rank < KeeperRank.maxRank)
    // 1か月でお題を半分以上はこなせる
    #expect(month.quests >= 30 * 3 / 2)
}
