import SwiftUI

// MARK: - お世話

struct CareScreen: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        StatBar(title: String(localized: "水質"), value: store.state.tank.waterQuality,
                                word: WaterCondition(store.state.tank.waterQuality).label)
                        HStack(spacing: 12) {
                            Button { store.feed() } label: { Label("餌をあげる", systemImage: "leaf") }
                            Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle") }
                        }
                        .controlSize(.large)
                        Label("持っている薬: \(store.state.medicine) 個", systemImage: "cross.case")
                            .font(.pixel(.callout))
                        Text(careHint).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    }
                    .padding(6)
                } label: {
                    Label("水槽のお世話", systemImage: "drop")
                }

                Text("魚たち").font(.pixel(.headline))
                if store.state.tank.fish.isEmpty {
                    Text("魚がいません。お店で迎えましょう。").foregroundStyle(PixelPalette.dim)
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
        if let fed = store.state.lastFedAt { parts.append(String(localized: "最後の餌やり: \(fed.relativeText)")) } else { parts.append(String(localized: "まだ餌をあげていません")) }
        if let w = store.state.lastWaterChangeAt { parts.append(String(localized: "最後の水換え: \(w.relativeText)")) }
        parts.append(String(localized: "餌は1日1〜2回、水換えは数日に1回が目安です。あげすぎると水が汚れます。汚れた水が続くと病気になりやすくなります。"))
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
                        .font(.pixel(.headline))
                        .frame(maxWidth: 200)
                        .onSubmit { store.rename(fish.id, to: name) }
                    Text(fish.species.name).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    Spacer()
                    if fish.isSick && fish.isAlive {
                        Button { store.giveMedicine(fish.id) } label: { Label("薬をあげる", systemImage: "cross.case") }
                            .disabled(store.state.medicine == 0)
                            .help(store.state.medicine == 0 ? "お店で薬を買えます" : "薬を1つ使って病気を治します")
                    }
                    ConditionBadge(condition: fish.condition)
                }
                Text(lifeText).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                if fish.isAlive {
                    HStack(spacing: 16) {
                        StatBar(title: String(localized: "満腹"), value: fish.fullness, word: fish.fullness < Simulation.hungryThreshold ? String(localized: "空腹") : String(localized: "十分"))
                        StatBar(title: String(localized: "体調"), value: fish.health, word: healthWord)
                    }
                } else {
                    HStack {
                        Text(fish.diedAt.map { "\($0.shortText) に死んでしまいました（\((fish.deathCause ?? .neglect).label)）" } ?? "死んでしまいました")
                            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        Spacer()
                        Button("お別れする") { confirmFarewell = true }
                    }
                }
            }
        }
        .padding(12)
        .pixelInset(highlight: fish.condition.isDanger)
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
        var parts = ["\(fish.stage.label)", String(localized: "\(days)日齢"), String(localized: "寿命の目安 \(Int(fish.species.lifespanDays))日")]
        if fish.stage != .adult && fish.isAlive { parts.append(String(localized: "成長 \(Int(fish.growth * 100))%")) }
        if fish.isElderly() { parts.append(String(localized: "老齢（ゆっくり過ごしています）")) }
        return parts.joined(separator: String(localized: "・"))
    }

    private var healthWord: String {
        switch fish.condition {
        case .critical: return String(localized: "危険")
        case .weak: return String(localized: "弱っている")
        default: return fish.health >= 90 ? String(localized: "良好") : String(localized: "ふつう")
        }
    }
}

// MARK: - お店

enum ShopTab: String, CaseIterable, Identifiable {
    case fish, decorations, supplies
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fish: return String(localized: "魚")
        case .decorations: return String(localized: "装飾")
        case .supplies: return String(localized: "お世話用品・水槽")
        }
    }
}

