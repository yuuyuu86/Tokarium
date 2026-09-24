import SwiftUI

/// 表現スタイル。魚や装飾の形（設計図）は共通で、塗り方と背景をスタイルが決める。
/// いまはドット絵のみ。画風を増やすときはここに追加する。
struct AquariumStyle: Identifiable {
    let id: String
    let name: String
}

enum AquariumStyles {
    static let pixel = AquariumStyle(id: "pixel", name: String(localized: "ドット絵"))
    static let all: [AquariumStyle] = [pixel]
    static func style(_ id: String) -> AquariumStyle { all.first { $0.id == id } ?? pixel }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - 画像

extension AquariumStyle {
    /// 1ドットの画面上の大きさ。水槽を大きくすると、同じ画面により多くのドットが入る。
    func dot(_ size: CGSize, level: Int = 0) -> CGFloat {
        max(2, floor(min(size.width, size.height) / (150 + 25 * CGFloat(level))))
    }

    /// 魚の1ドットの大きさ。成長に合わせて大きくなる（整数ピクセルでくっきり描く）。
    func fishDot(_ growth: Double, p: CGFloat) -> CGFloat {
        max(1, (p * (1 + 0.7 * CGFloat(growth))).rounded())
    }

    /// 魚の画像と、ドット単位の大きさ。手描きのスプライトがあればそれを使う。
    func fishImage(_ speciesID: String, frame: Int, dead: Bool) -> (image: CGImage, dots: CGSize)? {
        if let sprite = SpriteLibrary.fish[speciesID],
           let img = SpriteLibrary.image(for: sprite, key: "fish-\(speciesID)", frame: frame % 2, dead: dead) {
            return (img, CGSize(width: sprite.width, height: sprite.height))
        }
        let design = Catalog.species(speciesID).design
        guard let img = ArtCache.shared.image("fish-\(speciesID)-\(frame % 2)-\(dead)", make: {
            ArtRenderer.render(FishArtBuilder.build(design, scale: 1, phase: frame % 2 == 0 ? -0.5 : 0.5, dead: dead))
        }) else { return nil }
        return (img, CGSize(width: design.canvas.width + 2, height: design.canvas.height + 2))
    }

    func decorationImage(_ kindID: String) -> (image: CGImage, dots: CGSize)? {
        if let sprite = SpriteLibrary.decorations[kindID], let img = SpriteLibrary.image(for: sprite, key: "deco-\(kindID)") {
            return (img, CGSize(width: sprite.width * sprite.scale, height: sprite.height * sprite.scale))
        }
        let kind = Catalog.decoration(kindID)
        guard let img = ArtCache.shared.image("deco-\(kindID)", make: {
            ArtRenderer.render(DecoArtBuilder.build(kind.design, size: kind.size, seed: kindID.stableSeed))
        }) else { return nil }
        return (img, CGSize(width: kind.size.width + 2, height: kind.size.height + 2))
    }

    private func draw(_ ctx: inout GraphicsContext, _ img: CGImage, in rect: CGRect) {
        ctx.draw(Image(decorative: img, scale: 1).interpolation(.none), in: rect)
    }

    func snap(_ v: CGFloat, _ p: CGFloat) -> CGFloat { (v / p).rounded() * p }
}

// MARK: - 配置

extension AquariumStyle {
    func decorationFrame(_ d: Decoration, tank: Tank, size: CGSize) -> CGRect {
        let p = dot(size, level: tank.level)
        guard let art = decorationImage(d.kindID) else { return .zero }
        let w = art.dots.width * p, h = art.dots.height * p
        let sand = size.height * SwimEngine.sandTop
        let base = snap(sand + p * (d.layer == 0 ? 2 : 5), p)
        let cx = snap(CGFloat(d.x) * size.width, p)
        return CGRect(x: snap(cx - w / 2, p), y: base - h, width: w, height: h)
    }

