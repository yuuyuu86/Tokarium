import SwiftUI

// MARK: - お題と飼育員ランク

struct QuestScreen: View {
    @Environment(GameStore.self) private var store
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RankCard()
                let claimable = store.state.claimableQuests()
                if claimable.count > 1 {
                    Button { store.claimAll() } label: {
                        Label("ごほうびをまとめて受け取る（\(claimable.count)）", systemImage: "gift.fill")
                    }
                    .buttonStyle(.pixelProminent)
                }
                PixelSection("今日のお題") {
                    ForEach(Quests.today()) { QuestRow(quest: $0) }
                    Text("毎日0時に新しいお題に変わります。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                PixelSection("今週のお題") {
                    ForEach(Quests.thisWeek()) { QuestRow(quest: $0) }
                    Text("毎週月曜日に新しいお題に変わります。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                exchange
            }
            .padding(.vertical, 4)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }

    private var exchange: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("かけらの交換所").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
                Spacer()
                FragmentLabel(count: store.state.fragments).font(.pixel(.title3))
            }
            Text("お題でもらえるかけらを集めると、ここでしか手に入らない装飾と交換できます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Catalog.questDecorations) { kind in
                    let cost = kind.fragmentPrice ?? 0
                    let owned = store.state.tank.decorations.filter { $0.kindID == kind.id }.count
                    VStack(spacing: 8) {
                        DecorationIcon(kindID: kind.id)
                            .frame(height: 56).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(LinearGradient(colors: [Color(rgb: 0x3190C8), Color(rgb: 0x165D93)], startPoint: .top, endPoint: .bottom))
                            .overlay(Rectangle().strokeBorder(PixelPalette.deeper, lineWidth: 2))
                        HStack(spacing: 4) {
                            Text(kind.name).font(.pixel(.headline))
                            if owned > 0 { Text("×\(owned)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim) }
                        }
                        Text(kind.blurb).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                            .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                        Button { message = store.exchange(kind)?.errorDescription } label: {
                            Label("かけら \(cost) 個で交換", systemImage: "sparkles")
                                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PixelButtonStyle(prominent: store.state.fragments >= cost))
                        .disabled(store.state.fragments < cost)
                    }
                    .padding(10)
                    .pixelInset()
                }
            }
        }
    }
}

/// 飼育員ランクと、次のランクまでの進み具合。
struct RankCard: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        let xp = store.state.xp
        let rank = store.state.rank
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ランク \(rank)").font(.pixel(.title2)).foregroundStyle(PixelPalette.gold)
                Text(KeeperRank.title(rank)).font(.pixel(.headline))
                if let title = store.titleText {
                    Text("【\(title)】").font(.pixel(.callout)).foregroundStyle(PixelPalette.sand)
                }
                Spacer()
                Text("経験値 \(xp)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim).monospacedDigit()
            }
            if rank < KeeperRank.maxRank {
                PixelBar(value: KeeperRank.progress(xp: xp) * 100, color: PixelPalette.gold)
                let next = KeeperRank.xpRequired(for: rank + 1)
                let unlocks = KeeperRank.unlocked(at: rank + 1)
                Text(unlocks.isEmpty
                     ? String(localized: "次のランクまで あと \(next - xp)")
                     : String(localized: "次のランクまで あと \(next - xp)。お店に並ぶもの: \(unlocks.joined(separator: String(localized: "、")))"))
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            } else {
                Text("最高ランクです。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            Text("餌やり・水換え（1日の回数に上限あり）、稚魚の誕生、成長、図鑑や品種の登録、実績、お題で経験値がたまります。")
                .font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
        }
        .padding(12)
        .pixelInsetGold()
    }
}

private struct QuestRow: View {
    @Environment(GameStore.self) private var store
    let quest: Quest

    var body: some View {
        let t = quest.template
        let progress = store.state.progress(of: quest)
        let done = store.state.isDone(quest)
        let claimed = store.state.isClaimed(quest)
        HStack(spacing: 12) {
            Image(systemName: claimed ? "checkmark.seal.fill" : done ? "gift.fill" : "circle")
                .foregroundStyle(claimed ? PixelPalette.dim : done ? PixelPalette.gold : PixelPalette.sand)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(.pixel(.callout)).foregroundStyle(claimed ? PixelPalette.dim : PixelPalette.text)
                HStack(spacing: 8) {
                    PixelBar(value: Double(progress) / Double(max(1, t.target)) * 100, color: done ? PixelPalette.gold : Color(rgb: 0x5FD068))
                        .frame(width: 140)
                    Text(progressText(progress, t)).font(.pixel(.caption)).monospacedDigit().foregroundStyle(PixelPalette.dim)
                }
                Text("ごほうび: \(t.reward.text)").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            }
            Spacer()
            if claimed {
                Text("受け取り済み").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            } else {
                Button("受け取る") { store.claim(quest) }
                    .buttonStyle(PixelButtonStyle(prominent: done))
                    .disabled(!done)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func progressText(_ p: Int, _ t: QuestTemplate) -> String {
        if t.kind == .cleanMinutes {
            return String(format: String(localized: "%.1f/%lld 時間"), Double(p) / 60, t.target / 60)
        }
        return "\(p)/\(t.target)"
    }
}

/// かけらの数。
struct FragmentLabel: View {
    let count: Int
    var body: some View {
        Label {
            Text("\(count)").monospacedDigit()
        } icon: {
            Image(systemName: "sparkles").foregroundStyle(Color(rgb: 0xB0E0FF))
        }
        .accessibilityLabel("かけら \(count) 個")
    }
}

/// なつき度のハート（5つ）。
struct HeartsView: View {
    let affection: Double
    var body: some View {
        let n = Affection.hearts(affection)
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < n ? "heart.fill" : "heart")
                    .foregroundStyle(i < n ? Color(rgb: 0xFF6A9A) : PixelPalette.dim.opacity(0.6))
            }
        }
        .font(.system(size: 9))
        .accessibilityElement()
        .accessibilityLabel("なつき度 \(Int(affection))")
        .help("なつき度 \(Int(affection))/100")
    }
}
