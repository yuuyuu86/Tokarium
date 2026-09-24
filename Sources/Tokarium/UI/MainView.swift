import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case tank, care, shop, usage, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tank: return "水槽"
        case .care: return "お世話"
        case .shop: return "お店"
        case .usage: return "AI利用量"
        case .settings: return "設定"
        }
    }
    var symbol: String {
        switch self {
        case .tank: return "fish"
        case .care: return "heart.text.square"
        case .shop: return "cart"
        case .usage: return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @Environment(GameStore.self) private var store
    @State private var screen: Screen? = .tank

    var body: some View {
        NavigationSplitView {
            List(Screen.allCases, selection: $screen) { s in
                Label(s.title, systemImage: s.symbol)
                    .badge(s == .care ? store.dangerFish.count : 0)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    CoinLabel(coins: store.coins).font(.title3)
                    Text("AIを使うと増えます").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            Group {
                switch screen ?? .tank {
                case .tank: TankScreen()
                case .care: CareScreen()
                case .shop: ShopScreen()
                case .usage: UsageScreen()
                case .settings: SettingsScreen()
                }
            }
            .navigationTitle((screen ?? .tank).title)
        }
        .overlay(alignment: .bottom) { ToastView() }
        .sheet(isPresented: Binding(get: { !store.settings.onboarded }, set: { _ in })) {
            OnboardingView().interactiveDismissDisabled()
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

private struct ToastView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let toast = store.toast {
            Text(toast)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { store.toast = nil }
                }
        }
    }
}

// MARK: - 水槽

struct TankScreen: View {
    @Environment(GameStore.self) private var store
    @State private var selected: UUID?
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            if let msg = store.resumeMessage {
                banner(msg, symbol: "clock.arrow.circlepath", color: .blue) { store.resumeMessage = nil }
            }
            if !store.dangerFish.isEmpty {
                banner("危険な状態の魚がいます：\(store.dangerFish.map(\.name).joined(separator: "、"))。餌やりと水換えをしてください。",
                       symbol: "exclamationmark.triangle.fill", color: .red, onClose: nil)
            }
            ZStack(alignment: .topLeading) {
                AquariumView(store: store, interactive: true, selectedFish: $selected, editingLayout: $editing)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 8) {
                    Label("水質：\(WaterCondition(store.state.tank.waterQuality).label)", systemImage: "drop")
                    Text("・")
                    Label("\(store.livingFish.count)/\(store.state.tank.size.maxFish) 匹", systemImage: "fish")
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
                if let f = store.state.tank.fish.first(where: { $0.id == selected }) {
                    FishCard(fish: f) { selected = nil }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(10)
                }
                if editing {
                    Text("装飾をドラッグで移動・右クリックで奥/手前を変更")
                        .font(.caption)
                        .padding(8).background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(10)
                }
            }
            .padding(12)
            HStack {
                Button { store.feed() } label: { Label("餌をあげる", systemImage: "leaf") }
                Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle") }
                Spacer()
                Toggle(isOn: $editing) { Label("配置を編集", systemImage: "square.and.pencil") }
                    .toggleStyle(.button)
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], 12)
        }
    }

    private func banner(_ text: String, symbol: String, color: Color, onClose: (() -> Void)?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("閉じる")
            }
        }
        .padding(10)
        .background(color.opacity(0.12))
    }
}

private struct FishCard: View {
    let fish: Fish
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FishIcon(speciesID: fish.speciesID, dead: !fish.isAlive).frame(width: 36, height: 24)
                VStack(alignment: .leading) {
                    Text(fish.name).font(.headline)
                    Text("\(fish.species.name)・\(fish.stage.label)\(fish.isElderly() ? "・老齢" : "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("閉じる")
            }
            ConditionBadge(condition: fish.condition)
            if fish.isAlive {
                StatBar(title: "満腹", value: fish.fullness, word: fish.fullness < Simulation.hungryThreshold ? "空腹" : "十分")
                StatBar(title: "体調", value: fish.health, word: fish.condition.label)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
