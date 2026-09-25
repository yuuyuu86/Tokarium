import AppKit
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case tank, care, shop, quests, dex, usage, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tank: return String(localized: "水槽")
        case .care: return String(localized: "お世話")
        case .shop: return String(localized: "お店")
        case .quests: return String(localized: "お題")
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
        case .quests: return "checklist"
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
    @State private var windowVisible = false

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
        .onChange(of: screen) { _, _ in
            selected = nil
            store.sfx(.click)
        }
        // BGM は水槽の窓が見えているときに流す
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        .onChange(of: windowVisible) { _, visible in SoundPlayer.shared.tankVisible = visible }
        .onDisappear { SoundPlayer.shared.tankVisible = false }
        .onChange(of: store.command) { _, command in
            guard let command else { return }
            store.command = nil
            switch command {
            case .show(let s): screen = s
            case .toggleEdit:
                screen = .tank
                editing.toggle()
            case .photo:
                screen = .tank
                if let url = Snapshot.take(store: store, size: windowSize) {
                    store.toast = String(localized: "写真を保存しました（ピクチャ/Tokarium）。クリップボードにも入れました")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
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
                case .quests: QuestScreen()
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
