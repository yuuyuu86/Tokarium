import AppKit
import SwiftUI

// MARK: - 上の表示

struct TopHUD: View {
    @Environment(GameStore.self) private var store
    let screen: Screen
    let hovered: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PixelBadge {
                Image(systemName: "drop.fill").foregroundStyle(Color(rgb: 0x6FC8FF))
                Text("水質：\(WaterCondition(store.state.tank.waterQuality).label)")
            }
            PixelBadge {
                Image(systemName: "fish.fill").foregroundStyle(Color(rgb: 0x6FC8FF))
                Text("\(store.livingFish.count)/\(store.state.tank.size.maxFish) 匹")
            }
            PixelBadge {
                Image(systemName: "leaf.fill").foregroundStyle(store.state.food <= Catalog.lowFood ? PixelPalette.danger : Color(rgb: 0xE8C060))
                Text("餌 \(store.state.food)")
            }
            .help("餌やり1回で1つ使います。お店で買えます")
            if let event = SeasonalEvents.active() {
                PixelBadge {
                    Image(systemName: event.symbol).foregroundStyle(PixelPalette.gold)
                    Text(event.name)
                }
                .help("期間限定の魚と装飾がお店に並んでいます（\(event.periodText)）")
            }
            Spacer(minLength: 10)
            if let f = store.state.tank.fish.first(where: { $0.id == hovered }) {
                FishHoverStatus(fish: f)
                    .transition(.opacity)
            }
            Spacer(minLength: 10)
            Button { store.command = .show(.quests) } label: {
                PixelBadge {
                    Text("Lv.\(store.state.rank)").foregroundStyle(PixelPalette.gold).monospacedDigit()
                    PixelBar(value: KeeperRank.progress(xp: store.state.xp) * 100, color: PixelPalette.gold).frame(width: 44)
                    if let title = store.titleText { Text("【\(title)】").lineLimit(1) }
                }
            }
            .buttonStyle(.plain)
            .help("飼育員ランク \(store.state.rank)（\(KeeperRank.title(store.state.rank))）。クリックでミッションの画面へ")
            .accessibilityLabel("飼育員ランク \(store.state.rank)")
            PixelBadge {
                Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(PixelPalette.gold)
                Text("\(store.coins)").monospacedDigit().foregroundStyle(PixelPalette.gold)
            }
            .help("AIを使うと増えます")
            .accessibilityLabel("コイン \(store.coins)")
            .tutorialAnchor("coins")
        }
        // 左上の信号ボタンをよける
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

/// カーソルを重ねた魚のステータス（上部に出す）。
struct FishHoverStatus: View {
    @Environment(GameStore.self) private var store
    let fish: Fish

    private var mood: String? { Ecology.mood(fish, in: store.state.tank) }

    var body: some View {
        HStack(spacing: 12) {
            FishIcon(fish: fish).frame(width: 40, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fish.name).font(.pixel(.callout)).lineLimit(1)
                    if fish.isAlive { HeartsView(affection: fish.affection) }
                }
                Text(subtitle).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim).lineLimit(1)
            }
            ConditionBadge(condition: fish.condition)
            if fish.isAlive {
                VStack(alignment: .leading, spacing: 4) {
                    miniBar(String(localized: "満腹"), fish.fullness)
                    miniBar(String(localized: "体調"), fish.health)
                }
                .frame(width: 130)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PixelFrame(fill: PixelPalette.deep.opacity(0.92), border: PixelPalette.sand, step: 2))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [fish.breedName, fish.stage.label, fish.personality.label]
        if fish.isAlive { parts.append(String(localized: "\(Int(fish.ageDays()))日齢")) }
        if fish.isElderly() { parts.append(String(localized: "老齢")) }
        if let mood { parts.append(mood) }
        return parts.joined(separator: String(localized: "・"))
    }

    private func miniBar(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim).frame(width: 34, alignment: .leading)
            PixelBar(value: value, color: value < 25 ? PixelPalette.danger : value < 50 ? Color(rgb: 0xFFA030) : Color(rgb: 0x5FD068))
                .frame(height: 10)
            Text("\(Int(value.rounded()))").font(.pixel(.caption2)).monospacedDigit().frame(width: 26, alignment: .trailing)
        }
    }
}

// MARK: - 水槽の上のお知らせ

