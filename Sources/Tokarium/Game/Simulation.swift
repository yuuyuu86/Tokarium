import Foundation

/// 育成ルール（確定: 「ゆるめ」）。
///
/// - 餌は1日1〜2回で十分。満腹度は約60時間で100→0。
/// - 放置すると約2日で空腹になり、体調が下がり始める（約3日で「弱っている」）。
/// - 何もしないと約4〜5日で死亡する。
/// - 水質は数日に1回の水換えで保てる。汚れた水が続くと病気になりやすい。
/// - よくお世話された魚は約1週間で稚魚から成魚になる。元気な成魚が2匹以上いると稚魚が生まれることがある。
/// - 魚には種類ごとの寿命がある。
/// - 再開時に反映する経過時間は最大48時間。再開時の反映だけで弱って死亡することはない。
enum Simulation {
    // 1時間あたりの変化量
    static let fullnessDecayPerHour = 100.0 / 60.0
    static let waterDecayBasePerHour = 0.55
    static let waterDecayPerFishPerHour = 0.08
    static let starvingHealthLossPerHour = 2.0
    static let dirtyWaterHealthLossPerHour = 1.5
    static let sickHealthLossPerHour = 1.2
    static let recoveryPerHour = 3.0

    static let hungryThreshold = 35.0
    static let starvingThreshold = 20.0
    static let dirtyWaterThreshold = 25.0

    static let feedAmount = 30.0
    /// 満腹を超えた餌1につき水質がどれだけ下がるか。
    static let overfeedPollution = 0.15

    // 成長
    static let growthPerHour = 1.0 / (7 * 24)

    // 病気
    /// これより水が汚れると病気になることがある。
    static let illnessWaterThreshold = 45.0
    /// 最も汚れた水での1時間あたりの発病確率。
    static let maxIllnessChancePerHour = 0.02
    /// きれいな水で自然に治る1時間あたりの確率。
    static let naturalCureChancePerHour = 0.02
    static let medicineHealthBoost = 10.0

    // 繁殖
    static let breedingChancePerHour = 0.012
    static let breedingCooldown: TimeInterval = 24 * 3600
    static let breedingWaterThreshold = 60.0

    // 色違い
    static let shinyChance = 0.03
    static let shinyChanceFromShinyParent = 0.15

    // 設備
    static let autoFeedInterval: TimeInterval = 8 * 3600
    static let autoFeedBelow = 30.0

    // 寿命
    /// 寿命のこの割合を過ぎると「老齢」。
    static let elderlyFraction = 0.85

    /// これ以上の間隔が空いたら「再開」とみなす（スリープ・終了・非表示を同じ扱いにする）。
    static let resumeGap: TimeInterval = 5 * 60
    /// 再開時に反映する最大の経過時間。
    static let maxCatchUp: TimeInterval = 48 * 3600
    /// 再開時の反映で体調がこれ未満にはならない（長期不在で即死しない）。
    static let catchUpHealthFloor = 5.0

    struct Report {
        var simulated: TimeInterval = 0
        var skipped: TimeInterval = 0
        var isCatchUp = false
        var newlyDead: [Fish] = []
        var newlySick: [Fish] = []
        var births: [Fish] = []
        var grownUp: [Fish] = []
        var autoFed = 0
    }

    /// `state.lastSimulatedAt` から `now` まで時間を進める。
    @discardableResult
    static func advance(_ state: inout GameState, to now: Date) -> Report {
        var rng = SystemRandomNumberGenerator()
        return advance(&state, to: now, rng: &rng)
    }

    @discardableResult
    static func advance<R: RandomNumberGenerator>(_ state: inout GameState, to now: Date, rng: inout R) -> Report {
        var report = Report()
        let elapsed = now.timeIntervalSince(state.lastSimulatedAt)
        guard elapsed > 0 else {
            // 時計が戻った場合は基準だけ合わせる
            if elapsed < 0 { state.lastSimulatedAt = now }
            return report
        }
        let isCatchUp = elapsed > resumeGap
        let span = min(elapsed, maxCatchUp)
        report.isCatchUp = isCatchUp
        report.simulated = span
        report.skipped = elapsed - span

        // 再開時は、反映前の体調（5未満ならその値）を下限にする
        var floors: [UUID: Double] = [:]
        if isCatchUp {
            for f in state.tank.fish where f.isAlive {
                floors[f.id] = min(f.health, catchUpHealthFloor)
            }
        }

        // 反映しない分は時間を飛ばす（年齢は実時間で進む）
        var clock = now.addingTimeInterval(-span)
        var remaining = span
        let step: TimeInterval = 600
        while remaining > 0 {
            let dt = min(step, remaining)
            clock = clock.addingTimeInterval(dt)
            tick(&state, hours: dt / 3600, at: clock, floors: floors, rng: &rng, report: &report)
            remaining -= dt
        }
        state.lastSimulatedAt = now
        return report
    }

