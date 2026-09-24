import Foundation
import Testing
@testable import Tokarium

// MARK: - 利用記録と通貨

private func tempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokarium-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ lines: [String], to url: URL, append: Bool = false) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = lines.joined(separator: "\n") + "\n"
    if append, let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(Data(text.utf8))
        try h.close()
    } else {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func iso(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: d)
}

private func claudeLine(id: String, req: String, at: Date, input: Int = 10, output: Int = 1000, cacheRead: Int = 0) -> String {
    """
    {"type":"assistant","timestamp":"\(iso(at))","requestId":"\(req)","message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":\(cacheRead)}}}
    """
}

@Test func claudeRecordsBeforeStartAreIgnoredAndDuplicatesCountOnce() throws {
    let home = try tempHome()
    let start = Date()
    let file = home.appendingPathComponent(".claude/projects/p/s.jsonl")
    try write([
        claudeLine(id: "old", req: "r0", at: start.addingTimeInterval(-60)),
        claudeLine(id: "m1", req: "r1", at: start.addingTimeInterval(10)),
        claudeLine(id: "m1", req: "r1", at: start.addingTimeInterval(11)), // ストリーミングの重複
    ], to: file)

    let ctx = ScanContext(ledger: UsageLedger(startDate: start), includeEstimated: false, home: home)
    try ClaudeCodeReader().scan(ctx)
    #expect(ctx.ledger.sources["claude-code"]?.records == 1)
    #expect(ctx.ledger.sources["claude-code"]?.tokens.output == 1000)

    // 再走査しても増えない（ファイル位置をリセットしても重複IDで弾く）
    ctx.ledger.files.removeAll()
    try ClaudeCodeReader().scan(ctx)
    #expect(ctx.ledger.sources["claude-code"]?.records == 1)

    // 追記分だけ増える
    try write([claudeLine(id: "m2", req: "r2", at: start.addingTimeInterval(20), input: 0, output: 500, cacheRead: 10_000)], to: file, append: true)
    try ClaudeCodeReader().scan(ctx)
    let t = try #require(ctx.ledger.sources["claude-code"])
    #expect(t.records == 2)
    // 重み付きトークン: 10 + 1000 + (500 + 10000 * 0.1)
    #expect(abs(t.creditedWeighted - 2510) < 0.001)
}

