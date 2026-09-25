import SwiftUI

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

    /// まだランクが足りなければ、必要なランク。
    private func lock(_ rank: Int) -> Int? { store.state.rank < rank ? rank : nil }

    @ViewBuilder
    private var fishSection: some View {
        let size = store.state.tank.size
        Text("水槽の魚 \(store.livingFish.count)/\(size.maxFish) 匹").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        if let event = SeasonalEvents.active() {
            eventHeader(event)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(event.fish, id: \.self) { id in fishCard(Catalog.species(id)) }
            }
        }
        ForEach([FishRarity.common, .uncommon, .rare], id: \.self) { rarity in
            let list = Catalog.fish.filter { $0.isRegular && $0.rarity == rarity && (!affordableOnly || store.coins >= $0.price) }.sorted { $0.price < $1.price }
            if !list.isEmpty {
                Text(rarity.label).font(.pixel(.headline))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { sp in fishCard(sp) }
                }
            }
        }
    }

    private func fishCard(_ sp: FishSpecies) -> some View {
        let conflicts = Ecology.conflicts(buying: sp.id, into: store.state.tank)
        return ShopCard(title: sp.name, blurb: sp.blurb, price: sp.price, canAfford: store.coins >= sp.price,
                        lockedRank: lock(KeeperRank.required(sp)),
                        owned: store.livingFish.filter { $0.speciesID == sp.id }.count,
                        tags: Ecology.traits(sp.id),
                        warning: conflicts.isEmpty ? nil : String(localized: "相性注意: \(conflicts.map { Catalog.species($0).name }.joined(separator: "、"))")) {
            FishIcon(speciesID: sp.id)
        } buy: {
            message = store.buyFish(sp)?.errorDescription
        }
    }

    private func eventHeader(_ event: SeasonalEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.symbol).foregroundStyle(PixelPalette.gold)
            Text("期間限定: \(event.name)（\(event.periodText)）").font(.pixel(.headline)).foregroundStyle(PixelPalette.gold)
        }
    }

    @ViewBuilder
    private var decorationSection: some View {
        let size = store.state.tank.size
        if let event = SeasonalEvents.active() {
            eventHeader(event)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(event.decorations, id: \.self) { id in
                    let kind = Catalog.decoration(id)
                    ShopCard(title: kind.name, blurb: kind.blurb, price: kind.price, canAfford: store.coins >= kind.price,
                             owned: store.state.tank.decorations.filter { $0.kindID == kind.id }.count) {
                        DecorationIcon(kindID: kind.id)
                    } buy: {
                        message = store.buyDecoration(kind)?.errorDescription
                    }
                }
            }
        }
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
            let list = Catalog.decorations.filter { $0.isRegular && $0.category == category && (!affordableOnly || store.coins >= $0.price) }.sorted { $0.price < $1.price }
            if !list.isEmpty {
                Text(category.label).font(.pixel(.headline))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { kind in
                        ShopCard(title: kind.name, blurb: kind.blurb, price: kind.price, canAfford: store.coins >= kind.price,
                                 lockedRank: lock(KeeperRank.required(kind)),
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
        Text("持っている餌: \(store.state.food) 回分　／　薬: \(store.state.medicine) 個").font(.pixel(.callout))
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Catalog.foodPacks) { pack in
                ShopCard(title: String(localized: "餌（\(pack.servings)回分）"),
                         blurb: String(localized: "餌やり1回で1つ使います。"),
                         price: pack.price, canAfford: store.coins >= pack.price) {
                    FoodIcon(servings: pack.servings)
                } buy: {
                    message = store.buyFood(pack)?.errorDescription
                }
            }
            ForEach(Equipment.all) { e in
                let owned = store.state.equipment.contains(e.id)
                ShopCard(title: e.name, blurb: e.blurb, price: e.price, canAfford: !owned && store.coins >= e.price,
                         lockedRank: owned ? nil : lock(KeeperRank.equipmentRank)) {
                    Image(systemName: owned ? "checkmark.seal.fill" : e.symbol).font(.system(size: 30)).foregroundStyle(.white)
                } buy: {
                    message = store.buyEquipment(e)?.errorDescription
                }
                .overlay(alignment: .topTrailing) {
                    if owned { Text("取りつけ済み").font(.pixel(.caption2)).padding(6).foregroundStyle(PixelPalette.gold) }
                }
            }
            ShopCard(title: String(localized: "薬"), blurb: String(localized: "病気の魚を1匹治します。持っている数: \(store.state.medicine)"),
                     price: Catalog.medicinePrice, canAfford: store.coins >= Catalog.medicinePrice) {
                Image(systemName: "cross.case.fill").font(.system(size: 34)).foregroundStyle(.white)
            } buy: {
                message = store.buyMedicine()?.errorDescription
            }
            if let next = store.nextTankSize {
                ShopCard(title: String(localized: "\(next.name)へ拡張"),
                         blurb: String(localized: "魚 \(next.maxFish) 匹・装飾 \(next.maxDecorations) 個まで置けます。"),
                         price: next.price, canAfford: store.coins >= next.price,
                         lockedRank: lock(KeeperRank.required(tankLevel: next.level))) {
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

/// 餌の袋のドット絵（多いほど袋が大きい）。
private struct FoodIcon: View {
    let servings: Int

    var body: some View {
        Canvas { ctx, size in
            let rows = ["..kkkkkk..", ".kyyyyyyk.", "kyyyyyyyyk", "kybbyybbyk", "kyyyyyyyyk", "kyrrrrrryk", "kyrwwwwryk",
                        "kyrrrrrryk", "kyyyyyyyyk", ".kkkkkkkk."]
            let palette: [Character: Color] = ["k": Color(rgb: 0x3A2410), "y": Color(rgb: 0xE8C060), "b": Color(rgb: 0x8B4A1C),
                                               "r": Color(rgb: 0xD84A3A), "w": Color(rgb: 0xFFF4E0)]
            let scale = servings >= 100 ? 1.0 : servings >= 30 ? 0.85 : 0.7
            let p = floor(min(size.width, size.height) / 10 * scale)
            let ox = (size.width - p * 10) / 2, oy = (size.height - p * 10) / 2
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    ctx.fill(Path(CGRect(x: ox + CGFloat(c) * p, y: oy + CGFloat(r) * p, width: p, height: p)), with: .color(color))
                }
            }
        }
    }
}

private struct ShopCard<Icon: View>: View {
    let title: String
    let blurb: String
    let price: Int
    let canAfford: Bool
    /// ランクが足りないとき、必要なランク（買えない）。
    var lockedRank: Int? = nil
    var owned = 0
    var tags: [String] = []
    var warning: String? = nil
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
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).font(.pixel(.caption2)).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(PixelFrame(fill: PixelPalette.sea.opacity(0.6), border: PixelPalette.sea, outline: .clear, step: 1))
                    }
                }
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.pixel(.caption2))
                    .foregroundStyle(Color(rgb: 0xFFA030)).lineLimit(2).multilineTextAlignment(.center)
            }
            if let lockedRank {
                Label("ランク \(lockedRank) で並びます", systemImage: "lock.fill")
                    .font(.pixel(.callout))
                    .foregroundStyle(PixelPalette.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .pixelInset()
            } else {
                Button(action: buy) {
                    Label("\(price) コインで買う", systemImage: "cart")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(prominent: canAfford))
                .disabled(!canAfford)
                .help(canAfford ? "" : "コインが足りません")
            }
        }
        .padding(10)
        .pixelInset()
    }
}
