import Foundation

/// お世話（餌・水換え・薬・お気に入りなど）
extension GameStore {
    // MARK: お世話

    /// コインも餌もないときの救済: 1日1回分だけ無料で餌をあげられる。
    var rescueFoodAvailable: Bool {
        let cheapest = Catalog.foodPacks.map(\.price).min() ?? 0
        return state.food == 0 && coins < cheapest && state.lastRescueDay != DayKey.key(Date()) && !livingFish.isEmpty
    }

    /// 餌やりができるか（餌があるか、救済の餌が使えるか）。
    var canFeed: Bool { state.food > 0 || rescueFoodAvailable }

    /// 餌を1つ使う。なければ知らせて false。
    func useFood() -> Bool {
        if state.food == 0 && rescueFoodAvailable {
            state.lastRescueDay = DayKey.key(Date())
            toast = String(localized: "コインも餌もないので、今日の1回分は無料であげました。AIを使うとコインが貯まります")
            return true
        }
        guard state.food > 0 else {
            toast = String(localized: "餌がありません。お店で買えます")
            return false
        }
        state.food -= 1
        if state.food == 0 {
            post(title: String(localized: "餌がなくなりました"), body: String(localized: "お店で餌を買ってください。"))
        } else if state.food <= Catalog.lowFood {
            toast = String(localized: "餌が残り \(state.food) 回分です")
        }
        return true
    }

    func feed() {
        simulate()
        guard !livingFish.isEmpty else { toast = String(localized: "餌を食べる魚がいません"); return }
        guard useFood() else { return }
        Simulation.feed(&state, now: Date())
        state.stats.feedings += 1
        engine.dropFood(count: min(24, 4 + livingFish.count * 2))
        save()
    }

    /// 1匹だけに餌をあげる（その魚の近くに餌を落とす）。
    func feed(fish id: UUID) {
        simulate()
        guard let f = state.tank.fish.first(where: { $0.id == id }), f.isAlive else { return }
        guard useFood() else { return }
        Simulation.feed(&state, fish: id, now: Date())
        state.stats.feedings += 1
        engine.dropFood(count: 4, near: engine.position(of: id)?.x ?? f.x)
        toast = String(localized: "\(f.name)に餌をあげました")
        save()
    }

    func changeWater() {
        simulate()
        Simulation.changeWater(&state, now: Date())
        state.stats.waterChanges += 1
        toast = String(localized: "水をきれいにしました")
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = state.tank.fish.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.tank.fish[i].name = String(trimmed.prefix(20))
        save()
    }

    /// お気に入りの魚（主役は1匹）。
    var favoriteFish: Fish? { state.tank.fish.first { $0.isFavorite } }

    /// お気に入りにする（ほかの魚のお気に入りは外す）。もう一度押すと外す。
    func toggleFavorite(_ id: UUID) {
        let wasFavorite = state.tank.fish.first { $0.id == id }?.isFavorite ?? false
        for i in state.tank.fish.indices { state.tank.fish[i].isFavorite = !wasFavorite && state.tank.fish[i].id == id }
        if let f = favoriteFish { toast = String(localized: "\(f.name)をお気に入り（主役）にしました") }
        save()
    }

    /// 死んだ魚とお別れする（水槽から取り出す）。
    func farewell(_ id: UUID) {
        state.tank.fish.removeAll { $0.id == id && !$0.isAlive }
        state.notifiedDangerFish.remove(id)
        save()
    }
}