@Test func coworkAndClaudeCodeShareDedup() throws {
    let home = try tempHome()
    let start = Date()
    try write([claudeLine(id: "same", req: "r", at: start.addingTimeInterval(5))],
              to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
    try write([claudeLine(id: "same", req: "r", at: start.addingTimeInterval(5))],
              to: home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions/x/y/.claude/projects/q/b.jsonl"))
    let ctx = ScanContext(ledger: UsageLedger(startDate: start), includeEstimated: false, home: home)
    try ClaudeCodeReader().scan(ctx)
    try ClaudeDesktopCoworkReader().scan(ctx)
    let total = ctx.ledger.sources.values.reduce(0) { $0 + $1.records }
    #expect(total == 1)
}

private func codexLine(at: Date, input: Int, cached: Int, output: Int) -> String {
    """
    {"timestamp":"\(iso(at))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}},"rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1788136743},"plan_type":"plus"}}}
    """
}

@Test func codexCountsOnlyGrowthAfterStartAcrossArchiveMove() throws {
    let home = try tempHome()
    let start = Date()
    let sid = "01a0340e-3f75-77c3-bd01-98230d106219"
    let live = home.appendingPathComponent(".codex/sessions/2026/09/25/rollout-2026-09-25T10-00-00-\(sid).jsonl")
    try write([
        codexLine(at: start.addingTimeInterval(-100), input: 1000, cached: 0, output: 100),  // 開始前
        codexLine(at: start.addingTimeInterval(10), input: 3000, cached: 1000, output: 300),
        codexLine(at: start.addingTimeInterval(11), input: 3000, cached: 1000, output: 300), // 同じ累計
    ], to: live)
    let ctx = ScanContext(ledger: UsageLedger(startDate: start), includeEstimated: false, home: home)
    try CodexReader().scan(ctx)
    var t = try #require(ctx.ledger.sources["codex"])
    // 増分: 入力(非キャッシュ) 2000-1000=1000, キャッシュ読込 1000, 出力 200
    #expect(t.tokens.input == 1000)
    #expect(t.tokens.cacheRead == 1000)
    #expect(t.tokens.output == 200)
    #expect(ctx.ledger.quotas["codex"]?.primary?.usedPercent == 12)

    // archived_sessions に移動しても二重に数えない
    let archived = home.appendingPathComponent(".codex/archived_sessions/rollout-2026-09-25T10-00-00-\(sid).jsonl")
    try FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: live, to: archived)
    try CodexReader().scan(ctx)
    t = try #require(ctx.ledger.sources["codex"])
    #expect(t.records == 1)
}

@Test func estimatedValuesAreNotCreditedByDefault() {
    let start = Date()
    let ctx = ScanContext(ledger: UsageLedger(startDate: start), includeEstimated: false)
    let info = OllamaReader().info
    ctx.record(source: info, key: nil, date: start.addingTimeInterval(1), tokens: TokenBreakdown(output: 5000))
    #expect(ctx.ledger.coinsEarned == 0)
    #expect(ctx.ledger.sources["ollama"]?.uncreditedWeighted == 5000)
}

@Test func recordsWithoutTimestampAreIgnored() {
    let ctx = ScanContext(ledger: UsageLedger(startDate: Date()), includeEstimated: false)
    let ok = ctx.record(source: ClaudeCodeReader().info, key: "k", date: nil, tokens: TokenBreakdown(output: 10))
    #expect(!ok)
}

@Test func geminiSessionFile() throws {
    let home = try tempHome()
    let start = Date()
    let json = """
    {"sessionId":"s1","messages":[
      {"id":"a","timestamp":"\(iso(start.addingTimeInterval(-5)))","type":"gemini","tokens":{"input":100,"output":10,"cached":0,"thoughts":0,"tool":0,"total":110}},
      {"id":"b","timestamp":"\(iso(start.addingTimeInterval(5)))","type":"gemini","tokens":{"input":300,"output":20,"cached":100,"thoughts":5,"tool":0,"total":325}}
    ]}
    """
    let file = home.appendingPathComponent(".gemini/tmp/hash/chats/session-1.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try json.write(to: file, atomically: true, encoding: .utf8)
    let ctx = ScanContext(ledger: UsageLedger(startDate: start), includeEstimated: false, home: home)
    try GeminiFamilyReader.gemini.scan(ctx)
    let t = try #require(ctx.ledger.sources["gemini-cli"])
    #expect(t.records == 1)
    #expect(t.tokens.input == 200)
    #expect(t.tokens.cacheRead == 100)
    #expect(t.tokens.output == 25)
}

// MARK: - 育成

@Test func neglectedFishWeakensThenDies() {
    var s = GameState.newGame(now: Date(timeIntervalSince1970: 0))
    s.tank.fish[0].fullness = 100
    // 起動したまま少しずつ進める（再開扱いにしない）
    var t = Date(timeIntervalSince1970: 0)
    func run(hours: Double) {
        let end = t.addingTimeInterval(hours * 3600)
        while t < end { t = t.addingTimeInterval(60); Simulation.advance(&s, to: t) }
    }
    run(hours: 36)
    #expect(s.tank.fish[0].condition == .healthy) // 1日半は元気
    run(hours: 36)
    #expect(s.tank.fish[0].condition == .weak)    // 約3日で弱る
    run(hours: 20)
    #expect(s.tank.fish[0].isAlive)
    run(hours: 28)
    #expect(!s.tank.fish[0].isAlive)              // 約4〜5日で死亡
}

@Test func catchUpIsCappedAndNeverKills() {
    var s = GameState.newGame(now: Date(timeIntervalSince1970: 0))
    s.tank.fish[0].fullness = 10
    s.tank.fish[0].health = 30
    let report = Simulation.advance(&s, to: Date(timeIntervalSince1970: 10 * 24 * 3600))
    #expect(report.isCatchUp)
    #expect(report.simulated == Simulation.maxCatchUp)
    #expect(s.tank.fish[0].isAlive)
    #expect(s.tank.fish[0].health >= Simulation.catchUpHealthFloor)
    #expect(s.tank.fish[0].condition == .critical)
}

@Test func feedingRestoresAndOverfeedingPollutes() {
    var s = GameState.newGame()
    s.tank.fish[0].fullness = 90
    Simulation.feed(&s, now: Date())
    #expect(s.tank.fish[0].fullness == 100)
    #expect(s.tank.waterQuality < 100)
    Simulation.changeWater(&s, now: Date())
    #expect(s.tank.waterQuality == 100)
}

// MARK: - 成長・病気・繁殖・寿命・水槽

/// よくお世話しながら時間を進める（1時間ごとに餌、1日ごとに水換え）。
private func careFor(_ s: inout GameState, from start: Date, hours: Int, water: Bool = true, seed: UInt64 = 1) -> Date {
    var rng = SeededRandom(seed: seed)
    var t = start
    for h in 1...hours {
        t = start.addingTimeInterval(Double(h) * 3600)
        Simulation.advance(&s, to: t, rng: &rng)
        if h % 8 == 0 { Simulation.feed(&s, now: t) }
        if water && h % 24 == 0 { Simulation.changeWater(&s, now: t) }
    }
    return t
}

@Test func caredFishGrowsIntoAdult() {
    let start = Date(timeIntervalSince1970: 0)
    var s = GameState.newGame(now: start)
    s.tank.fish[0].growth = 0
    _ = careFor(&s, from: start, hours: 24 * 3)
    #expect(s.tank.fish[0].stage == .juvenile)
    _ = careFor(&s, from: start.addingTimeInterval(72 * 3600), hours: 24 * 5)
    #expect(s.tank.fish[0].stage == .adult)
}

@Test func dirtyWaterCausesIllnessAndMedicineCures() {
    let start = Date(timeIntervalSince1970: 0)
    var s = GameState.newGame(now: start)
    s.tank.waterQuality = 30
    var rng = SeededRandom(seed: 3)
    var t = start
    var sick = false
    for h in 1...240 where !sick {
        t = start.addingTimeInterval(Double(h) * 3600)
        Simulation.advance(&s, to: t, rng: &rng)
        Simulation.feed(&s, now: t)
        s.tank.waterQuality = 30 // 汚れたまま
        sick = s.tank.fish[0].isSick
    }
    #expect(sick)
    #expect(s.tank.fish[0].condition == .sick || s.tank.fish[0].condition == .critical)
    #expect(!Simulation.giveMedicine(&s, fish: s.tank.fish[0].id)) // 薬がない
    s.medicine = 1
    #expect(Simulation.giveMedicine(&s, fish: s.tank.fish[0].id))
    #expect(!s.tank.fish[0].isSick)
    #expect(s.medicine == 0)
}

@Test func twoHealthyAdultsBreed() {
    let start = Date(timeIntervalSince1970: 0)
    var s = GameState.newGame(now: start)
    s.tank.fish.append(Fish(speciesID: "neon", name: "b", purchasedAt: start))
    for i in s.tank.fish.indices { s.tank.fish[i].growth = 1 }
    _ = careFor(&s, from: start, hours: 24 * 20)
    let fry = s.tank.fish.filter { $0.bornAt >= start && $0.purchasedAt > start }
    #expect(!fry.isEmpty)
    #expect(s.tank.fish.filter(\.isAlive).count <= s.tank.size.maxFish)
}

@Test func fishDiesOfOldAge() {
    let start = Date(timeIntervalSince1970: 0)
    var s = GameState.newGame(now: start)
    let sp = s.tank.fish[0].species
    s.tank.fish[0].bornAt = start.addingTimeInterval(-(sp.lifespanDays - 0.5) * 86400)
    #expect(s.tank.fish[0].isElderly(at: start))
    _ = careFor(&s, from: start, hours: 24)
    #expect(!s.tank.fish[0].isAlive)
    #expect(s.tank.fish[0].deathCause == .oldAge)
}

@Test func starvationDeathRecordsCause() {
    var s = GameState.newGame(now: Date(timeIntervalSince1970: 0))
    s.tank.fish[0].fullness = 0
    s.tank.fish[0].health = 1
    var rng = SeededRandom(seed: 1)
    // 起動中として1分ずつ進める（再開時の下限がかからない）
    for m in 1...60 { Simulation.advance(&s, to: Date(timeIntervalSince1970: Double(m) * 60), rng: &rng) }
    #expect(!s.tank.fish[0].isAlive)
    #expect(s.tank.fish[0].deathCause == .neglect)
}

@Test func oldSaveDataLoadsWithDefaults() throws {
    let json = """
    {"version":1,"createdAt":0,"lastSimulatedAt":0,"coinsSpent":5,"initialCoins":50,"notifiedDangerFish":[],
     "tank":{"waterQuality":80,"decorations":[],"fish":[{"id":"8C1E4C54-1B4B-4E1A-9B77-2B1B6B0D6F11","speciesID":"guppy","name":"g",
       "fullness":50,"health":90,"isAlive":true,"purchasedAt":0,"x":0.2,"y":0.3}]}}
    """
    let s = try JSONDecoder.tokarium.decode(GameState.self, from: Data(json.utf8))
    #expect(s.tank.level == 0)
    #expect(s.medicine == 0)
    #expect(s.tank.fish[0].growth == 0.4)
    #expect(!s.tank.fish[0].isSick)
    #expect(s.coinsSpent == 5)
}

@MainActor
@Test func tankUpgradeRaisesCapacity() throws {
    let dir = try tempHome()
    let store = GameStore(directory: dir)
    #expect(store.state.tank.size.maxFish == 8)
    #expect(store.buyTankUpgrade() == .notEnoughCoins)
    #expect(store.buyMedicine() == nil)
    #expect(store.state.medicine == 1)
    #expect(store.coins == Catalog.initialCoins - Catalog.medicinePrice)
}

@MainActor
@Test func buyingDecorationStartsPlacement() throws {
    let store = GameStore(directory: try tempHome())
    let kind = Catalog.decoration("shell")
    #expect(store.buyDecoration(kind) == nil)
    let id = try #require(store.placingDecoration)
    store.moveDecoration(id, x: 0.3)
    store.finishPlacing()
    #expect(store.placingDecoration == nil)
    let placed = try #require(store.state.tank.decorations.first { $0.id == id })
    #expect(placed.isPlaced && abs(placed.x - 0.3) < 0.001)

    // 置くのをやめると持ち物に入る
    #expect(store.buyDecoration(kind) == nil)
    let second = try #require(store.placingDecoration)
    store.cancelPlacing()
    #expect(store.state.tank.decorations.first { $0.id == second }?.isPlaced == false)
    // 持ち物から出すと、また置き場所を選ぶ
    store.setDecoration(second, placed: true)
    #expect(store.placingDecoration == second)
}

@Test func feedingOneFishOnlyFeedsThatFish() {
    var s = GameState.newGame()
    s.tank.fish.append(Fish(speciesID: "guppy", name: "b", fullness: 40))
    s.tank.fish[0].fullness = 40
    Simulation.feed(&s, fish: s.tank.fish[1].id, now: Date())
    #expect(s.tank.fish[0].fullness == 40)
    #expect(s.tank.fish[1].fullness == 70)
}

@MainActor
@Test func feedingUsesFoodAndFoodCanBeBought() throws {
    let store = GameStore(directory: try tempHome())
    #expect(store.state.food == Catalog.initialFood)
    store.feed()
    #expect(store.state.food == Catalog.initialFood - 1)
    store.feed(fish: store.state.tank.fish[0].id)
    #expect(store.state.food == Catalog.initialFood - 2)

    // 餌がないと餌やりできない
    for _ in 0..<store.state.food { store.feed() }
    #expect(store.state.food == 0)
    let fullness = store.state.tank.fish[0].fullness
    store.feed()
    #expect(store.state.food == 0)
    #expect(store.state.tank.fish[0].fullness <= fullness)

    let pack = Catalog.foodPacks[0]
    let coins = store.coins
    #expect(store.buyFood(pack) == nil)
    #expect(store.state.food == pack.servings)
    #expect(store.coins == coins - pack.price)
}

@Test func oldSaveGetsStarterFood() throws {
    let json = #"{"createdAt":0,"tank":{"fish":[],"decorations":[]}}"#
    let s = try JSONDecoder.tokarium.decode(GameState.self, from: Data(json.utf8))
    #expect(s.food == Catalog.initialFood)
}
