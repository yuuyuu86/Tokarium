import Foundation

/// やり込み要素（飼育員ランク・ミッション・品種・なつき度・隠れた魚・殿堂・称号・レイアウトの評価）
extension GameStore {
    // MARK: 経験値とランク

    /// 経験値を足し、ランクが上がったら知らせる。
    func gainXP(_ event: XPEvent, amount: Int? = nil) {
        if let rank = state.gainXP(event, amount: amount) { announceRankUp(rank) }
    }

    func announceRankUp(_ rank: Int) {
        let unlocked = KeeperRank.unlocked(at: rank)
        var msg = String(localized: "飼育員ランク \(rank)（\(KeeperRank.title(rank))）になりました")
        if !unlocked.isEmpty { msg += String(localized: "。お店に新しく \(unlocked.count) 個並びました") }
        toast = msg
        sfx(.fanfare)
        post(title: String(localized: "ランク \(rank) になりました"),
             body: unlocked.isEmpty ? KeeperRank.title(rank) : String(localized: "お店に並んだもの: \(unlocked.joined(separator: String(localized: "、")))"))
    }

    // MARK: ミッション

    /// 行動をミッションに数える。達成したら知らせる。
    func questEvent(_ kind: QuestKind, count: Int = 1) {
        let done = state.questEvent(kind, count: count)
        if let q = done.first {
            toast = String(localized: "ミッション「\(q.template.title)」を達成しました。ミッションの画面でごほうびを受け取れます")
            sfx(.sparkle, spontaneous: kind == .cleanMinutes || kind == .birth || kind == .grownUp || kind == .newVariant)
        }
    }

    /// ミッションのごほうびを受け取る。
    func claim(_ quest: Quest) {
        let before = state.rank
        guard let reward = state.claim(quest) else { return }
        toast = String(localized: "ごほうび: \(reward.text)")
        sfx(.treasure)
        if state.rank > before { announceRankUp(state.rank) }
        evaluateProgress()
        save()
    }

    /// 受け取れるごほうびをまとめて受け取る。
    func claimAll() {
        for q in state.claimableQuests() { claim(q) }
    }

    // MARK: 今日の入荷

    var todaysStock: [StockOffer] { DailyStock.offers(rank: state.rank) }

    @discardableResult
    func buyStock(_ offer: StockOffer) -> PurchaseError? {
        guard !state.stockBought.contains(offer.id) else { return nil }
        guard coins >= offer.price else { return failed(.notEnoughCoins) }
        guard livingFish.count < state.tank.size.maxFish else { return failed(.tankFull) }
        let gene = ColorGene(rawValue: offer.variant.rawValue) ?? .gold
        var fish = Fish(speciesID: offer.speciesID, name: offer.name, fullness: 70, purchasedAt: Date(),
                        x: .random(in: 0.2...0.8), y: offer.species.zone == .bottom ? 0.82 : 0.15)
        fish.genotype = Genotype(a: gene, b: gene)
        state.addFish(fish, at: Date())
        state.stats.fishBought += 1
        state.coinsSpent += offer.price
        // 過ぎた日の記録は消す
        let today = DayKey.key(Date())
        state.stockBought = state.stockBought.filter { $0.hasPrefix(today) }
        state.stockBought.insert(offer.id)
        toast = String(localized: "\(offer.name)を水槽に入れました")
        sfx(.buy)
        sfx(.tap)
        evaluateProgress()
        save()
        return nil
    }

    // MARK: かけらの交換

    @discardableResult
    func exchange(_ kind: DecorationKind) -> PurchaseError? {
        guard let cost = kind.fragmentPrice else { return nil }
        guard state.fragments >= cost else { return failed(.notEnoughFragments) }
        state.fragments -= cost
        let placed = state.tank.decorations.filter(\.isPlaced).count
        let d = Decoration(kindID: kind.id, isPlaced: placed < state.tank.size.maxDecorations, x: .random(in: 0.1...0.9))
        state.tank.decorations.append(d)
        sfx(.buy)
        save()
        if !d.isPlaced { return .tooManyDecorations }
        placingDecoration = d.id
        return nil
    }

    // MARK: 品種と繁殖