    private static func chance<R: RandomNumberGenerator>(_ perHour: Double, hours: Double, rng: inout R) -> Bool {
        guard perHour > 0 else { return false }
        let p = 1 - pow(1 - min(1, perHour), hours)
        return Double.random(in: 0..<1, using: &rng) < p
    }

    private static func tick<R: RandomNumberGenerator>(_ state: inout GameState, hours h: Double, at time: Date,
                                                        floors: [UUID: Double], rng: inout R, report: inout Report) {
        let living = state.tank.fish.filter(\.isAlive).count
        var waterLoss = (waterDecayBasePerHour + waterDecayPerFishPerHour * Double(living)) * h
        if state.equipment.contains(Equipment.filter.id) { waterLoss *= 0.5 }
        waterLoss *= Ecology.waterDecayFactor(state.tank)
        state.tank.waterQuality = clamp(state.tank.waterQuality - waterLoss)
        let water = state.tank.waterQuality

        for i in state.tank.fish.indices where state.tank.fish[i].isAlive {
            var f = state.tank.fish[i]
            f.fullness = clamp(f.fullness - fullnessDecayPerHour * h)

            // 病気
            if f.isSick {
                if water >= 70 && f.fullness >= hungryThreshold && chance(naturalCureChancePerHour, hours: h, rng: &rng) {
                    f.isSick = false
                }
            } else if water < illnessWaterThreshold {
                var p = maxIllnessChancePerHour * (illnessWaterThreshold - water) / illnessWaterThreshold
                if f.health < 60 { p *= 2 }
                if f.isElderly(at: time) { p *= 1.5 }
                if chance(p, hours: h, rng: &rng) {
                    f.isSick = true
                    report.newlySick.append(f)
                }
            }

            // 体調
            var delta = 0.0
            if f.fullness < starvingThreshold { delta -= starvingHealthLossPerHour * h }
            if water < dirtyWaterThreshold { delta -= dirtyWaterHealthLossPerHour * h }
            if f.isSick { delta -= sickHealthLossPerHour * h }
            // 相性の悪い魚がいるとストレスで弱る
            if !Ecology.bulliesOf(f, in: state.tank).isEmpty { delta -= Ecology.stressHealthLossPerHour * h }
            if delta == 0 {
                delta = recoveryPerHour * h * (f.isElderly(at: time) ? 0.5 : 1)
                // 共生の相手がいると早く元気になる
                if Ecology.hasPartner(f, in: state.tank) { delta *= 1.5 }
            }
            f.health = clamp(f.health + delta)
            if let floor = floors[f.id] { f.health = max(f.health, floor) }

            // 成長
            if f.growth < 1 && f.fullness >= hungryThreshold && f.health >= 60 && !f.isSick {
                f.growth = min(1, f.growth + growthPerHour * h)
                if f.growth >= 1 { report.grownUp.append(f) }
            }

            // 死亡
            if f.health <= 0 {
                f.isAlive = false
                f.diedAt = time
                f.deathCause = f.isSick ? .illness : .neglect
            } else if f.lifeFraction(at: time) >= 1 {
                f.isAlive = false
                f.diedAt = time
                f.deathCause = .oldAge
            }
            if !f.isAlive {
                f.isSick = false
                report.newlyDead.append(f)
                state.stats.deaths += 1
                state.stats.lastDeathAt = time
                if f.deathCause == .oldAge { state.dex[f.speciesID, default: DexEntry(firstSeenAt: time)].oldAge += 1 }
            }
            state.tank.fish[i] = f
        }

        autoFeed(&state, at: time, report: &report)

        breed(&state, hours: h, at: time, rng: &rng, report: &report)
    }

