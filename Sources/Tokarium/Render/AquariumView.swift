import Combine
import SwiftUI

/// 水槽の表示。ウィンドウとデスクトップの両方で使う。
struct AquariumView: View {
    let store: GameStore
    var interactive = false
    @Binding var selectedFish: UUID?
    @Binding var editingLayout: Bool
    /// カーソルが重なっている魚。
    @Binding var hoveredFish: UUID?
    /// 魚をクリックした場所（操作メニューを出す位置）。
    @Binding var selectedPoint: CGPoint?
    @State private var hoverPoint: CGPoint?
    /// 窓が完全に隠れているときは動かさない（省電力）。
    @State private var windowVisible = true

    /// 魚は泳いで動くので、カーソルが止まっていても定期的に判定し直す。
    private let hoverTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    init(store: GameStore, interactive: Bool = false, selectedFish: Binding<UUID?> = .constant(nil),
         editingLayout: Binding<Bool> = .constant(false), hoveredFish: Binding<UUID?> = .constant(nil),
         selectedPoint: Binding<CGPoint?> = .constant(nil)) {
        self.store = store
        self.interactive = interactive
        self._selectedFish = selectedFish
        self._editingLayout = editingLayout
        self._hoveredFish = hoveredFish
        self._selectedPoint = selectedPoint
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
                TimelineView(.animation(minimumInterval: 1.0 / Double(max(5, store.effectiveFPS)),
                                        paused: store.settings.autoPowerSaving && !windowVisible)) { timeline in
                    Canvas { ctx, size in
                        let ambient = store.settings.timeOfDay ? Ambient.at(timeline.date) : .day
                        store.engine.aspect = size.height > 0 ? size.width / size.height : 1.6
                        store.engine.speedFactor = ambient.speed
                        store.engine.season = store.settings.seasons ? .forSeason(timeline.date) : nil
                        store.engine.step(to: timeline.date, fish: tank.fish, decorations: tank.decorations)
                        style.drawLive(&ctx, size: size, tank: tank, engine: store.engine,
                                       selected: interactive ? (hoveredFish ?? selectedFish) : nil,
                                       treasureX: store.state.treasureX, ambient: ambient)
                    }
                }
                if interactive && editingLayout && store.placingDecoration == nil {
                    layoutHandles(size: size, tank: tank, style: style)
                }
            }
            .background(WindowVisibilityReader(isVisible: $windowVisible))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                guard interactive else { return }
                // 置き場所を決めている最中なら、クリックした場所に置く
                if store.placingDecoration != nil {
                    placeDecoration(at: point, size: size)
                    store.finishPlacing()
                    return
                }
                guard !editingLayout else { return }
                // 宝箱 → 魚 → 水（たたくと魚が寄ってくる）の順に調べる
                if let tx = store.state.treasureX,
                   style.treasureFrame(x: tx, tank: tank, engine: store.engine, size: size).insetBy(dx: -8, dy: -8).contains(point) {
                    store.openTreasure()
                    return
                }
                selectedFish = hitFish(at: point, size: size, tank: tank, style: style)
                selectedPoint = selectedFish == nil ? nil : point
                if selectedFish == nil, size.width > 0, size.height > 0 {
                    store.touchWater(x: point.x / size.width, y: point.y / size.height)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard interactive else { return }
                switch phase {
                case .active(let point):
                    hoverPoint = point
                    if store.placingDecoration != nil { placeDecoration(at: point, size: size) }
                    updateHover(size: size, tank: tank, style: style)
                case .ended:
                    hoverPoint = nil
                    if hoveredFish != nil { hoveredFish = nil }
                }
            }
            .onReceive(hoverTimer) { _ in
                guard interactive, hoverPoint != nil else { return }
                updateHover(size: size, tank: tank, style: style)
            }
            .onChange(of: interactive) { _, now in
                if !now { hoverPoint = nil; hoveredFish = nil }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// 置き場所を決めている装飾をカーソルの横位置へ動かす。
    private func placeDecoration(at point: CGPoint, size: CGSize) {
        guard let id = store.placingDecoration, size.width > 0 else { return }
        store.moveDecoration(id, x: point.x / size.width)
    }

    private func updateHover(size: CGSize, tank: Tank, style: AquariumStyle) {
        let hit = editingLayout || store.placingDecoration != nil ? nil : hoverPoint.flatMap { hitFish(at: $0, size: size, tank: tank, style: style) }
        if hit != hoveredFish { hoveredFish = hit }
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
