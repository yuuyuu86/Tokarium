import SwiftUI

/// 水槽の表示。ウィンドウとデスクトップの両方で使う。
struct AquariumView: View {
    let store: GameStore
    var interactive = false
    @Binding var selectedFish: UUID?
    @Binding var editingLayout: Bool

    init(store: GameStore, interactive: Bool = false, selectedFish: Binding<UUID?> = .constant(nil), editingLayout: Binding<Bool> = .constant(false)) {
        self.store = store
        self.interactive = interactive
        self._selectedFish = selectedFish
        self._editingLayout = editingLayout
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let tank = store.state.tank
            let style = store.style
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    style.drawBackground(&ctx, size: size, tank: tank)
                }
                TimelineView(.animation(minimumInterval: 1.0 / Double(max(5, store.settings.fps)))) { timeline in
                    Canvas { ctx, size in
                        store.engine.aspect = size.height > 0 ? size.width / size.height : 1.6
                        store.engine.step(to: timeline.date, fish: tank.fish, decorations: tank.decorations)
                        style.drawLive(&ctx, size: size, tank: tank, engine: store.engine, selected: interactive ? selectedFish : nil)
                    }
                }
                if interactive && editingLayout {
                    layoutHandles(size: size, tank: tank, style: style)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                guard interactive, !editingLayout else { return }
                selectedFish = hitFish(at: point, size: size, tank: tank, style: style)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func hitFish(at point: CGPoint, size: CGSize, tank: Tank, style: AquariumStyle) -> UUID? {
        tank.fish.reversed().first { f in
            style.fishFrame(f, tank: tank, engine: store.engine, size: size)?.insetBy(dx: -8, dy: -8).contains(point) ?? false
        }?.id
    }

    @ViewBuilder
    private func layoutHandles(size: CGSize, tank: Tank, style: AquariumStyle) -> some View {
        ForEach(tank.decorations.filter(\.isPlaced)) { d in
            let frame = style.decorationFrame(d, tank: tank, size: size)
            DecorationHandle(frame: frame, name: d.kind.name, isFront: d.layer == 1,
                             onMove: { dx in store.moveDecoration(d.id, x: d.x + dx / size.width) },
                             onEnd: { store.save() },
                             onLayer: { store.toggleDecorationLayer(d.id) },
                             onStore: { store.setDecoration(d.id, placed: false) })
        }
    }

    private var accessibilitySummary: String {
        let fish = store.state.tank.fish
        let alive = fish.filter(\.isAlive).count
        let danger = fish.filter { $0.condition.isDanger }.count
        var s = String(localized: "水槽。魚 \(alive) 匹。水質は\(WaterCondition(store.state.tank.waterQuality).label)。")
        if danger > 0 { s += String(localized: "危険な状態の魚が \(danger) 匹います。") }
        return s
    }
}

private struct DecorationHandle: View {
    let frame: CGRect
    let name: String
    let isFront: Bool
    let onMove: (Double) -> Void
    let onEnd: () -> Void
    let onLayer: () -> Void
    let onStore: () -> Void
    @State private var lastX: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.08))
            .frame(width: max(24, frame.width), height: max(24, frame.height))
            .position(x: frame.midX, y: frame.midY)
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    onMove(v.translation.width - lastX)
                    lastX = v.translation.width
                }
                .onEnded { _ in lastX = 0; onEnd() })
            .contextMenu {
                Button(isFront ? "奥へ移動" : "手前へ移動", action: onLayer)
                Button("持ち物にしまう", action: onStore)
            }
            .help("\(name)：ドラッグで移動、右クリックで奥/手前・しまう")
    }
}
