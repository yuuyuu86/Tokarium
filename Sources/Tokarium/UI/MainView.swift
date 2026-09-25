import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case tank, care, shop, dex, usage, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tank: return String(localized: "水槽")
        case .care: return String(localized: "お世話")
        case .shop: return String(localized: "お店")
        case .dex: return String(localized: "図鑑")
        case .usage: return String(localized: "AI利用量")
        case .settings: return String(localized: "設定")
        }
    }
    var symbol: String {
        switch self {
        case .tank: return "fish.fill"
        case .care: return "heart.fill"
        case .shop: return "cart.fill"
        case .dex: return "book.fill"
        case .usage: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// 水槽を窓いっぱいに出し、その上にドット絵の操作パネルを重ねる。
struct MainView: View {
    @Environment(GameStore.self) private var store
    @State private var screen: Screen = .tank
    @State private var selected: UUID?
    @State private var selectedPoint: CGPoint?
    @State private var hovered: UUID?
    @State private var editing = false
    @State private var windowSize = CGSize(width: 1080, height: 700)
    @State private var tutorialStep = 0

    var body: some View {
        ZStack {
            PixelPalette.deeper.ignoresSafeArea()
            AquariumView(store: store, interactive: screen == .tank, selectedFish: $selected, editingLayout: $editing,
                         hoveredFish: $hovered, selectedPoint: $selectedPoint)
                .overlay { fishMenu }
                .ignoresSafeArea()

            if screen != .tank {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { screen = .tank }
                panel
                    .padding(.top, 58)
                    .padding(.bottom, 72)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            VStack(spacing: 0) {
                TopHUD(screen: screen, hovered: screen == .tank ? hovered : nil)
                if screen == .tank { TankOverlays(editing: $editing) }
                Spacer(minLength: 0)
                BottomBar(screen: $screen, editing: $editing, tankSize: windowSize)
            }
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { windowSize = geo.size }.onChange(of: geo.size) { _, new in windowSize = new }
        }.ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: screen)
        .onChange(of: screen) { _, _ in selected = nil }
        .onChange(of: editing) { _, now in
            if now { selected = nil } else if store.placingDecoration != nil { store.finishPlacing() }
        }
        // 装飾を買ったら水槽に戻り、置き場所を決めてもらう
        .onChange(of: store.placingDecoration) { _, id in
            if id != nil {
                screen = .tank
                editing = true
            }
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 72) }
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if showTutorial {
                TutorialOverlay(anchors: anchors, step: $tutorialStep) {
                    store.settings.tutorialDone = true
                    tutorialStep = 0
                }
            }
        }
        .font(.pixel(.body))
        .foregroundStyle(PixelPalette.text)
        .tint(PixelPalette.gold)
        .groupBoxStyle(PixelGroupBoxStyle())
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(get: { !store.settings.onboarded }, set: { _ in })) {
            OnboardingView().interactiveDismissDisabled().modifier(PixelSheet())
        }
        .sheet(item: Binding(get: { store.settings.onboarded ? store.bugReport : nil }, set: { store.bugReport = $0 })) { req in
            BugReportView(crash: req.crash).modifier(PixelSheet())
        }
        .sheet(isPresented: Binding(get: { store.showAbout && store.settings.onboarded }, set: { store.showAbout = $0 })) {
            AboutView().modifier(PixelSheet())
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var showTutorial: Bool {
        store.settings.onboarded && !store.settings.tutorialDone && screen == .tank && store.bugReport == nil
    }

    /// クリックした魚の操作メニュー。クリックした場所の近くに出す。
    @ViewBuilder
    private var fishMenu: some View {
        GeometryReader { geo in
            if screen == .tank, let f = store.state.tank.fish.first(where: { $0.id == selected }), let p = selectedPoint {
                let w: CGFloat = 230, h: CGFloat = 250
                // 画面からはみ出さないように、右に出せなければ左に出す
                let x = p.x + 24 + w <= geo.size.width - 12 ? p.x + 24 + w / 2 : max(w / 2 + 12, p.x - 24 - w / 2)
                let y = min(max(p.y, h / 2 + 70), geo.size.height - h / 2 - 80)
                FishActionMenu(fish: f) { selected = nil }
                    .frame(width: w)
                    .position(x: x, y: y)
                    .transition(.opacity)
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: screen.symbol).foregroundStyle(PixelPalette.gold)
                Text(screen.title).font(.pixel(.title2)).foregroundStyle(PixelPalette.sand)
                Spacer()
                Button { screen = .tank } label: { Image(systemName: "xmark") }
                    .buttonStyle(.pixel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("閉じる")
            }
            .padding(.bottom, 10)
            Group {
                switch screen {
                case .tank: EmptyView()
                case .care: CareScreen()
                case .shop: ShopScreen()
                case .dex: DexScreen()
                case .usage: UsageScreen()
                case .settings: SettingsScreen()
                }
            }
            .scrollContentBackground(.hidden)
            .buttonStyle(.pixel)
            .toggleStyle(.pixel)
        }
        .pixelPanel()
        .frame(maxWidth: 1100, maxHeight: .infinity)
    }
}

// MARK: - 上の表示

private struct TopHUD: View {
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
private struct FishHoverStatus: View {
    @Environment(GameStore.self) private var store
    let fish: Fish

    private var mood: String? { Ecology.mood(fish, in: store.state.tank) }

    var body: some View {
        HStack(spacing: 12) {
            FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive, shiny: fish.isShiny).frame(width: 40, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(fish.name).font(.pixel(.callout)).lineLimit(1)
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
        var parts = [fish.species.name, fish.stage.label]
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

private struct TankOverlays: View {
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

private struct BottomBar: View {
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

private struct ToastView: View {
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
private struct FishActionMenu: View {
    @Environment(GameStore.self) private var store
    let fish: Fish
    let onClose: () -> Void
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmFarewell = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive, shiny: fish.isShiny).frame(width: 34, height: 22)
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
private struct PixelSheet: ViewModifier {
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
