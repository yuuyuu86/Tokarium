import SwiftUI

/// 表現スタイル。後から画風を追加できるように描画をここへ集める。
protocol AquariumStyle {
    var id: String { get }
    var name: String { get }
    func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank)
    func drawLive(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank, engine: SwimEngine, selected: UUID?)
    /// 装飾の画面上の枠（配置編集の当たり判定用）。
    func decorationFrame(_ d: Decoration, tank: Tank, size: CGSize) -> CGRect
    func fishFrame(_ f: Fish, tank: Tank, engine: SwimEngine, size: CGSize) -> CGRect?
}

enum AquariumStyles {
    static let all: [AquariumStyle] = [PixelArtStyle()]
    static func style(_ id: String) -> AquariumStyle { all.first { $0.id == id } ?? all[0] }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}

/// 最初の画風: ドット絵。
struct PixelArtStyle: AquariumStyle {
    let id = "pixel"
    let name = "ドット絵"

    /// 1ドットの画面上の大きさ。水槽を大きくすると、同じ画面により多くのドットが入る。
    func dot(_ size: CGSize, level: Int = 0) -> CGFloat {
        max(2, floor(min(size.width, size.height) / (150 + 25 * CGFloat(level))))
    }

    /// 魚の1ドットの大きさ。成長に合わせて大きくなる（整数ピクセルでくっきり描く）。
    func fishDot(_ f: Fish, p: CGFloat) -> CGFloat {
        max(1, (p * (1 + 0.7 * CGFloat(f.growth))).rounded())
    }

    // MARK: 背景（水・砂・装飾）

