import SwiftUI

/// 表現スタイル。魚や装飾の形は共通で、塗り方と背景が画風ごとに変わる。
struct AquariumStyle: Identifiable {
    let look: Look
    var id: String { look.rawValue }

    var name: String {
        switch look {
        case .pixel: return String(localized: "ドット絵")
        case .anime: return String(localized: "アニメ調")
        case .realistic: return String(localized: "リアル")
        case .picturebook: return String(localized: "絵本風")
        }
    }

    var blurb: String {
        switch look {
        case .pixel: return String(localized: "くっきりしたドットのレトロな水槽。")
        case .anime: return String(localized: "太い線とあざやかな色のアニメのような水槽。")
        case .realistic: return String(localized: "光とかげ、うろこまで描き込んだ本物らしい水槽。")
        case .picturebook: return String(localized: "やわらかい水彩の、絵本のような水槽。")
        }
    }

    var isPixel: Bool { look == .pixel }
}

enum AquariumStyles {
    static let all: [AquariumStyle] = Look.allCases.map { AquariumStyle(look: $0) }
    static func style(_ id: String) -> AquariumStyle { all.first { $0.id == id } ?? all[0] }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - 画像

extension AquariumStyle {
    /// 網膜ディスプレイ向けに倍の解像度で描く。
    static let renderScale: CGFloat = 2

    /// 1ドットの画面上の大きさ。水槽を大きくすると、同じ画面により多くのドットが入る。
    func dot(_ size: CGSize, level: Int = 0) -> CGFloat {
        let raw = min(size.width, size.height) / (150 + 25 * CGFloat(level))
        return isPixel ? max(2, floor(raw)) : max(1.5, raw)
    }

    /// 魚の1ドットの大きさ。成長に合わせて大きくなる。
    func fishDot(_ growth: Double, p: CGFloat) -> CGFloat {
        let v = p * (1 + 0.7 * CGFloat(growth))
        return isPixel ? max(1, v.rounded()) : v
    }

    /// 魚の画像と、ドット単位の大きさ。
    func fishImage(_ speciesID: String, dotPixels: CGFloat, frame: Int, dead: Bool) -> (image: CGImage, dots: CGSize)? {
        let sp = Catalog.species(speciesID)
        if isPixel {
            if let sprite = SpriteLibrary.fish[speciesID],
               let img = SpriteLibrary.image(for: sprite, key: "fish-\(speciesID)", frame: frame % 2, dead: dead) {
                return (img, CGSize(width: sprite.width, height: sprite.height))
            }
            let key = "px-fish-\(speciesID)-\(frame % 2)-\(dead)"
            guard let img = ArtCache.shared.image(key, make: {
                let model = FishArtBuilder.build(sp.design, scale: 1, phase: frame % 2 == 0 ? -0.5 : 0.5, dead: dead)
                return ArtRenderer.render(model, look: .pixel, padding: 1)
            }) else { return nil }
            return (img, CGSize(width: sp.design.canvas.width + 2, height: sp.design.canvas.height + 2))
        }
        // 大きさを段階にまとめて、描き直しを減らす
        let scale = max(1, (dotPixels * Self.renderScale * 2).rounded() / 2)
        let phases: [Double] = [-0.8, -0.3, 0.3, 0.8, 0.3, -0.3]
        let f = frame % phases.count
        let key = "\(look.rawValue)-fish-\(speciesID)-\(scale)-\(f)-\(dead)"
        guard let img = ArtCache.shared.image(key, make: {
            let model = FishArtBuilder.build(sp.design, scale: scale, phase: phases[f], dead: dead)
            return ArtRenderer.render(model, look: look, seed: speciesID.stableSeed)
        }) else { return nil }
        return (img, sp.design.canvas)
    }