struct TankOverlays: View {
    @Environment(GameStore.self) private var store
    @Binding var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let msg = store.resumeMessage {
                message(msg, symbol: "clock.arrow.circlepath", color: PixelPalette.sand) { store.resumeMessage = nil }
            }
            if !store.dangerFish.isEmpty {
                let names = store.dangerFish.map(\.name).joined(separator: String(localized: "、"))
                message(String(localized: "危険な状態の魚がいます：\(names)。餌やりと水換えをしてください。"),
                        symbol: "exclamationmark.triangle.fill", color: PixelPalette.danger, onClose: nil)
            }
            if let id = store.placingDecoration, let d = store.state.tank.decorations.first(where: { $0.id == id }) {
                HStack(spacing: 10) {
                    DecorationIcon(kindID: d.kindID).frame(width: 34, height: 26)
                    Text("\(d.kind.name)を置く場所をクリックしてください").font(.pixel(.callout))
                    Button(d.layer == 0 ? "手前へ" : "奥へ") { store.toggleDecorationLayer(id) }
                    Button("ここに置く") { store.finishPlacing() }.buttonStyle(.pixelProminent)
                    Button("持ち物にしまう") { store.cancelPlacing() }
                }
                .buttonStyle(.pixel)
                .pixelPanel(padding: 10)
                .frame(maxWidth: .infinity)
            } else if editing {
                Text("装飾をドラッグで移動・右クリックで奥/手前を変更")
                    .font(.pixel(.callout))
                    .pixelPanel(padding: 10)
                    .frame(maxWidth: .infinity)
                LayoutScorePanel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func message(_ text: String, symbol: String, color: Color, onClose: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.pixel(.callout)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.pixel).accessibilityLabel("閉じる")
            }
        }
        .pixelPanel(border: color, padding: 12)
        .frame(maxWidth: 640, alignment: .leading)
    }
}

// MARK: - 下の操作バー

struct BottomBar: View {
    @Environment(GameStore.self) private var store
    @Binding var screen: Screen
    @Binding var editing: Bool
    var tankSize: CGSize

    var body: some View {
        // 幅が足りないときは、文字を省いてアイコンだけにする
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            VStack(spacing: 0) {
                Rectangle().fill(PixelPalette.deeper).frame(height: 3)
                Rectangle().fill(PixelPalette.sand).frame(height: 3)
                Rectangle().fill(PixelPalette.deep.opacity(0.94))
            }
            .ignoresSafeArea()
        )
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Screen.allCases) { s in
                Button {
                    screen = s
                    if s != .tank { editing = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol)
                        if !compact { Text(s.title) }
                        if s == .care && !store.dangerFish.isEmpty {
                            Text("!").foregroundStyle(PixelPalette.danger)
                        }
                        if s == .quests && !store.state.claimableQuests().isEmpty {
                            Text("!").foregroundStyle(PixelPalette.gold)
                        }
                    }
                    .fixedSize()
                }
                .buttonStyle(PixelButtonStyle(prominent: screen == s))
                .tutorialAnchor(s.rawValue)
                .help(s.title)
                .accessibilityLabel(s.title)
                .accessibilityAddTraits(screen == s ? .isSelected : [])
            }
            Spacer(minLength: 12)
            Button { store.feed() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text(compact ? "\(store.state.food)" : String(localized: "餌をあげる（\(store.state.food)）"))
                }
                .fixedSize()
            }
            .buttonStyle(.pixel)
            .tutorialAnchor("feed")
            .disabled(!store.canFeed)
            .help(!store.canFeed ? "餌がありません。お店で買えます" : store.state.food == 0 ? "コインも餌もないので、今日の1回分は無料です" : "水槽の魚みんなに餌をあげます（餌を1つ使います）")
            .accessibilityLabel("餌をあげる")
            Button { store.changeWater() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "drop.triangle.fill")
                    if !compact { Text("水換え") }
                }
                .fixedSize()
            }
            .buttonStyle(.pixel)
            .tutorialAnchor("water")
            .help("水換え")
            .accessibilityLabel("水換え")
            if screen == .tank {
                Button { editing.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        if !compact { Text("配置を編集") }
                    }
                    .fixedSize()
                }
                .buttonStyle(PixelButtonStyle(prominent: editing))
                .help("配置を編集")
                .accessibilityLabel("配置を編集")
                Button {
                    if let url = Snapshot.take(store: store, size: tankSize) {
                        store.toast = String(localized: "写真を保存しました（ピクチャ/Tokarium）。クリップボードにも入れました")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: { Image(systemName: "camera.fill") }
                    .buttonStyle(.pixel)
                    .help("水槽の写真を撮る（操作パネルは写りません）")
                    .accessibilityLabel("写真を撮る")
            }
        }
    }
}