    private static func breed<R: RandomNumberGenerator>(_ state: inout GameState, hours h: Double, at time: Date,
                                                         rng: inout R, report: inout Report) {
        guard state.tank.waterQuality >= breedingWaterThreshold else { return }
        if let last = state.lastBirthAt, time.timeIntervalSince(last) < breedingCooldown { return }
        let living = state.tank.fish.filter(\.isAlive)
        let room = state.tank.size.maxFish - living.count
        guard room > 0 else { return }

        let parents = living.filter { $0.stage == .adult && $0.condition == .healthy && $0.fullness >= 50 && !$0.isElderly(at: time) }
        let bySpecies = Dictionary(grouping: parents, by: \.speciesID).filter { $0.value.count >= 2 }
        for (speciesID, group) in bySpecies.sorted(by: { $0.key < $1.key }) {
            guard chance(breedingChancePerHour, hours: h, rng: &rng) else { continue }
            let sp = Catalog.species(speciesID)
            let count = min(room, Int.random(in: 1...3, using: &rng))
            let parent = group[0]
            let generation = (group.map(\.generation).max() ?? 1) + 1
            let shinyChance = group.contains(where: \.isShiny) ? shinyChanceFromShinyParent : Self.shinyChance
            var n = state.tank.fish.filter { $0.speciesID == speciesID }.count
            for _ in 0..<count {
                n += 1
                var fry = Fish(speciesID: speciesID, name: String(localized: "\(sp.name) \(n)号"), fullness: 70, purchasedAt: time, bornAt: time,
                               growth: 0, x: min(0.95, max(0.05, parent.x + .random(in: -0.05...0.05, using: &rng))), y: parent.y)
                fry.generation = generation
                fry.isShiny = Double.random(in: 0..<1, using: &rng) < shinyChance
                state.addFish(fry, at: time, born: true)
                state.stats.births += 1
                report.births.append(fry)
            }
            state.lastBirthAt = time
            return
        }
    }

    /// 自動給餌器: おなかをすかせた魚がいれば、決まった間隔で餌をあげる（餌を使う）。
    private static func autoFeed(_ state: inout GameState, at time: Date, report: inout Report) {
        guard state.equipment.contains(Equipment.feeder.id), state.food > 0 else { return }
        if let last = state.lastAutoFeedAt, time.timeIntervalSince(last) < autoFeedInterval { return }
        guard state.tank.fish.contains(where: { $0.isAlive && $0.fullness < autoFeedBelow }) else { return }
        feed(&state, now: time)
        state.food -= 1
        state.lastAutoFeedAt = time
        report.autoFed += 1
    }

    /// 餌やり。生きている魚すべての満腹度を上げ、食べ残しは水を汚す。
    static func feed(_ state: inout GameState, now: Date) {
        var overflow = 0.0
        for i in state.tank.fish.indices where state.tank.fish[i].isAlive {
            let after = state.tank.fish[i].fullness + feedAmount
            overflow += max(0, after - 100)
            state.tank.fish[i].fullness = min(100, after)
        }
        state.tank.waterQuality = clamp(state.tank.waterQuality - overflow * overfeedPollution)
        state.lastFedAt = now
    }

    /// 1匹だけに餌をあげる。
    static func feed(_ state: inout GameState, fish id: UUID, now: Date) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id && $0.isAlive }) else { return }
        let after = state.tank.fish[i].fullness + feedAmount
        state.tank.fish[i].fullness = min(100, after)
        state.tank.waterQuality = clamp(state.tank.waterQuality - max(0, after - 100) * overfeedPollution)
        state.lastFedAt = now
    }

    static func changeWater(_ state: inout GameState, now: Date) {
        state.tank.waterQuality = 100
        state.lastWaterChangeAt = now
    }

    /// 薬を1つ使って病気を治す。
    @discardableResult
    static func giveMedicine(_ state: inout GameState, fish id: UUID) -> Bool {
        guard state.medicine > 0, let i = state.tank.fish.firstIndex(where: { $0.id == id }),
              state.tank.fish[i].isAlive, state.tank.fish[i].isSick else { return false }
        state.medicine -= 1
        state.tank.fish[i].isSick = false
        state.tank.fish[i].health = clamp(state.tank.fish[i].health + medicineHealthBoost)
        return true
    }

    static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }
}