    func decorationImage(_ kindID: String, dotPixels: CGFloat) -> (image: CGImage, dots: CGSize)? {
        let kind = Catalog.decoration(kindID)
        if isPixel {
            if let sprite = SpriteLibrary.decorations[kindID], let img = SpriteLibrary.image(for: sprite, key: "deco-\(kindID)") {
                return (img, CGSize(width: sprite.width * sprite.scale, height: sprite.height * sprite.scale))
            }
            guard let img = ArtCache.shared.image("px-deco-\(kindID)", make: {
                let model = DecoArtBuilder.build(kind.design, size: kind.size, seed: kindID.stableSeed)
                return ArtRenderer.render(model, look: .pixel, padding: 1)
            }) else { return nil }
            return (img, CGSize(width: kind.size.width + 2, height: kind.size.height + 2))
        }
        let scale = max(1, (dotPixels * Self.renderScale * 2).rounded() / 2)
        guard let img = ArtCache.shared.image("\(look.rawValue)-deco-\(kindID)-\(scale)", make: {
            let size = CGSize(width: kind.size.width * scale, height: kind.size.height * scale)
            let model = DecoArtBuilder.build(kind.design, size: size, seed: kindID.stableSeed)
            return ArtRenderer.render(model, look: look, seed: kindID.stableSeed)
        }) else { return nil }
        return (img, kind.size)
    }

    private func draw(_ ctx: inout GraphicsContext, _ img: CGImage, in rect: CGRect) {
        let image = Image(decorative: img, scale: 1)
        ctx.draw(isPixel ? image.interpolation(.none) : image.interpolation(.high), in: rect)
    }