struct ShopScreen: View {
    @Environment(GameStore.self) private var store
    @State private var message: String?
    @State private var tab: ShopTab = .fish
    @State private var affordableOnly = false

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(ShopTab.allCases) { t in
                    Button(t.title) { tab = t }
                        .buttonStyle(PixelButtonStyle(prominent: tab == t))
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
                Toggle("買えるものだけ", isOn: $affordableOnly).toggleStyle(.checkbox).fixedSize()
                Spacer()
                CoinLabel(coins: store.coins).font(.pixel(.title2))
            }
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .fish: fishSection
                    case .decorations: decorationSection
                    case .supplies: suppliesSection
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }

    @ViewBuilder
    private var fishSection: some View {
        let size = store.state.tank.size
        Text("水槽の魚 \(store.livingFish.count)/\(size.maxFish) 匹").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        ForEach([FishRarity.common, .uncommon, .rare], id: \.self) { rarity in
            let list = Catalog.fish.filter { $0.rarity == rarity && (!affordableOnly || store.coins >= $0.price) }.sorted { $0.price < $1.price }
            if !list.isEmpty {
                Text(rarity.label).font(.pixel(.headline))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { sp in
                        ShopCard(title: sp.name, blurb: sp.blurb, price: sp.price, canAfford: store.coins >= sp.price,
                                 owned: store.livingFish.filter { $0.speciesID == sp.id }.count) {
                            FishIcon(speciesID: sp.id)
                        } buy: {
                            message = store.buyFish(sp)?.errorDescription
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var decorationSection: some View {
        let size = store.state.tank.size
        Text("置いている装飾 \(store.state.tank.decorations.filter(\.isPlaced).count)/\(size.maxDecorations) 個。置いた装飾は「水槽」画面の「配置を編集」で動かせます。")
            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        let stored = store.state.tank.decorations.filter { !$0.isPlaced }
        if !stored.isEmpty {
            Text("持ち物").font(.pixel(.headline))
            ForEach(stored) { d in
                HStack {
                    DecorationIcon(kindID: d.kindID).frame(width: 40, height: 30)
                    Text(d.kind.name)
                    Spacer()
                    Button("水槽に置く") { store.setDecoration(d.id, placed: true) }
                }
            }
        }
        ForEach(DecorationCategory.allCases, id: \.self) { category in
            let list = Catalog.decorations.filter { $0.category == category && (!affordableOnly || store.coins >= $0.price) }.sorted { $0.price < $1.price }
            if !list.isEmpty {
                Text(category.label).font(.pixel(.headline))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { kind in
                        ShopCard(title: kind.name, blurb: kind.blurb, price: kind.price, canAfford: store.coins >= kind.price,
                                 owned: store.state.tank.decorations.filter { $0.kindID == kind.id }.count) {
                            DecorationIcon(kindID: kind.id)
                        } buy: {
                            message = store.buyDecoration(kind)?.errorDescription
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suppliesSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ShopCard(title: String(localized: "薬"), blurb: String(localized: "病気の魚を1匹治します。持っている数: \(store.state.medicine)"),
                     price: Catalog.medicinePrice, canAfford: store.coins >= Catalog.medicinePrice) {
                Image(systemName: "cross.case.fill").font(.system(size: 34)).foregroundStyle(.white)
            } buy: {
                message = store.buyMedicine()?.errorDescription
            }
            if let next = store.nextTankSize {
                ShopCard(title: String(localized: "\(next.name)へ拡張"),
                         blurb: String(localized: "魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで置けます。"),
                         price: next.price, canAfford: store.coins >= next.price) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 30)).foregroundStyle(.white)
                } buy: {
                    message = store.buyTankUpgrade()?.errorDescription
                }
            }
        }
        let size = store.state.tank.size
        Text("いまの水槽: \(size.name)（魚 \(store.livingFish.count)/\(size.maxFish) 匹・装飾 \(store.state.tank.decorations.filter(\.isPlaced).count)/\(size.maxDecorations) 個）")
            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
    }
}

private struct ShopCard<Icon: View>: View {
    let title: String
    let blurb: String
    let price: Int
    let canAfford: Bool
    var owned = 0
    @ViewBuilder let icon: () -> Icon
    let buy: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            icon()
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(LinearGradient(colors: [Color(rgb: 0x3190C8), Color(rgb: 0x165D93)], startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().strokeBorder(PixelPalette.deeper, lineWidth: 2))
            HStack(spacing: 4) {
                Text(title).font(.pixel(.headline))
                if owned > 0 {
                    Text("×\(owned)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        .help("水槽にいる数")
                }
            }
            Text(blurb).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim).multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            Button(action: buy) {
                Label("\(price) コインで買う", systemImage: "cart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(prominent: canAfford))
            .disabled(!canAfford)
            .help(canAfford ? "" : "コインが足りません")
        }
        .padding(10)
        .pixelInset()
    }
}