    /// 繁殖の相手を決める（同じ種類の魚どうし）。nil で解除。
    func setPartner(_ id: UUID, to mate: UUID?) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id }) else { return }
        // 前の相手との組を解く
        for j in state.tank.fish.indices where state.tank.fish[j].partnerID == id || state.tank.fish[j].id == mate {
            state.tank.fish[j].partnerID = nil
        }
        if let old = state.tank.fish[i].partnerID, let j = state.tank.fish.firstIndex(where: { $0.id == old }) {
            state.tank.fish[j].partnerID = nil
        }
        state.tank.fish[i].partnerID = mate
        if let mate, let j = state.tank.fish.firstIndex(where: { $0.id == mate }) {
            state.tank.fish[j].partnerID = id
            toast = String(localized: "\(state.tank.fish[i].name)と\(state.tank.fish[j].name)をペアにしました")
            sfx(.sparkle)
        }
        save()
    }

    /// ペアの相手（生きていて同じ種類のときだけ）。
    func partner(of fish: Fish) -> Fish? {
        guard let id = fish.partnerID else { return nil }
        return state.tank.fish.first { $0.id == id && $0.isAlive && $0.speciesID == fish.speciesID }
    }

    // MARK: なつき度

    func addAffection(_ id: UUID, _ amount: Double) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id && $0.isAlive }) else { return }
        let f = state.tank.fish[i]
        state.tank.fish[i].affection = min(Affection.max, f.affection + amount * f.personality.affectionFactor)
    }

    /// 水をたたいた場所の近くの魚が、少しなつく（1分に1回まで）。
    func petFish(near x: Double, y: Double, now: Date = Date()) {
        for i in state.tank.fish.indices where state.tank.fish[i].isAlive {
            let f = state.tank.fish[i]
            guard let pos = engine.position(of: f.id), hypot(pos.x - x, pos.y - y) < 0.2 else { continue }
            if let last = f.lastPettedAt, now.timeIntervalSince(last) < Affection.touchInterval { continue }
            state.tank.fish[i].lastPettedAt = now
            addAffection(f.id, Affection.perTouch)
        }
    }

    // MARK: 称号

    /// 表示する称号（達成した実績の名前）。
    var titleText: String? {
        guard let id = state.selectedTitle, state.achievements[id] != nil else { return nil }
        return Achievements.achievement(id)?.title
    }

    func setTitle(_ id: String?) {
        state.selectedTitle = id
        if let id, let a = Achievements.achievement(id) {
            toast = String(localized: "称号を「\(a.title)」にしました")
            sfx(.sparkle)
        }
        save()
    }

    // MARK: レイアウトの評価

    var layoutScore: LayoutScore { Layout.score(state.tank) }

    /// 装飾を置いた・動かしたあと。ミッションに数え、いちばんよい評価を更新する。
    func decorationArranged() {
        questEvent(.placeDecoration)
        let score = layoutScore.total
        if score > state.bestLayoutScore {
            let gained = score - state.bestLayoutScore
            state.bestLayoutScore = score
            gainXP(.layout, amount: gained)
            if score >= 50 { toast = String(localized: "レイアウトの評価が \(score) 点になりました（自己ベスト）") }
        }
        evaluateProgress()
        save()
    }

    // MARK: 殿堂

    /// お別れする魚を思い出に残す。
    func remember(_ fish: Fish) {
        state.memories.insert(FishMemory(fish), at: 0)
        if state.memories.count > Hall.maxMemories { state.memories.removeLast(state.memories.count - Hall.maxMemories) }
    }

    // MARK: 時間経過で起きること

    /// 時間経過のあとに、ミッション・経験値・隠れた魚を反映する。
    func applyGrowth(_ report: Simulation.Report, now: Date) {
        if !report.births.isEmpty {
            gainXP(.birth)
            questEvent(.birth)
        }
        for _ in report.grownUp { gainXP(.grownUp) }
        if !report.grownUp.isEmpty { questEvent(.grownUp, count: report.grownUp.count) }

        // 水がきれいだった時間
        if state.tank.waterQuality >= 70 {
            cleanMinutesCarry += report.simulated / 60
            let whole = Int(cleanMinutesCarry)
            if whole > 0 {
                cleanMinutesCarry -= Double(whole)
                questEvent(.cleanMinutes, count: whole)
            }
        }

        var rng = SystemRandomNumberGenerator()
        if let visitor = state.visitSecretFish(hours: report.simulated / 3600, now: now, rng: &rng) {
            toast = String(localized: "隠れた魚「\(visitor.name)」が迷いこんできました！")
            sfx(.fanfare, spontaneous: true)
            post(title: String(localized: "隠れた魚がやってきました"), body: String(localized: "\(visitor.name)が水槽に迷いこんできました。図鑑に記録しました。"))
            gainXP(.secret)
        }
    }

    /// 図鑑・品種・実績・天寿の増えた分だけ経験値を渡す。
    func awardProgressXP() {
        let now = state.currentXPCounts
        var counted = state.xpCounted
        if now.species > counted.species { gainXP(.newSpecies, amount: (now.species - counted.species) * XPEvent.newSpecies.amount) }
        if now.variants > counted.variants {
            let diff = now.variants - counted.variants
            gainXP(.newVariant, amount: diff * XPEvent.newVariant.amount)
            questEvent(.newVariant, count: diff)
            toast = String(localized: "新しい品種を図鑑に登録しました")
            sfx(.sparkle, spontaneous: true)
        }
        if now.achievements > counted.achievements {
            gainXP(.achievement, amount: (now.achievements - counted.achievements) * XPEvent.achievement.amount)
        }
        if now.oldAge > counted.oldAge { gainXP(.oldAge, amount: (now.oldAge - counted.oldAge) * XPEvent.oldAge.amount) }
        counted = now
        state.xpCounted = counted
    }
}