    func snap(_ v: CGFloat, _ p: CGFloat) -> CGFloat { isPixel ? (v / p).rounded() * p : v }
}

// MARK: - 配置

extension AquariumStyle {
    func decorationFrame(_ d: Decoration, tank: Tank, size: CGSize) -> CGRect {
        let p = dot(size, level: tank.level)
        guard let art = decorationImage(d.kindID, dotPixels: p) else { return .zero }
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
        guard let art = fishImage(f.speciesID, dotPixels: fp, frame: 0, dead: !f.isAlive) else { return nil }
        let w = art.dots.width * fp, h = art.dots.height * fp
        let bob = f.isAlive ? CGFloat(sin(s.phase * 0.5)) * p * 0.6 : 0
        return CGRect(x: snap(CGFloat(s.x) * size.width - w / 2, p), y: snap(CGFloat(s.y) * size.height - h / 2 + bob, p), width: w, height: h)
    }
}

// MARK: - 背景

extension AquariumStyle {
    func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank) {
        let p = dot(size, level: tank.level)
        switch look {
        case .pixel: pixelBackground(&ctx, size: size, p: p)
        case .anime: animeBackground(&ctx, size: size, p: p)
        case .realistic: realisticBackground(&ctx, size: size, p: p)
        case .picturebook: picturebookBackground(&ctx, size: size, p: p)
        }

        // 装飾（奥 → 手前）
        for d in tank.decorations.filter(\.isPlaced).sorted(by: { ($0.layer, $0.x) < ($1.layer, $1.x) }) {
            guard let art = decorationImage(d.kindID, dotPixels: p) else { continue }
            let rect = decorationFrame(d, tank: tank, size: size)
            if look == .realistic {
                // 砂に落ちる影
                ctx.fill(Path(ellipseIn: CGRect(x: rect.minX, y: rect.maxY - p * 1.5, width: rect.width, height: p * 3)),
                         with: .color(.black.opacity(0.25)))
            }
            draw(&ctx, art.image, in: rect)
        }

        // 水のにごり
        let murk = max(0, 1 - tank.waterQuality / 100)
        if murk > 0.05 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x5A6B2A, opacity: murk * 0.45)))
        }
        if look == .realistic {
            // 周辺を少し暗く
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]),
                                           center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                                           startRadius: min(size.width, size.height) * 0.35, endRadius: max(size.width, size.height) * 0.75))
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

    private func smoothHills(_ ctx: inout GraphicsContext, size: CGSize, sand: CGFloat, color: Color, seed: UInt64, height: CGFloat) {
        var rng = SeededRandom(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: sand))
        var x: CGFloat = 0
        while x < size.width {
            let w = size.width * CGFloat.random(in: 0.08...0.2, using: &rng)
            let h = height * CGFloat.random(in: 0.3...1, using: &rng)
            path.addQuadCurve(to: CGPoint(x: x + w, y: sand), control: CGPoint(x: x + w / 2, y: sand - h * 2))
            x += w
        }
        path.addLine(to: CGPoint(x: size.width, y: sand + 2))
        path.addLine(to: CGPoint(x: 0, y: sand + 2))
        ctx.fill(path, with: .color(color))
    }

    private func animeBackground(_ ctx: inout GraphicsContext, size: CGSize, p: CGFloat) {
        let sand = size.height * SwimEngine.sandTop
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(rgb: 0x6FE0FF), Color(rgb: 0x2A9CEB), Color(rgb: 0x1456C8)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: sand)))
        rays(&ctx, size: size, p: p, bottom: sand, opacity: 0.12)
        smoothHills(&ctx, size: size, sand: sand, color: Color(rgb: 0x2A7BD8), seed: 3, height: p * 12)
        smoothHills(&ctx, size: size, sand: sand, color: Color(rgb: 0x1F5FB8), seed: 9, height: p * 6)
        ctx.fill(Path(CGRect(x: 0, y: sand, width: size.width, height: size.height - sand)), with: .color(Color(rgb: 0xFFE2A0)))
        ctx.fill(Path(CGRect(x: 0, y: sand + (size.height - sand) * 0.55, width: size.width, height: size.height)), with: .color(Color(rgb: 0xF2C878)))
        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: sand)); $0.addLine(to: CGPoint(x: size.width, y: sand)) },
                   with: .color(Color(rgb: 0xB07A40)), lineWidth: max(1.5, p * 0.6))
        var rng = SeededRandom(seed: 11)
        for _ in 0..<60 {
            let x = CGFloat.random(in: 0...size.width, using: &rng), y = CGFloat.random(in: sand + p * 2...size.height, using: &rng)
            let r = p * CGFloat.random(in: 0.4...0.9, using: &rng)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r)), with: .color(Color(rgb: 0xD8A860)))
        }
    }

    private func realisticBackground(_ ctx: inout GraphicsContext, size: CGSize, p: CGFloat) {
        let sand = size.height * SwimEngine.sandTop
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(rgb: 0x3E8FB4), Color(rgb: 0x19597E), Color(rgb: 0x082A42)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: sand)))
        rays(&ctx, size: size, p: p, bottom: sand, opacity: 0.07)
        // 遠くの岩は霧でかすむ
        smoothHills(&ctx, size: size, sand: sand, color: Color(rgb: 0x1C4A66).opacity(0.7), seed: 5, height: p * 14)
        smoothHills(&ctx, size: size, sand: sand, color: Color(rgb: 0x13384F), seed: 13, height: p * 7)
        ctx.fill(Path(CGRect(x: 0, y: sand, width: size.width, height: size.height - sand)),
                 with: .linearGradient(Gradient(colors: [Color(rgb: 0xB8A078), Color(rgb: 0x8C7552)]),
                                       startPoint: CGPoint(x: 0, y: sand), endPoint: CGPoint(x: 0, y: size.height)))
        var rng = SeededRandom(seed: 17)
        let grains = Int(size.width * (size.height - sand) / max(4, p * p) * 0.9)
        for _ in 0..<min(grains, 6000) {
            let x = CGFloat.random(in: 0...size.width, using: &rng), y = CGFloat.random(in: sand...size.height, using: &rng)
            let r = p * CGFloat.random(in: 0.12...0.35, using: &rng)
            let tone: UInt32 = [0xD8C8A8, 0x6E5A40, 0xA89070, 0xE8DCC0][Int.random(in: 0...3, using: &rng)]
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(Color(rgb: tone, opacity: 0.6)))
        }
        // 水と砂の境目を霧でなじませる
        ctx.fill(Path(CGRect(x: 0, y: sand - p * 8, width: size.width, height: p * 10)),
                 with: .linearGradient(Gradient(colors: [.clear, Color(rgb: 0x0E3A55, opacity: 0.45), .clear]),
                                       startPoint: CGPoint(x: 0, y: sand - p * 8), endPoint: CGPoint(x: 0, y: sand + p * 2)))
    }

    private func picturebookBackground(_ ctx: inout GraphicsContext, size: CGSize, p: CGFloat) {
        let sand = size.height * SwimEngine.sandTop
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(rgb: 0xD4F0F4), Color(rgb: 0x9FD4E4), Color(rgb: 0x7FB8D6)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: sand)))
        var rng = SeededRandom(seed: 21)
        // 水彩のむら
        for _ in 0..<18 {
            let x = CGFloat.random(in: -0.1...1, using: &rng) * size.width, y = CGFloat.random(in: 0...0.8, using: &rng) * sand
            let r = size.width * CGFloat.random(in: 0.08...0.2, using: &rng)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r)), with: .color(.white.opacity(0.12)))
        }
        smoothHills(&ctx, size: size, sand: sand, color: Color(rgb: 0x9CC8C0).opacity(0.8), seed: 23, height: p * 10)
        var wave = Path()
        wave.move(to: CGPoint(x: 0, y: sand))
        var x: CGFloat = 0
        while x < size.width {
            wave.addQuadCurve(to: CGPoint(x: x + p * 16, y: sand), control: CGPoint(x: x + p * 8, y: sand - p * 2))
            x += p * 16
        }
        wave.addLine(to: CGPoint(x: size.width, y: size.height)); wave.addLine(to: CGPoint(x: 0, y: size.height)); wave.closeSubpath()
        ctx.fill(wave, with: .color(Color(rgb: 0xF4E2C0)))
        ctx.stroke(wave, with: .color(Color(rgb: 0xC8A880).opacity(0.7)), lineWidth: max(1, p * 0.4))
        // 紙の風合い
        for _ in 0..<500 {
            let x = CGFloat.random(in: 0...size.width, using: &rng), y = CGFloat.random(in: 0...size.height, using: &rng)
            ctx.fill(Path(CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(Color(rgb: 0x806040, opacity: 0.08)))
        }
    }
}