    func fishFrame(_ f: Fish, tank: Tank, engine: SwimEngine, size: CGSize) -> CGRect? {
        guard let s = engine.swimmers[f.id] else { return nil }
        let p = dot(size, level: tank.level)
        let fp = fishDot(f.growth, p: p)
        guard let art = fishImage(f.speciesID, frame: 0, dead: !f.isAlive) else { return nil }
        let w = art.dots.width * fp, h = art.dots.height * fp
        let bob = f.isAlive ? CGFloat(sin(s.phase * 0.5)) * p * 0.6 : 0
        return CGRect(x: snap(CGFloat(s.x) * size.width - w / 2, p), y: snap(CGFloat(s.y) * size.height - h / 2 + bob, p), width: w, height: h)
    }
}

// MARK: - 背景

extension AquariumStyle {
    func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank) {
        let p = dot(size, level: tank.level)
        pixelBackground(&ctx, size: size, p: p)

        // 装飾（奥 → 手前）
        for d in tank.decorations.filter(\.isPlaced).sorted(by: { ($0.layer, $0.x) < ($1.layer, $1.x) }) {
            guard let art = decorationImage(d.kindID) else { continue }
            draw(&ctx, art.image, in: decorationFrame(d, tank: tank, size: size))
        }

        // 水のにごり
        let murk = max(0, 1 - tank.waterQuality / 100)
        if murk > 0.05 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x5A6B2A, opacity: murk * 0.45)))
        }
    }

    private func pixelBackground(_ ctx: inout GraphicsContext, size: CGSize, p: CGFloat) {
        let cols = Int(ceil(size.width / p)), rows = Int(ceil(size.height / p))
        let sandRow = Int(Double(rows) * SwimEngine.sandTop)
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
        rays(&ctx, size: size, p: p, bottom: CGFloat(sandRow) * p, opacity: 0.05)
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
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(sandRow) * p, width: size.width, height: size.height - CGFloat(sandRow) * p)), with: .color(Color(rgb: 0xD9BE84)))
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(sandRow) * p, width: size.width, height: p)), with: .color(Color(rgb: 0xEAD5A0)))
        var dark = Path(), light = Path()
        for _ in 0..<(cols * (rows - sandRow) / 9) {
            let sx = Int.random(in: 0..<cols, using: &rng), sy = Int.random(in: (sandRow + 1)..<max(sandRow + 2, rows), using: &rng)
            let r = CGRect(x: CGFloat(sx) * p, y: CGFloat(sy) * p, width: p, height: p)
            if Bool.random(using: &rng) { dark.addRect(r) } else { light.addRect(r) }
        }
        ctx.fill(dark, with: .color(Color(rgb: 0xB89A62)))
        ctx.fill(light, with: .color(Color(rgb: 0xF0DCAA)))
    }

    private func rays(_ ctx: inout GraphicsContext, size: CGSize, p: CGFloat, bottom: CGFloat, opacity: Double) {
        for i in 0..<4 {
            let x0 = size.width * (0.12 + 0.24 * Double(i))
            var ray = Path()
            ray.move(to: CGPoint(x: x0, y: 0))
            ray.addLine(to: CGPoint(x: x0 + p * 10, y: 0))
            ray.addLine(to: CGPoint(x: x0 - size.width * 0.08 + p * 24, y: bottom))
            ray.addLine(to: CGPoint(x: x0 - size.width * 0.08, y: bottom))
            ray.closeSubpath()
            ctx.fill(ray, with: .linearGradient(Gradient(colors: [.white.opacity(opacity * 1.6), .white.opacity(0)]),
                                                startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0, y: bottom)))
        }
    }
}

// MARK: - 動くもの（魚・餌・泡・水面）

