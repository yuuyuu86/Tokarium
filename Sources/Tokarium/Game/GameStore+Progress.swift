import Foundation

/// 図鑑・実績・ごほうび・設備
extension GameStore {
    // MARK: 図鑑・実績・ごほうび

    /// 実績・記念の魚・宝箱を確かめる。
    func evaluateProgress(now: Date = Date()) {
        let ctx = AchievementContext(state: state, coinsEarned: ledger.coinsEarned, now: now)
        for a in Achievements.all where state.achievements[a.id] == nil && a.isUnlocked(ctx) {
            state.achievements[a.id] = now
            var body = a.detail
            if let reward = a.reward {
                let kind = Catalog.decoration(reward)
                state.tank.decorations.append(Decoration(kindID: reward, isPlaced: false, x: 0.5))
                body += String(localized: "（ごほうび: \(kind.name) を持ち物に入れました）")
            }
            toast = String(localized: "実績「\(a.title)」を達成しました")
            post(title: String(localized: "実績「\(a.title)」を達成"), body: body)
        }

        // よく使うAIの記念の魚
        for m in MemorialFish.all where !state.memorialsGiven.contains(m.group) && ledger.coins(from: m.sources) >= MemorialFish.threshold {
            state.memorialsGiven.insert(m.group)
            let sp = Catalog.species(m.speciesID)
            if livingFish.count < state.tank.size.maxFish {
                state.addFish(Fish(speciesID: sp.id, name: sp.name, fullness: 80, purchasedAt: now, growth: 1,
                                   x: .random(in: 0.2...0.8), y: 0.3), at: now)
                toast = String(localized: "\(m.label) の記念に「\(sp.name)」がやってきました")
                post(title: String(localized: "記念の魚がやってきました"), body: String(localized: "\(m.label) をたくさん使った記念に、\(sp.name)が水槽に入りました。"))
            } else {
                // 水槽がいっぱいなら、空いたときにもう一度ためす
                state.memorialsGiven.remove(m.group)
            }
        }

        // AIをたくさん使った日は宝箱が流れてくる
        let today = DayKey.key(now)
        if state.lastTreasureDay != today, state.treasureX == nil, ledger.coins(on: today) >= Double(TreasureRule.dailyCoins) {
            state.lastTreasureDay = today
            state.treasureX = .random(in: 0.15...0.85)
            toast = String(localized: "今日はAIをたくさん使いました！ 宝箱が流れてきました")
        }
    }

    /// 宝箱を開ける。
    func openTreasure() {
        guard state.treasureX != nil else { return }
        state.treasureX = nil
        state.food += TreasureRule.rewardFood
        state.medicine += TreasureRule.rewardMedicine
        state.stats.treasures += 1
        toast = String(localized: "宝箱から餌 \(TreasureRule.rewardFood) 回分と薬 \(TreasureRule.rewardMedicine) 個が出てきました")
        evaluateProgress()
        save()
    }

    /// 水槽をたたく（魚が寄ってくる）。
    func touchWater(x: Double, y: Double) {
        engine.touch(x: x, y: y)
        state.stats.touches += 1
    }

    @discardableResult
    func buyEquipment(_ e: Equipment) -> PurchaseError? {
        guard !state.equipment.contains(e.id) else { return nil }
        guard coins >= e.price else { return .notEnoughCoins }
        state.coinsSpent += e.price
        state.equipment.insert(e.id)
        toast = String(localized: "\(e.name)を取りつけました")
        save()
        return nil
    }
}
