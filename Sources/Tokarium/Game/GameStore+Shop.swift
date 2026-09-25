import Foundation

/// お店と装飾の配置
extension GameStore {
    // MARK: お店

    enum PurchaseError: LocalizedError {
        case notEnoughCoins, tankFull, tooManyDecorations, maxSize
        var errorDescription: String? {
            switch self {
            case .notEnoughCoins: return String(localized: "コインが足りません")
            case .tankFull: return String(localized: "水槽がいっぱいです。お店で水槽を大きくできます")
            case .tooManyDecorations: return String(localized: "これ以上は置けません。持ち物に入りました。お店で水槽を大きくできます")
            case .maxSize: return String(localized: "これ以上大きな水槽はありません")
            }
        }
    }

    @discardableResult
    func buyFish(_ sp: FishSpecies) -> PurchaseError? {
        guard coins >= sp.price else { return .notEnoughCoins }
        guard livingFish.count < state.tank.size.maxFish else { return .tankFull }
        let n = state.tank.fish.filter { $0.speciesID == sp.id }.count + 1
        let fish = Fish(speciesID: sp.id, name: String(localized: "\(sp.name) \(n)号"), fullness: 70, purchasedAt: Date(),
                        x: .random(in: 0.2...0.8), y: sp.zone == .bottom ? 0.82 : 0.15)
        state.addFish(fish, at: Date())
        state.stats.fishBought += 1
        state.coinsSpent += sp.price
        toast = String(localized: "\(sp.name)を水槽に入れました")
        save()
        return nil
    }

    @discardableResult
    func buyDecoration(_ kind: DecorationKind) -> PurchaseError? {
        guard coins >= kind.price else { return .notEnoughCoins }
        let placed = state.tank.decorations.filter(\.isPlaced).count
        let d = Decoration(kindID: kind.id, isPlaced: placed < state.tank.size.maxDecorations,
                           x: .random(in: 0.1...0.9), layer: Int.random(in: 0...1))
        state.tank.decorations.append(d)
        state.coinsSpent += kind.price
        state.stats.decorationsBought += 1
        save()
        if !d.isPlaced { return .tooManyDecorations }
        // 置き場所はユーザーが水槽で決める
        placingDecoration = d.id
        return nil
    }

    @discardableResult
    func buyMedicine() -> PurchaseError? {
        guard coins >= Catalog.medicinePrice else { return .notEnoughCoins }
        state.coinsSpent += Catalog.medicinePrice
        state.medicine += 1
        toast = String(localized: "薬を買いました（持っている数: \(state.medicine)）")
        save()
        return nil
    }

    @discardableResult
    func buyFood(_ pack: FoodPack) -> PurchaseError? {
        guard coins >= pack.price else { return .notEnoughCoins }
        state.coinsSpent += pack.price
        state.food += pack.servings
        toast = String(localized: "餌を買いました（残り \(state.food) 回分）")
        save()
        return nil
    }

    var nextTankSize: TankSize? {
        let next = state.tank.level + 1
        return next < Catalog.tankSizes.count ? Catalog.tankSizes[next] : nil
    }

    @discardableResult
    func buyTankUpgrade() -> PurchaseError? {
        guard let next = nextTankSize else { return .maxSize }
        guard coins >= next.price else { return .notEnoughCoins }
        state.coinsSpent += next.price
        state.tank.level = next.level
        toast = String(localized: "\(next.name)になりました（魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで）")
        save()
        return nil
    }

    func giveMedicine(_ id: UUID) {
        simulate()
        if Simulation.giveMedicine(&state, fish: id) {
            toast = String(localized: "薬をあげました")
            save()
        } else if state.medicine == 0 {
            toast = String(localized: "薬がありません。お店で買えます")
        }
    }

    func moveDecoration(_ id: UUID, x: Double) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        state.tank.decorations[i].x = min(0.97, max(0.03, x))
    }

    func toggleDecorationLayer(_ id: UUID) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        state.tank.decorations[i].layer = state.tank.decorations[i].layer == 0 ? 1 : 0
        save()
    }

    func setDecoration(_ id: UUID, placed: Bool) {
        guard let i = state.tank.decorations.firstIndex(where: { $0.id == id }) else { return }
        if placed && state.tank.decorations.filter(\.isPlaced).count >= state.tank.size.maxDecorations {
            toast = String(localized: "これ以上は置けません")
            return
        }
        state.tank.decorations[i].isPlaced = placed
        placingDecoration = placed ? id : (placingDecoration == id ? nil : placingDecoration)
        save()
    }

    /// 置き場所を決める。
    func finishPlacing() {
        guard let id = placingDecoration, let d = state.tank.decorations.first(where: { $0.id == id }) else { return }
        placingDecoration = nil
        toast = String(localized: "\(d.kind.name)を置きました")
        save()
    }

    /// 置くのをやめて持ち物にしまう。
    func cancelPlacing() {
        guard let id = placingDecoration else { return }
        setDecoration(id, placed: false)
        placingDecoration = nil
    }
}
