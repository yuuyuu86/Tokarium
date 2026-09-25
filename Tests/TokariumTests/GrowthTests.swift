import Foundation
import Testing
@testable import Tokarium

// MARK: - やり込み要素

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokarium-growth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func careFor(_ s: inout GameState, from start: Date, hours: Int, seed: UInt64 = 1) {
    var rng = SeededRandom(seed: seed)
    for h in 1...hours {
        let t = start.addingTimeInterval(Double(h) * 3600)
        Simulation.advance(&s, to: t, rng: &rng)
        if h % 8 == 0 { Simulation.feed(&s, now: t) }
        if h % 24 == 0 { Simulation.changeWater(&s, now: t) }
    }
}

// MARK: 品種

@Test func genotypeDecidesVariant() {
    #expect(Genotype(a: .wild, b: .wild).variant == .wild)
    #expect(Genotype(a: .gold, b: .gold).variant == .gold)
    // 野生型は優性で、色の遺伝子はかくれる
    let carrier = Genotype(a: .wild, b: .gold)
    #expect(carrier.variant == .wild)
    #expect(carrier.hiddenGenes == [.gold])
    // 組み合わせの品種
    #expect(Genotype(a: .gold, b: .red).variant == .sunset)
    #expect(Genotype(a: .red, b: .gold).variant == .sunset)
    #expect(Genotype(a: .black, b: .albino).variant == .panda)
    // レシピのない2色は強い方
    #expect(Genotype(a: .gold, b: .black).variant == .black)
    #expect(Genotype(a: .gold, b: .black).hiddenGenes == [.gold])
    // すべての組み合わせの品種に、たどり着くレシピがある
    for v in FishVariant.allCases where v.isCombination { #expect(v.recipeHint != nil) }
}

@Test func outcomesFollowMendel() {
    let carrier = Genotype(a: .wild, b: .gold)
    let outcomes = Dictionary(uniqueKeysWithValues: Genetics.outcomes(carrier, carrier).map { ($0.0, $0.1) })
    #expect(outcomes[.wild] == 0.75)
    #expect(outcomes[.gold] == 0.25)
    #expect(abs(Genetics.outcomes(Genotype(a: .gold, b: .blue), Genotype(a: .red, b: .pastel)).map(\.1).reduce(0, +) - 1) < 1e-9)
}

@Test func fryInheritGenesFromChosenPair() {
    let start = Date(timeIntervalSince1970: 0)
    var s = GameState.newGame(now: start)
    s.tank.fish.removeAll()
    var a = Fish(speciesID: "guppy", name: "a", purchasedAt: start)
    var b = Fish(speciesID: "guppy", name: "b", purchasedAt: start)
    var c = Fish(speciesID: "guppy", name: "c", purchasedAt: start)
    a.genotype = Genotype(a: .gold, b: .gold)
    b.genotype = Genotype(a: .gold, b: .gold)
    c.genotype = .wild
    a.partnerID = b.id
    b.partnerID = a.id
    for var f in [a, b, c] {
        f.growth = 1
        s.addFish(f, at: start)
    }
    careFor(&s, from: start, hours: 24 * 20)
    let fry = s.tank.fish.filter { $0.generation == 2 }
    #expect(!fry.isEmpty)
    // ペアの魚は決めた相手とだけ繁殖するので、2代目はゴールドどうしの子（突然変異を除く）
    let gold = fry.filter { $0.genotype.genes.filter { $0 == .gold }.count >= 1 }
    #expect(gold.count == fry.count)
    #expect(fry.filter { $0.variant == .gold }.count >= fry.count / 2)
    #expect(s.dex["guppy"]?.variants.contains(.gold) == true)
    #expect(s.variantsDiscovered >= 1)
}

@Test func oldFishGetStableGenesAndPersonality() throws {
    let id = UUID()
    let json = #"{"id":"\#(id.uuidString)","speciesID":"neon","name":"a"}"#
    let f1 = try JSONDecoder.tokarium.decode(Fish.self, from: Data(json.utf8))
    let f2 = try JSONDecoder.tokarium.decode(Fish.self, from: Data(json.utf8))
    #expect(f1.genotype == f2.genotype)
    #expect(f1.personality == f2.personality)
    #expect(f1.size == f2.size)
    #expect(Fish.sizeRange.contains(f1.size))
}

@MainActor
@Test func variantImagesDifferFromWild() throws {
    let style = AquariumStyles.pixel
    let wild = try #require(style.fishImage("neon", frame: 0, dead: false, shiny: false, variant: .wild))
    for v in FishVariant.allCases where v != .wild {
        let img = try #require(style.fishImage("neon", frame: 0, dead: false, shiny: false, variant: v), "\(v) を描けない")
        #expect(img.image.width == wild.image.width)
        #expect(img.image.dataProvider?.data as Data? != wild.image.dataProvider?.data as Data?, "\(v) が原種と同じ色")
    }
}

// MARK: 飼育員ランク

@Test func rankGrowsWithXPAndDailyLimits() {
    for r in 2...KeeperRank.maxRank { #expect(KeeperRank.xpRequired(for: r) > KeeperRank.xpRequired(for: r - 1)) }
    #expect(KeeperRank.rank(forXP: 0) == 1)
    #expect(KeeperRank.rank(forXP: KeeperRank.xpRequired(for: 5)) == 5)
    var s = GameState.newGame()
    let now = Date()
    for _ in 0..<20 { s.gainXP(.feed, now: now) }
    // 餌やりの経験値は1日5回まで
    #expect(s.xp == 5 * XPEvent.feed.amount)
    s.gainXP(.feed, now: now.addingTimeInterval(86400))
    #expect(s.xp == 6 * XPEvent.feed.amount)
    // 安いものは最初から、高いものはランクが上がってから
    #expect(KeeperRank.required(Catalog.species("neon")) == 1)
    #expect(KeeperRank.required(Catalog.species("arowana")) > 5)
    #expect(KeeperRank.required(Catalog.decoration("goldshell")) == 1)
}

@Test func oldSavesGetEstimatedXP() throws {
    let json = #"{"createdAt":0,"stats":{"feedings":10,"waterChanges":4,"births":2,"deaths":0,"fishBought":1,"decorationsBought":0,"touches":0,"treasures":0},"dex":{"neon":{"firstSeenAt":0,"owned":2}}}"#
    let s = try JSONDecoder.tokarium.decode(GameState.self, from: Data(json.utf8))
    #expect(s.xp == 10 * 2 + 4 * 5 + 2 * 15 + 1 * 30)
    // 見積もった分は、あとで二重に渡さない
    #expect(s.xpCounted == s.currentXPCounts)
    #expect(s.dex["neon"]?.variants == [.wild])
}

@MainActor
@Test func purchasesUnlockWithRank() throws {
    let store = GameStore(directory: try tempDir())
    store.state.initialCoins = 10_000
    let pricey = Catalog.species("arowana")
    #expect(store.buyFish(pricey) == .rankTooLow(KeeperRank.required(pricey)))
    store.state.xp = KeeperRank.xpRequired(for: KeeperRank.required(pricey))
    #expect(store.buyFish(pricey) == nil)
}

// MARK: お題

@Test func questsArePickedPerPeriodAndClaimedOnce() {
    let day = Date(timeIntervalSince1970: 1_790_000_000)
    let q1 = Quests.today(day), q2 = Quests.today(day)
    #expect(q1 == q2)
    #expect(q1.count == Quests.dailyCount && Set(q1.map(\.template.id)).count == Quests.dailyCount)
    #expect(Quests.thisWeek(day).count == Quests.weeklyCount)

    var s = GameState.newGame(now: day)
    let quest = q1[0]
    s.questEvent(quest.template.kind, count: quest.template.target, now: day)
    #expect(s.isDone(quest))
    let food = s.food, xp = s.xp
    let reward = s.claim(quest, now: day)
    #expect(reward == quest.template.reward)
    #expect(s.food == food + quest.template.reward.food)
    #expect(s.xp == xp + quest.template.reward.xp)
    #expect(s.fragments >= 1)
    #expect(s.claim(quest, now: day) == nil)
    #expect(s.quests.completedCount == 1)

    // 次の週になると、前のお題の記録は消える
    s.questEvent(.touch, now: day.addingTimeInterval(8 * 86400))
    #expect(s.quests.progress[quest.id] == nil)
}

@MainActor
@Test func fragmentsExchangeForDecorations() throws {
    let store = GameStore(directory: try tempDir())
    let kind = Catalog.questDecorations[0]
    #expect(store.exchange(kind) == .notEnoughFragments)
    store.state.fragments = kind.fragmentPrice ?? 0
    #expect(store.exchange(kind) == nil)
    #expect(store.state.fragments == 0)
    #expect(store.state.tank.decorations.contains { $0.kindID == kind.id })
    #expect(!kind.isRegular)
}

// MARK: レイアウト・隠れた魚・殿堂・なつき度

@Test func layoutScoreRewardsVarietyAndCombos() {
    var tank = Tank()
    #expect(Layout.score(tank).total == 0)
    tank.decorations = [Decoration(kindID: "grass", x: 0.5)]
    let plain = Layout.score(tank).total
    tank.decorations = [("grass", 0.1, 0), ("redgrass", 0.3, 1), ("fern", 0.5, 0), ("sword", 0.7, 1), ("rock", 0.9, 0),
                        ("coral", 0.2, 1), ("chest", 0.6, 0)]
        .map { Decoration(kindID: $0.0, x: $0.1, layer: $0.2) }
    let rich = Layout.score(tank)
    #expect(rich.total > plain)
    #expect(rich.bonuses.contains { $0.title == String(localized: "水草の森") })
    #expect(rich.total <= 100)
}

@Test func secretFishVisitsOnlyWhenConditionsMet() {
    let night = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
    var s = GameState.newGame(now: night)
    var rng = SeededRandom(seed: 9)
    // 条件がそろっていなければ来ない
    for _ in 0..<50 { #expect(s.visitSecretFish(hours: 6, now: night, rng: &rng) == nil) }
    // 夜・光るもの・きれいな水でホタルテトラが来る
    s.tank.decorations.append(Decoration(kindID: "gems", x: 0.5))
    var visitor: Fish?
    for _ in 0..<200 where visitor == nil { visitor = s.visitSecretFish(hours: 6, now: night, rng: &rng) }
    #expect(visitor?.speciesID == "hotaru")
    #expect(s.dex["hotaru"] != nil)
    // 一度会った魚は、もう来ない
    for _ in 0..<50 { #expect(s.visitSecretFish(hours: 6, now: night, rng: &rng)?.speciesID != "hotaru") }
}

@MainActor
@Test func affectionMemoriesAndHall() throws {
    let store = GameStore(directory: try tempDir())
    let fish = try #require(store.state.tank.fish.first)
    store.feed(fish: fish.id)
    let after = try #require(store.state.tank.fish.first { $0.id == fish.id })
    #expect(after.affection > 0)

    // 死んだ魚とお別れすると、思い出に残る
    let i = try #require(store.state.tank.fish.firstIndex { $0.id == fish.id })
    store.state.tank.fish[i].isAlive = false
    store.state.tank.fish[i].diedAt = Date()
    store.state.tank.fish[i].deathCause = .oldAge
    store.farewell(fish.id)
    #expect(store.state.memories.first?.id == fish.id)
    #expect(Hall.records(store.state).contains { $0.id == "age" })

    // 称号は達成した実績だけ
    store.setTitle("first_feed")
    #expect(store.titleText == Achievements.achievement("first_feed")?.title)
}

@Test func memorialFishHaveThreeTiers() {
    for m in MemorialFish.all {
        #expect(m.tiers.map(\.threshold) == [100, 1000, 5000])
        #expect(m.tiers[0].key == m.group)
        for t in m.tiers { #expect(Catalog.fish.contains { $0.id == t.speciesID }, "\(t.speciesID) がない") }
    }
    for secret in SecretFish.all { #expect(Catalog.species(secret.speciesID).id == secret.speciesID) }
}
