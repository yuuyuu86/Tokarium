import SwiftUI

enum DexTab: String, CaseIterable, Identifiable {
    case dex, variants, achievements, hall
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dex: return String(localized: "図鑑")
        case .variants: return String(localized: "品種")
        case .achievements: return String(localized: "実績と称号")
        case .hall: return String(localized: "殿堂")
        }
    }
}

/// 図鑑・品種・実績・殿堂。
struct DexScreen: View {
    @Environment(GameStore.self) private var store
    @State private var tab: DexTab

    init(tab: DexTab = .dex) {
        _tab = State(initialValue: tab)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ForEach(DexTab.allCases) { t in
                    Button(t.title) { tab = t }
                        .buttonStyle(PixelButtonStyle(prominent: tab == t))
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
                Spacer()
                Text(summary).font(.pixel(.callout)).foregroundStyle(PixelPalette.sand)
            }
            ScrollView {
                switch tab {
                case .dex: dex
                case .variants: VariantBook()
                case .achievements: achievements
                case .hall: HallOfFame()
                }
            }
            .id(tab)
        }
    }

    private var shopSpecies: [FishSpecies] { Catalog.fish.filter(\.isRegular) }

    private var summary: String {
        switch tab {
        case .dex:
            let seen = shopSpecies.filter { store.state.dex[$0.id] != nil }.count
            return String(localized: "\(seen)/\(shopSpecies.count) 種類（\(Int(Double(seen) / Double(max(1, shopSpecies.count)) * 100))%）")
        case .variants:
            return String(localized: "品種 \(store.state.variantsDiscovered)")
        case .achievements:
            return String(localized: "\(store.state.achievements.count)/\(Achievements.all.count) 達成")
        case .hall:
            return String(localized: "思い出 \(store.state.memories.count)")
        }
    }

    private var dex: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shopSpecies) { sp in DexCard(species: sp, entry: store.state.dex[sp.id]) }
            }
            Text("隠れた魚").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            Text("お店には並ばない魚です。条件がそろうと、ときどき水槽に迷いこんできます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SecretFish.all, id: \.speciesID) { secret in
                    DexCard(species: Catalog.species(secret.speciesID), entry: store.state.dex[secret.speciesID], hint: secret.hint)
                }
            }
            Text("季節の魚").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SeasonalEvents.all) { event in
                    ForEach(event.fish, id: \.self) { id in
                        DexCard(species: Catalog.species(id), entry: store.state.dex[id],
                                hint: String(localized: "\(event.name)（\(event.periodText)）にお店に並びます"))
                    }
                }
            }
            Text("記念の魚").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            Text("よく使うAIごとに、そのAIで 100・1000・5000 コインを得ると記念の魚がやってきます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MemorialFish.all, id: \.group) { m in
                    ForEach(m.tiers, id: \.key) { tier in
                        DexCard(species: Catalog.species(tier.speciesID), entry: store.state.dex[tier.speciesID],
                                hint: String(localized: "\(m.label): \(min(store.ledger.coins(from: m.sources), tier.threshold))/\(tier.threshold) コイン"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var achievements: some View {
        VStack(spacing: 8) {
            HStack {
                Text("達成した実績は称号として、画面の上に表示できます。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                Spacer()
                if store.state.selectedTitle != nil {
                    Button("称号を外す") { store.setTitle(nil) }
                }
            }
            ForEach(Achievements.all) { a in
                let date = store.state.achievements[a.id]
                HStack(spacing: 12) {
                    Image(systemName: date != nil ? "star.fill" : "star")
                        .foregroundStyle(date != nil ? PixelPalette.gold : PixelPalette.dim)
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.pixel(.callout)).foregroundStyle(date != nil ? PixelPalette.text : PixelPalette.dim)
                        Text(a.detail).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    }
                    Spacer()
                    if let reward = a.reward {
                        HStack(spacing: 6) {
                            DecorationIcon(kindID: reward).frame(width: 30, height: 24).opacity(date != nil ? 1 : 0.35)
                            Text(Catalog.decoration(reward).name).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                    }
                    if let date {
                        Text(date.shortText).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                        if store.state.selectedTitle == a.id {
                            Text("称号にしています").font(.pixel(.caption)).foregroundStyle(PixelPalette.gold)
                        } else {
                            Button("称号にする") { store.setTitle(a.id) }
                        }
                    }
                }
                .padding(10)
                .pixelInsetGold(store.state.selectedTitle == a.id)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DexCard: View {
    let species: FishSpecies
    let entry: DexEntry?
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(colors: [Color(rgb: 0x3190C8), Color(rgb: 0x165D93)], startPoint: .top, endPoint: .bottom)
                // まだ迎えていない魚はかげだけ
                FishIcon(speciesID: species.id, silhouette: entry == nil)
                    .padding(8)
                if let entry, entry.shiny > 0 {
                    Image(systemName: "sparkles").foregroundStyle(PixelPalette.gold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(4)
                }
            }
            .frame(height: 64)
            .overlay(Rectangle().strokeBorder(PixelPalette.deeper, lineWidth: 2))
            Text(entry == nil ? "？？？" : species.name).font(.pixel(.callout)).lineLimit(1)
            if let entry {
                Text("迎えた \(entry.owned)・生まれた \(entry.born)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                Text("最大 \(entry.maxGeneration) 代目・品種 \(entry.variants.count)/\(FishVariant.allCases.count)")
                    .font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            } else if let hint {
                Text(hint).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim).multilineTextAlignment(.center)
            } else {
                Text("お店で迎えると記録されます").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            }
        }
        .padding(8)
        .pixelInset()
    }
}

// MARK: - 品種

private struct VariantBook: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            PixelSection("遺伝のしくみ") {
                Text("魚は色の遺伝子を2つ持ち、両親から1つずつ受け継ぎます。同じ色が2つそろうとその品種になります。ちがう色が1つずつだと、組み合わせの品種になることも。お店の魚の4匹に1匹くらいは、色の遺伝子をかくし持っています。生まれるときに、まれに突然変異が起きます。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                Text("お世話の画面で、同じ種類の魚どうしをペアにできます。ペアから生まれうる品種も見られます。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(FishVariant.allCases.filter(\.isCombination)) { v in
                        let known = store.state.dex.values.contains { $0.variants.contains(v) }
                        HStack {
                            Text(v.label).font(.pixel(.caption)).frame(width: 90, alignment: .leading)
                            Text(known ? (v.recipeHint ?? "") : String(localized: "？？？（見つけるとレシピがわかります）"))
                                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                    }
                }
            }
            let seen = Catalog.fish.filter { store.state.dex[$0.id] != nil }
            if seen.isEmpty {
                Text("魚を迎えると、ここに品種が記録されます。").foregroundStyle(PixelPalette.dim)
            }
            ForEach(seen) { sp in
                let entry = store.state.dex[sp.id]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(sp.name).font(.pixel(.callout))
                        if sp.isRegular {
                            Text("出やすい色: \(Genetics.palette(sp.id).map(\.label).joined(separator: String(localized: "・")))")
                                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                        Spacer()
                        Text("\(entry?.variants.count ?? 0)/\(FishVariant.allCases.count)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], spacing: 6) {
                        ForEach(FishVariant.allCases) { v in
                            let has = entry?.variants.contains(v) ?? false
                            VStack(spacing: 2) {
                                FishIcon(speciesID: sp.id, variant: has ? v : .wild, silhouette: !has)
                                    .frame(height: 22)
                                Text(has ? v.label : "？？？").font(.pixel(.caption2)).lineLimit(1).minimumScaleFactor(0.7)
                                    .foregroundStyle(has ? PixelPalette.text : PixelPalette.dim)
                            }
                            .padding(4)
                            .background(Color(rgb: 0x165D93).opacity(has ? 0.8 : 0.35))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(10)
                .pixelInset()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 殿堂

private struct HallOfFame: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let records = Hall.records(store.state)
            if records.isEmpty {
                Text("魚を育てると、ここに記録が残ります。").foregroundStyle(PixelPalette.dim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(records) { r in
                        HStack(spacing: 10) {
                            FishIcon(fish: r.fish).frame(width: 56, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.pixel(.caption)).foregroundStyle(PixelPalette.gold)
                                Text(r.fish.name).font(.pixel(.callout)).lineLimit(1)
                                Text("\(r.value)・\(r.fish.breedName)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim).lineLimit(1)
                                if !r.fish.isAlive { Text("思い出").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .pixelInsetGold()
                    }
                }
            }
            Text("思い出").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            if store.state.memories.isEmpty {
                Text("お別れした魚は、ここに思い出として残ります。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            ForEach(store.state.memories) { m in
                let f = m.asFish
                HStack(spacing: 12) {
                    FishIcon(speciesID: m.speciesID, shiny: m.isShiny, variant: m.genotype.variant).frame(width: 44, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.pixel(.callout))
                        Text("\(f.breedName)・\(m.generation)代目・\(m.personality.label)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(m.bornAt.shortText) 〜 \(m.diedAt.shortText)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                        Text("\(Int(f.ageDays(at: m.diedAt)))日・\(m.cause.label)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                    }
                }
                .padding(8)
                .pixelInset()
            }
        }
        .padding(.vertical, 4)
    }
}