extension AquariumStyle {
    func drawLive(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank, engine: SwimEngine, selected: UUID?) {
        let p = dot(size, level: tank.level)
        let t = engine.time

        // 水面のゆらめき
        var shimmer = Path()
        let cols = Int(ceil(size.width / p))
        for x in 0..<cols where (x + Int(t * 6)) % 7 < 3 { shimmer.addRect(CGRect(x: CGFloat(x) * p, y: 0, width: p, height: p)) }
        ctx.fill(shimmer, with: .color(.white.opacity(0.35)))

        // 泡
        var bubbles = Path()
        for b in engine.bubbles {
            let bx = snap(CGFloat(b.x) * size.width + CGFloat(sin(t * 3 + b.wobble)) * p, p)
            let by = snap(CGFloat(b.y) * size.height, p)
            bubbles.addRect(CGRect(x: bx, y: by - p, width: p, height: p)); bubbles.addRect(CGRect(x: bx - p, y: by, width: p, height: p))
            bubbles.addRect(CGRect(x: bx + p, y: by, width: p, height: p)); bubbles.addRect(CGRect(x: bx, y: by + p, width: p, height: p))
        }
        ctx.fill(bubbles, with: .color(.white.opacity(0.55)))

        // 餌
        var food = Path()
        for pellet in engine.pellets where pellet.y > 0 {
            food.addRect(CGRect(x: snap(CGFloat(pellet.x) * size.width, p), y: snap(CGFloat(pellet.y) * size.height, p), width: p, height: p))
        }
        ctx.fill(food, with: .color(Color(rgb: 0x8B4A1C)))

        // 魚（死んだ魚を奥に）
        for f in tank.fish.sorted(by: { ($0.isAlive ? 1 : 0) < ($1.isAlive ? 1 : 0) }) {
            guard let s = engine.swimmers[f.id], let rect = fishFrame(f, tank: tank, engine: engine, size: size) else { continue }
            let frame = f.isAlive ? Int(s.phase) % 2 : 0
            guard let art = fishImage(f.speciesID, frame: frame, dead: !f.isAlive) else { continue }
            var layer = ctx
            if !s.facingRight || !f.isAlive {
                layer.translateBy(x: rect.midX, y: rect.midY)
                layer.scaleBy(x: s.facingRight ? 1 : -1, y: f.isAlive ? 1 : -1)
                layer.translateBy(x: -rect.midX, y: -rect.midY)
            }
            draw(&layer, art.image, in: rect)

            if f.id == selected { drawSelection(&ctx, rect.insetBy(dx: -p * 2, dy: -p * 2), p: p) }
            if f.isSick && !f.condition.isDanger { drawMarker(&ctx, above: rect, p: p, color: 0x8E24AA, symbol: "+") }
            if f.condition.isDanger { drawMarker(&ctx, above: rect, p: p, color: 0xE53935, symbol: "!") }
        }
    }

    private func drawMarker(_ ctx: inout GraphicsContext, above rect: CGRect, p: CGFloat, color: UInt32, symbol: String) {
        let cx = snap(rect.midX, p), cy = rect.minY - p * 5
        var bg = Path(), fg = Path()
        if symbol == "!" {
            bg.addRect(CGRect(x: cx - p, y: cy - p, width: p * 3, height: p * 7))
            fg.addRect(CGRect(x: cx, y: cy, width: p, height: p * 3)); fg.addRect(CGRect(x: cx, y: cy + p * 4, width: p, height: p))
        } else {
            bg.addRect(CGRect(x: cx - p, y: cy - p * 2, width: p * 3, height: p * 7)); bg.addRect(CGRect(x: cx - p * 3, y: cy, width: p * 7, height: p * 3))
            fg.addRect(CGRect(x: cx, y: cy - p, width: p, height: p * 5)); fg.addRect(CGRect(x: cx - p * 2, y: cy + p, width: p * 5, height: p))
        }
        ctx.fill(bg, with: .color(.white))
        ctx.fill(fg, with: .color(Color(rgb: color)))
    }

    private func drawSelection(_ ctx: inout GraphicsContext, _ r: CGRect, p: CGFloat) {
        var path = Path()
        let len = p * 3
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX - p, r.minY, -1.0, 1.0), (r.minX, r.maxY - p, 1.0, -1.0), (r.maxX - p, r.maxY - p, -1.0, -1.0)] {
            path.addRect(CGRect(x: dx > 0 ? x : x - len + p, y: y, width: len, height: p))
            path.addRect(CGRect(x: x, y: dy > 0 ? y : y - len + p, width: p, height: len))
        }
        ctx.fill(path, with: .color(.white.opacity(0.9)))
    }
}
