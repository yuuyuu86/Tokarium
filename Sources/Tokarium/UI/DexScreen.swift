import SwiftUI

/// 図鑑と実績。
struct DexScreen: View {
    @Environment(GameStore.self) private var store
    @State private var tab = 0

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("図鑑") { tab = 0 }.buttonStyle(PixelButtonStyle(prominent: tab == 0))
                Button("実績") { tab = 1 }.buttonStyle(PixelButtonStyle(prominent: tab == 1))
                Spacer()
                Text(tab == 0 ? summaryDex : summaryAchievements).font(.pixel(.callout)).foregroundStyle(PixelPalette.sand)
            }
            ScrollView {
                if tab == 0 { dex } else { achievements }
            }
        }
    }

    private var shopSpecies: [FishSpecies] { Catalog.fish.filter { !$0.hidden } }

    private var summaryDex: String {
        let seen = shopSpecies.filter { store.state.dex[$0.id] != nil }.count
        return String(localized: "\(seen)/\(shopSpecies.count) 種類（\(Int(Double(seen) / Double(max(1, shopSpecies.count)) * 100))%）")
    }

    private var summaryAchievements: String {
        String(localized: "\(store.state.achievements.count)/\(Achievements.all.count) 達成")
    }

    private var dex: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shopSpecies) { sp in DexCard(species: sp, entry: store.state.dex[sp.id]) }
            }
            Text("記念の魚").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            Text("よく使うAIごとに、そのAIで \(MemorialFish.threshold) コインを得ると記念の魚がやってきます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MemorialFish.all, id: \.group) { m in
                    DexCard(species: Catalog.species(m.speciesID), entry: store.state.dex[m.speciesID],
                            hint: String(localized: "\(m.label): \(min(store.ledger.coins(from: m.sources), MemorialFish.threshold))/\(MemorialFish.threshold) コイン"))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var achievements: some View {
        VStack(spacing: 8) {
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
                    }
                }
                .padding(10)
                .pixelInset()
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
                FishIcon(speciesID: species.id)
                    .padding(8)
                    // まだ迎えていない魚はかげだけ
                    .colorMultiply(entry == nil ? .black : .white)
                    .opacity(entry == nil ? 0.6 : 1)
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
                Text("最大 \(entry.maxGeneration) 代目・天寿 \(entry.oldAge)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            } else if let hint {
                Text(hint).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            } else {
                Text("お店で迎えると記録されます").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            }
        }
        .padding(8)
        .pixelInset()
    }
}
