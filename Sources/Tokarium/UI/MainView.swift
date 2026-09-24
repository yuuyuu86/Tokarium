import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case tank, care, shop, usage, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tank: return String(localized: "水槽")
        case .care: return String(localized: "お世話")
        case .shop: return String(localized: "お店")
        case .usage: return String(localized: "AI利用量")
        case .settings: return String(localized: "設定")
        }
    }
    var symbol: String {
        switch self {
        case .tank: return "fish.fill"
        case .care: return "heart.fill"
        case .shop: return "cart.fill"
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
    @State private var editing = false

    var body: some View {
        ZStack {
            PixelPalette.deeper.ignoresSafeArea()
            AquariumView(store: store, interactive: screen == .tank, selectedFish: $selected, editingLayout: $editing)
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
                TopHUD(screen: screen)
                if screen == .tank { TankOverlays(selected: $selected, editing: $editing) }
                Spacer(minLength: 0)
                BottomBar(screen: $screen, editing: $editing)
            }
        }
        .animation(.easeOut(duration: 0.15), value: screen)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 72) }
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
        .frame(minWidth: 820, minHeight: 560)
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

    var body: some View {
        HStack(spacing: 10) {
            PixelBadge {
                Image(systemName: "drop.fill").foregroundStyle(Color(rgb: 0x6FC8FF))
                Text("水質：\(WaterCondition(store.state.tank.waterQuality).label)")
            }
            PixelBadge {
                Image(systemName: "fish.fill").foregroundStyle(Color(rgb: 0x6FC8FF))
                Text("\(store.livingFish.count)/\(store.state.tank.size.maxFish) 匹")
            }
            Spacer()
            PixelBadge {
                Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(PixelPalette.gold)
                Text("\(store.coins)").monospacedDigit().foregroundStyle(PixelPalette.gold)
            }
            .help("AIを使うと増えます")
            .accessibilityLabel("コイン \(store.coins)")
        }
        // 左上の信号ボタンをよける
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .padding(.top, 12)
    }
}

// MARK: - 水槽の上のお知らせ

private struct TankOverlays: View {
    @Environment(GameStore.self) private var store
    @Binding var selected: UUID?
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
            HStack(alignment: .top) {
                Spacer()
                if let f = store.state.tank.fish.first(where: { $0.id == selected }) {
                    FishCard(fish: f) { selected = nil }
                }
            }
            if editing {
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Screen.allCases) { s in
                Button {
                    screen = s
                    if s != .tank { editing = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol)
                        Text(s.title)
                        if s == .care && !store.dangerFish.isEmpty {
                            Text("!").foregroundStyle(PixelPalette.danger)
                        }
                    }
                }
                .buttonStyle(PixelButtonStyle(prominent: screen == s))
                .accessibilityAddTraits(screen == s ? .isSelected : [])
            }
            Spacer(minLength: 12)
            Button { store.feed() } label: { Label("餌をあげる", systemImage: "leaf.fill") }
                .buttonStyle(.pixel)
            Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle.fill") }
                .buttonStyle(.pixel)
            if screen == .tank {
                Button { editing.toggle() } label: { Label("配置を編集", systemImage: "square.and.pencil") }
                    .buttonStyle(PixelButtonStyle(prominent: editing))
            }
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

// MARK: - 魚の札

private struct FishCard: View {
    let fish: Fish
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive).frame(width: 40, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fish.name).font(.pixel(.headline))
                    Text(subtitle).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.pixel).accessibilityLabel("閉じる")
            }
            ConditionBadge(condition: fish.condition)
            if fish.isAlive {
                StatBar(title: String(localized: "満腹"), value: fish.fullness, word: fish.fullness < Simulation.hungryThreshold ? String(localized: "空腹") : String(localized: "十分"))
                StatBar(title: String(localized: "体調"), value: fish.health, word: fish.condition.label)
            }
        }
        .frame(width: 250)
        .pixelPanel(padding: 14)
    }

    private var subtitle: String {
        var parts = [fish.species.name, fish.stage.label]
        if fish.isElderly() { parts.append(String(localized: "老齢")) }
        return parts.joined(separator: String(localized: "・"))
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