    func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank) {
        let p = dot(size, level: tank.level)
        let cols = Int(ceil(size.width / p)), rows = Int(ceil(size.height / p))
        let sandRow = Int(Double(rows) * SwimEngine.sandTop)

        // 水のグラデーション（段階的な色＋境目のディザ）
        let bands: [UInt32] = [0x4FB6E6, 0x3FA3D8, 0x3190C8, 0x2680B8, 0x1D6EA6, 0x165D93, 0x114E82, 0x0D4172]
        let bandHeight = max(1, sandRow / bands.count)
        for (i, c) in bands.enumerated() {
            let top = i * bandHeight
            let h = i == bands.count - 1 ? sandRow - top : bandHeight
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(top) * p, width: size.width, height: CGFloat(h) * p)), with: .color(Color(rgb: c)))
            if i > 0 {
                var dither = Path()
                for x in stride(from: 0, to: cols, by: 2) {
                    dither.addRect(CGRect(x: CGFloat(x) * p, y: CGFloat(top) * p, width: p, height: p))
                }
                ctx.fill(dither, with: .color(Color(rgb: bands[i - 1])))
            }
        }

        // 光の筋
        for i in 0..<4 {
            let x0 = size.width * (0.12 + 0.24 * Double(i))
            var ray = Path()
            ray.move(to: CGPoint(x: x0, y: 0))
            ray.addLine(to: CGPoint(x: x0 + p * 10, y: 0))
            ray.addLine(to: CGPoint(x: x0 - size.width * 0.08 + p * 24, y: CGFloat(sandRow) * p))
            ray.addLine(to: CGPoint(x: x0 - size.width * 0.08, y: CGFloat(sandRow) * p))
            ray.closeSubpath()
            ctx.fill(ray, with: .color(.white.opacity(0.05)))
        }

        // 奥の岩のシルエット
        var rng = SeededRandom(seed: 7)
        var hills = Path()
        var x = 0
        while x < cols {
            let w = Int.random(in: 6...18, using: &rng)
            let h = Int.random(in: 2...9, using: &rng)
            hills.addRect(CGRect(x: CGFloat(x) * p, y: CGFloat(sandRow - h) * p, width: CGFloat(w) * p, height: CGFloat(h) * p))
            hills.addRect(CGRect(x: CGFloat(x + 1) * p, y: CGFloat(sandRow - h - 1) * p, width: CGFloat(max(1, w - 2)) * p, height: p))
            x += w + Int.random(in: 0...10, using: &rng)
        }
        ctx.fill(hills, with: .color(Color(rgb: 0x0A3560)))

        // 砂
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(sandRow) * p, width: size.width, height: size.height - CGFloat(sandRow) * p)),
                 with: .color(Color(rgb: 0xD9BE84)))
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(sandRow) * p, width: size.width, height: p)), with: .color(Color(rgb: 0xEAD5A0)))
        var dark = Path(), light = Path()
        for _ in 0..<(cols * (rows - sandRow) / 9) {
            let sx = Int.random(in: 0..<cols, using: &rng), sy = Int.random(in: (sandRow + 1)..<max(sandRow + 2, rows), using: &rng)
            let r = CGRect(x: CGFloat(sx) * p, y: CGFloat(sy) * p, width: p, height: p)
            if Bool.random(using: &rng) { dark.addRect(r) } else { light.addRect(r) }
        }
        ctx.fill(dark, with: .color(Color(rgb: 0xB89A62)))
        ctx.fill(light, with: .color(Color(rgb: 0xF0DCAA)))

        // 装飾（奥 → 手前）
        for d in tank.decorations.filter(\.isPlaced).sorted(by: { ($0.layer, $0.x) < ($1.layer, $1.x) }) {
            guard let sprite = SpriteLibrary.decorations[d.kindID],
                  let img = SpriteLibrary.image(for: sprite, key: "deco-\(d.kindID)") else { continue }
            ctx.draw(Image(decorative: img, scale: 1).interpolation(.none), in: decorationFrame(d, tank: tank, size: size))
        }

        // 水のにごり
        let murk = max(0, 1 - tank.waterQuality / 100)
        if murk > 0.05 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x5A6B2A, opacity: murk * 0.45)))
        }
    }

    func decorationFrame(_ d: Decoration, tank: Tank, size: CGSize) -> CGRect {
        let p = dot(size, level: tank.level)
        guard let sprite = SpriteLibrary.decorations[d.kindID] else { return .zero }
        let w = CGFloat(sprite.width * sprite.scale) * p, h = CGFloat(sprite.height * sprite.scale) * p
        let rows = Int(ceil(size.height / p))
        let baseRow = Int(Double(rows) * SwimEngine.sandTop) + (d.layer == 0 ? 2 : 5)
        let cx = (CGFloat(d.x) * size.width / p).rounded() * p
        return CGRect(x: cx - (w / 2 / p).rounded() * p, y: CGFloat(baseRow) * p - h, width: w, height: h)
    }

    // MARK: 動くもの（魚・餌・泡・水面）

    func fishFrame(_ f: Fish, tank: Tank, engine: SwimEngine, size: CGSize) -> CGRect? {
        guard let s = engine.swimmers[f.id], let sprite = SpriteLibrary.fish[f.speciesID] else { return nil }
        let p = dot(size, level: tank.level)
        let fp = fishDot(f, p: p)
        let w = CGFloat(sprite.width) * fp, h = CGFloat(sprite.height) * fp
        let bob = f.isAlive ? (sin(s.phase * 0.5) * 0.6).rounded() * p : 0
        let x = (CGFloat(s.x) * size.width / p).rounded() * p - (w / 2 / p).rounded() * p
        let y = (CGFloat(s.y) * size.height / p).rounded() * p - (h / 2 / p).rounded() * p + bob
        return CGRect(x: x, y: y, width: w, height: h)
    }

    func drawLive(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank, engine: SwimEngine, selected: UUID?) {
        let p = dot(size, level: tank.level)

        // 水面のゆらめき
        var shimmer = Path()
        let cols = Int(ceil(size.width / p))
        for x in stride(from: 0, to: cols, by: 1) where (x + Int(engine.time * 6)) % 7 < 3 {
            shimmer.addRect(CGRect(x: CGFloat(x) * p, y: 0, width: p, height: p))
        }
        ctx.fill(shimmer, with: .color(.white.opacity(0.35)))

        // 泡
        var bubbles = Path()
        for b in engine.bubbles {
            let bx = ((CGFloat(b.x) * size.width + CGFloat(sin(engine.time * 3 + b.wobble)) * p) / p).rounded() * p
            let by = (CGFloat(b.y) * size.height / p).rounded() * p
            bubbles.addRect(CGRect(x: bx, y: by - p, width: p, height: p))
            bubbles.addRect(CGRect(x: bx - p, y: by, width: p, height: p))
            bubbles.addRect(CGRect(x: bx + p, y: by, width: p, height: p))
            bubbles.addRect(CGRect(x: bx, y: by + p, width: p, height: p))
        }
        ctx.fill(bubbles, with: .color(.white.opacity(0.55)))

        // 餌
        var food = Path()
        for pellet in engine.pellets where pellet.y > 0 {
            let fx = (CGFloat(pellet.x) * size.width / p).rounded() * p
            let fy = (CGFloat(pellet.y) * size.height / p).rounded() * p
            food.addRect(CGRect(x: fx, y: fy, width: p, height: p))
        }
        ctx.fill(food, with: .color(Color(rgb: 0x8B4A1C)))

        // 魚（死んだ魚を奥に）
        for f in tank.fish.sorted(by: { ($0.isAlive ? 1 : 0) < ($1.isAlive ? 1 : 0) }) {
            guard let sprite = SpriteLibrary.fish[f.speciesID], let s = engine.swimmers[f.id],
                  let rect = fishFrame(f, tank: tank, engine: engine, size: size) else { continue }
            let frame = f.isAlive && Int(s.phase) % 2 == 1 ? 1 : 0
            guard let img = SpriteLibrary.image(for: sprite, key: "fish-\(f.speciesID)", frame: frame, dead: !f.isAlive) else { continue }
            var layer = ctx
            if !s.facingRight {
                layer.translateBy(x: rect.midX, y: 0)
                layer.scaleBy(x: -1, y: 1)
                layer.translateBy(x: -rect.midX, y: 0)
            }
            layer.draw(Image(decorative: img, scale: 1).interpolation(.none), in: rect)

            if f.id == selected {
                drawPixelFrame(&ctx, rect.insetBy(dx: -p * 2, dy: -p * 2), p: p)
            }
            if f.isSick && !f.condition.isDanger {
                // 病気の魚の上に紫の十字
                let cx = (rect.midX / p).rounded() * p, cy = rect.minY - p * 5
                var cross = Path()
                cross.addRect(CGRect(x: cx - p, y: cy - p * 2, width: p * 3, height: p * 7))
                cross.addRect(CGRect(x: cx - p * 3, y: cy, width: p * 7, height: p * 3))
                ctx.fill(cross, with: .color(.white))
                var inner = Path()
                inner.addRect(CGRect(x: cx, y: cy - p, width: p, height: p * 5))
                inner.addRect(CGRect(x: cx - p * 2, y: cy + p, width: p * 5, height: p))
                ctx.fill(inner, with: .color(Color(rgb: 0x8E24AA)))
            }
            if f.condition.isDanger {
                // 危険な魚の上に「！」
                let ex = (rect.midX / p).rounded() * p, ey = rect.minY - p * 7
                var mark = Path()
                mark.addRect(CGRect(x: ex - p, y: ey - p, width: p * 3, height: p * 7))
                ctx.fill(mark, with: .color(.white))
                var bang = Path()
                bang.addRect(CGRect(x: ex, y: ey, width: p, height: p * 3))
                bang.addRect(CGRect(x: ex, y: ey + p * 4, width: p, height: p))
                ctx.fill(bang, with: .color(Color(rgb: 0xE53935)))
            }
        }
    }

    private func drawPixelFrame(_ ctx: inout GraphicsContext, _ r: CGRect, p: CGFloat) {
        var path = Path()
        let len = p * 3
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX - p, r.minY, -1.0, 1.0), (r.minX, r.maxY - p, 1.0, -1.0), (r.maxX - p, r.maxY - p, -1.0, -1.0)] {
            path.addRect(CGRect(x: dx > 0 ? x : x - len + p, y: y, width: len, height: p))
            path.addRect(CGRect(x: x, y: dy > 0 ? y : y - len + p, width: p, height: len))
        }
        ctx.fill(path, with: .color(.white.opacity(0.9)))
    }
}

/// 背景を毎回同じ模様で描くための乱数。
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
