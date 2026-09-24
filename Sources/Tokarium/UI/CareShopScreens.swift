import SwiftUI

// MARK: - お世話

struct CareScreen: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        StatBar(title: "水質", value: store.state.tank.waterQuality,
                                word: WaterCondition(store.state.tank.waterQuality).label)
                        HStack(spacing: 12) {
                            Button { store.feed() } label: { Label("餌をあげる", systemImage: "leaf") }
                            Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle") }
                        }
                        .controlSize(.large)
                        Label("持っている薬: \(store.state.medicine) 個", systemImage: "cross.case")
                            .font(.callout)
                        Text(careHint).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(6)
                } label: {
                    Label("水槽のお世話", systemImage: "drop")
                }

                Text("魚たち").font(.headline)
                if store.state.tank.fish.isEmpty {
                    Text("魚がいません。お店で迎えましょう。").foregroundStyle(.secondary)
                }
                ForEach(store.state.tank.fish.sorted { ($0.isAlive ? $0.health : 999) < ($1.isAlive ? $1.health : 999) }) { f in
                    FishRow(fish: f)
                }
            }
            .padding(20)
        }
    }

    private var careHint: String {
        var parts: [String] = []
        if let fed = store.state.lastFedAt { parts.append("最後の餌やり: \(fed.relativeText)") } else { parts.append("まだ餌をあげていません") }
        if let w = store.state.lastWaterChangeAt { parts.append("最後の水換え: \(w.relativeText)") }
        parts.append("餌は1日1〜2回、水換えは数日に1回が目安です。あげすぎると水が汚れます。汚れた水が続くと病気になりやすくなります。")
        return parts.joined(separator: "　")
    }
}

private struct FishRow: View {
    @Environment(GameStore.self) private var store
    let fish: Fish
    @State private var name = ""
    @State private var confirmFarewell = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive)
                .frame(width: 56, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("名前", text: $name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .frame(maxWidth: 200)
                        .onSubmit { store.rename(fish.id, to: name) }
                    Text(fish.species.name).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if fish.isSick && fish.isAlive {
                        Button { store.giveMedicine(fish.id) } label: { Label("薬をあげる", systemImage: "cross.case") }
                            .disabled(store.state.medicine == 0)
                            .help(store.state.medicine == 0 ? "お店で薬を買えます" : "薬を1つ使って病気を治します")
                    }
                    ConditionBadge(condition: fish.condition)
                }
                Text(lifeText).font(.caption).foregroundStyle(.secondary)
                if fish.isAlive {
                    HStack(spacing: 16) {
                        StatBar(title: "満腹", value: fish.fullness, word: fish.fullness < Simulation.hungryThreshold ? "空腹" : "十分")
                        StatBar(title: "体調", value: fish.health, word: healthWord)
                    }
                } else {
                    HStack {
                        Text(fish.diedAt.map { "\($0.shortText) に\((fish.deathCause ?? .neglect).label)死んでしまいました" } ?? "死んでしまいました")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("お別れする") { confirmFarewell = true }
                    }
                }
            }
        }
        .padding(12)
        .background(fish.condition.isDanger ? Color.red.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { name = fish.name }
        .onChange(of: fish.name) { _, new in name = new }
        .confirmationDialog("\(fish.name)とお別れしますか？", isPresented: $confirmFarewell) {
            Button("お別れする", role: .destructive) { store.farewell(fish.id) }
        } message: {
            Text("水槽から取り出します。元には戻せません。")
        }
    }

    private var lifeText: String {
        let days = Int(fish.ageDays(at: fish.diedAt ?? Date()))
        var parts = ["\(fish.stage.label)", "\(days)日齢", "寿命の目安 \(Int(fish.species.lifespanDays))日"]
        if fish.stage != .adult && fish.isAlive { parts.append("成長 \(Int(fish.growth * 100))%") }
        if fish.isElderly() { parts.append("老齢（ゆっくり過ごしています）") }
        return parts.joined(separator: "・")
    }

    private var healthWord: String {
        switch fish.condition {
        case .critical: return "危険"
        case .weak: return "弱っている"
        default: return fish.health >= 90 ? "良好" : "ふつう"
        }
    }
}

// MARK: - お店

struct ShopScreen: View {
    @Environment(GameStore.self) private var store
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("所持コイン").foregroundStyle(.secondary)
                    CoinLabel(coins: store.coins).font(.title2)
                    Spacer()
                    Text("\(Int(CurrencyRule.tokensPerCoin)) トークン（重み付き）で 1 コイン").font(.caption).foregroundStyle(.secondary)
                }
                Text("魚").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Catalog.fish) { sp in
                        ShopCard(title: sp.name, blurb: sp.blurb, price: sp.price, canAfford: store.coins >= sp.price) {
                            FishIcon(speciesID: sp.id)
                        } buy: {
                            message = store.buyFish(sp)?.errorDescription
                        }
                    }
                }
                Text("装飾").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Catalog.decorations) { kind in
                        ShopCard(title: kind.name, blurb: kind.blurb, price: kind.price, canAfford: store.coins >= kind.price) {
                            DecorationIcon(kindID: kind.id)
                        } buy: {
                            message = store.buyDecoration(kind)?.errorDescription
                        }
                    }
                }
                Text("お世話用品・水槽").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ShopCard(title: "薬", blurb: "病気の魚を1匹治します。持っている数: \(store.state.medicine)",
                             price: Catalog.medicinePrice, canAfford: store.coins >= Catalog.medicinePrice) {
                        Image(systemName: "cross.case.fill").font(.system(size: 34)).foregroundStyle(.white)
                    } buy: {
                        message = store.buyMedicine()?.errorDescription
                    }
                    if let next = store.nextTankSize {
                        ShopCard(title: "\(next.name)へ拡張", blurb: "魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで置けます。",
                                 price: next.price, canAfford: store.coins >= next.price) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 30)).foregroundStyle(.white)
                        } buy: {
                            message = store.buyTankUpgrade()?.errorDescription
                        }
                    }
                }
                let size = store.state.tank.size
                Text("いまの水槽: \(size.name)（魚 \(store.livingFish.count)/\(size.maxFish) 匹・装飾 \(store.state.tank.decorations.filter(\.isPlaced).count)/\(size.maxDecorations) 個）")
                    .font(.caption).foregroundStyle(.secondary)
                let stored = store.state.tank.decorations.filter { !$0.isPlaced }
                if !stored.isEmpty {
                    Text("持ち物").font(.headline)
                    ForEach(stored) { d in
                        HStack {
                            DecorationIcon(kindID: d.kindID).frame(width: 40, height: 30)
                            Text(d.kind.name)
                            Spacer()
                            Button("水槽に置く") { store.setDecoration(d.id, placed: true) }
                        }
                    }
                }
                Text("置いた装飾は「水槽」画面の「配置を編集」で動かせます。").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}

private struct ShopCard<Icon: View>: View {
    let title: String
    let blurb: String
    let price: Int
    let canAfford: Bool
    @ViewBuilder let icon: () -> Icon
    let buy: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            icon()
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(rgb: 0x2680B8).opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(.headline)
            Text(blurb).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
            Button(action: buy) {
                Label("\(price) コインで買う", systemImage: "cart")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canAfford)
            .help(canAfford ? "" : "コインが足りません")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}