// MARK: - 動くもの（魚・餌・泡・水面）

extension AquariumStyle {
    func drawLive(_ ctx: inout GraphicsContext, size: CGSize, tank: Tank, engine: SwimEngine, selected: UUID?) {
        let p = dot(size, level: tank.level)
        let t = engine.time

        // 水面
        switch look {
        case .pixel:
            var shimmer = Path()
            let cols = Int(ceil(size.width / p))
            for x in 0..<cols where (x + Int(t * 6)) % 7 < 3 { shimmer.addRect(CGRect(x: CGFloat(x) * p, y: 0, width: p, height: p)) }
            ctx.fill(shimmer, with: .color(.white.opacity(0.35)))
        default:
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: p))
            var x: CGFloat = 0
            while x <= size.width {
                wave.addLine(to: CGPoint(x: x, y: p + CGFloat(sin(Double(x) / Double(p * 6) + t * 1.5)) * p * 0.6))
                x += p * 2
            }
            ctx.stroke(wave, with: .color(.white.opacity(look == .realistic ? 0.25 : 0.5)), lineWidth: max(1, p * (look == .anime ? 0.7 : 0.4)))
        }

        // 砂にゆれる光（リアル）
        if look == .realistic {
            let sand = size.height * SwimEngine.sandTop
            for i in 0..<14 {
                let fx = (Double(i) * 0.137 + t * 0.012 * (i % 2 == 0 ? 1 : -1)).truncatingRemainder(dividingBy: 1)
                let x = CGFloat(fx < 0 ? fx + 1 : fx) * size.width
                let y = sand + (size.height - sand) * CGFloat(0.2 + 0.6 * abs(sin(Double(i) * 1.7 + t * 0.4)))
                let w = p * CGFloat(6 + (i % 4) * 2)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 0.35)), with: .color(.white.opacity(0.07)))
            }
        }

        // 泡
        for b in engine.bubbles {
            let bx = snap(CGFloat(b.x) * size.width + CGFloat(sin(t * 3 + b.wobble)) * p, p)
            let by = snap(CGFloat(b.y) * size.height, p)
            switch look {
            case .pixel:
                var cross = Path()
                cross.addRect(CGRect(x: bx, y: by - p, width: p, height: p)); cross.addRect(CGRect(x: bx - p, y: by, width: p, height: p))
                cross.addRect(CGRect(x: bx + p, y: by, width: p, height: p)); cross.addRect(CGRect(x: bx, y: by + p, width: p, height: p))
                ctx.fill(cross, with: .color(.white.opacity(0.55)))
            case .anime:
                let r = CGRect(x: bx - p, y: by - p, width: p * 2.2, height: p * 2.2)
                ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: r), with: .color(.white.opacity(0.9)), lineWidth: max(1, p * 0.35))
            case .realistic:
                let r = CGRect(x: bx - p * 0.8, y: by - p * 0.8, width: p * 1.6, height: p * 1.6)
                ctx.stroke(Path(ellipseIn: r), with: .color(.white.opacity(0.45)), lineWidth: max(0.6, p * 0.2))
                ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.2, width: r.width * 0.3, height: r.height * 0.3)),
                         with: .color(.white.opacity(0.7)))
            case .picturebook:
                let r = CGRect(x: bx - p, y: by - p, width: p * 2, height: p * 2)
                ctx.stroke(Path(ellipseIn: r), with: .color(Color(rgb: 0x5A8AA8, opacity: 0.6)), lineWidth: max(1, p * 0.3))
            }
        }

        // 餌
        for pellet in engine.pellets where pellet.y > 0 {
            let fx = snap(CGFloat(pellet.x) * size.width, p), fy = snap(CGFloat(pellet.y) * size.height, p)
            if isPixel {
                ctx.fill(Path(CGRect(x: fx, y: fy, width: p, height: p)), with: .color(Color(rgb: 0x8B4A1C)))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: fx, y: fy, width: p * 1.1, height: p * 1.1)), with: .color(Color(rgb: 0x8B4A1C)))
            }
        }

        // 魚（死んだ魚を奥に）
        for f in tank.fish.sorted(by: { ($0.isAlive ? 1 : 0) < ($1.isAlive ? 1 : 0) }) {
            guard let s = engine.swimmers[f.id], let rect = fishFrame(f, tank: tank, engine: engine, size: size) else { continue }
            let frames = isPixel ? 2 : 6
            let frame = f.isAlive ? Int(s.phase * (isPixel ? 1 : 2.5)) % frames : 0
            guard let art = fishImage(f.speciesID, dotPixels: fishDot(f.growth, p: p), frame: frame, dead: !f.isAlive) else { continue }
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
        if isPixel {
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
            return
        }
        let r = max(7, p * 3)
        let circle = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: circle), with: .color(Color(rgb: color)))
        ctx.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: max(1, r * 0.18))
        ctx.draw(Text(verbatim: symbol).font(.system(size: r * 1.4, weight: .black)).foregroundStyle(.white), at: CGPoint(x: cx, y: cy))
    }

    private func drawSelection(_ ctx: inout GraphicsContext, _ r: CGRect, p: CGFloat) {
        if !isPixel {
            ctx.stroke(Path(roundedRect: r, cornerRadius: p * 2), with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1.5, p * 0.5), dash: [p * 2, p]))
            return
        }
        var path = Path()
        let len = p * 3
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX - p, r.minY, -1.0, 1.0), (r.minX, r.maxY - p, 1.0, -1.0), (r.maxX - p, r.maxY - p, -1.0, -1.0)] {
            path.addRect(CGRect(x: dx > 0 ? x : x - len + p, y: y, width: len, height: p))
            path.addRect(CGRect(x: x, y: dy > 0 ? y : y - len + p, width: p, height: len))
        }
        ctx.fill(path, with: .color(.white.opacity(0.9)))
    }
}
