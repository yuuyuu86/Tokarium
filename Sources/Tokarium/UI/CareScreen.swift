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
                                .disabled(!store.canFeed)
                            Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle") }
                        }
                        .controlSize(.large)
                        Label("持っている餌: \(store.state.food) 回分　／　薬: \(store.state.medicine) 個", systemImage: "leaf")
                            .font(.pixel(.callout))
                        Text(careHint).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        let factor = Ecology.waterDecayFactor(store.state.tank)
                        if factor < 1 {
                            Label("掃除役のおかげで、水の汚れる速さが \(Int(((1 - factor) * 100).rounded()))% 下がっています",
                                  systemImage: "sparkles").font(.pixel(.caption)).foregroundStyle(Color(rgb: 0x5FD068))
                        }
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
            FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive, shiny: fish.isShiny)
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
                    Button { store.toggleFavorite(fish.id) } label: {
                        Image(systemName: fish.isFavorite ? "heart.fill" : "heart").foregroundStyle(Color(rgb: 0xFF6A9A))
                    }
                    .help(fish.isFavorite ? "お気に入りを外す" : "お気に入り（主役）にする")
                    .accessibilityLabel(fish.isFavorite ? "お気に入りを外す" : "お気に入り（主役）にする")
                    if fish.isSick && fish.isAlive {
                        Button { store.giveMedicine(fish.id) } label: { Label("薬をあげる", systemImage: "cross.case") }
                            .disabled(store.state.medicine == 0)
                            .help(store.state.medicine == 0 ? "お店で薬を買えます" : "薬を1つ使って病気を治します")
                    }
                    ConditionBadge(condition: fish.condition)
                }
                Text(lifeText).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                if let mood = Ecology.mood(fish, in: store.state.tank) {
                    Text(mood).font(.pixel(.caption))
                        .foregroundStyle(mood.contains(String(localized: "ストレス")) ? Color(rgb: 0xFFA030) : Color(rgb: 0x5FD068))
                }
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