// MARK: - お知らせ

struct ToastView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let toast = store.toast {
            Text(toast)
                .font(.pixel(.callout))
                .pixelPanel(padding: 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { store.toast = nil }
                }
        }
    }
}

// MARK: - 魚の操作メニュー

/// 魚をクリックしたときに出る操作。ステータスはカーソルを重ねたときに上に出る。
struct FishActionMenu: View {
    @Environment(GameStore.self) private var store
    let fish: Fish
    let onClose: () -> Void
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmFarewell = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FishIcon(fish: fish).frame(width: 34, height: 22)
                Text(fish.name).font(.pixel(.callout)).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.pixel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("閉じる")
            }
            if fish.isAlive {
                action("餌をあげる（残り \(store.state.food)）", "leaf.fill") { store.feed(fish: fish.id) }
                    .disabled(!store.canFeed)
                if fish.isSick {
                    action("薬をあげる（残り \(store.state.medicine)）", "cross.case.fill") { store.giveMedicine(fish.id) }
                        .disabled(store.state.medicine == 0)
                        .help(store.state.medicine == 0 ? "お店で薬を買えます" : "薬を1つ使って病気を治します")
                }
            } else {
                action("お別れする", "hand.wave.fill") { confirmFarewell = true }
            }
            action(fish.isFavorite ? "お気に入りを外す" : "お気に入り（主役）にする", fish.isFavorite ? "heart.slash.fill" : "heart.fill") {
                store.toggleFavorite(fish.id)
            }
            action("名前を変える", "pencil") {
                newName = fish.name
                renaming = true
            }
        }
        .buttonStyle(.pixel)
        .pixelPanel(padding: 12)
        .alert("名前を変える", isPresented: $renaming) {
            TextField("名前", text: $newName)
            Button("変更") { store.rename(fish.id, to: newName) }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("\(fish.name)とお別れしますか？", isPresented: $confirmFarewell) {
            Button("お別れする", role: .destructive) {
                store.farewell(fish.id)
                onClose()
            }
        } message: {
            Text("水槽から取り出します。元には戻せません。")
        }
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// シートもドット絵の見た目にそろえる。
struct PixelSheet: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.pixel(.body))
            .foregroundStyle(PixelPalette.text)
            .buttonStyle(.pixel)
            .tint(PixelPalette.gold)
            .background(PixelFrame(fill: PixelPalette.deep, border: PixelPalette.sand))
            .preferredColorScheme(.dark)
    }
}

// MARK: - レイアウトの評価

/// 配置を編集しているあいだに出す、レイアウトの点数。
struct LayoutScorePanel: View {
    @Environment(GameStore.self) private var store
    @State private var expanded = false

    var body: some View {
        let score = store.layoutScore
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Text("レイアウト評価").font(.pixel(.callout))
                    Text("\(score.total)点").font(.pixel(.title3)).foregroundStyle(PixelPalette.gold).monospacedDigit()
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < score.stars ? "star.fill" : "star")
                                .foregroundStyle(i < score.stars ? PixelPalette.gold : PixelPalette.dim)
                        }
                    }
                    .font(.system(size: 10))
                    Text(score.rankText).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    Text("自己ベスト \(store.state.bestLayoutScore)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(PixelPalette.dim)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("レイアウト評価 \(score.total)点")
            if expanded {
                ForEach(score.parts, id: \.title) { p in
                    HStack {
                        Text(p.title).font(.pixel(.caption)).frame(width: 90, alignment: .leading)
                        PixelBar(value: Double(p.points) / Double(max(1, p.max)) * 100, color: Color(rgb: 0x5FD068)).frame(width: 120)
                        Text("\(p.points)/\(p.max)").font(.pixel(.caption)).monospacedDigit().foregroundStyle(PixelPalette.dim)
                    }
                }
                ForEach(score.bonuses, id: \.title) { b in
                    Label("\(b.title) +\(b.points)（\(b.detail)）", systemImage: "sparkles")
                        .font(.pixel(.caption)).foregroundStyle(PixelPalette.gold)
                }
                ForEach(score.tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                Text("組み合わせのボーナス: \(Layout.combos.map(\.title).joined(separator: String(localized: "、")))")
                    .font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
            }
        }
        .pixelPanel(padding: 10)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}
