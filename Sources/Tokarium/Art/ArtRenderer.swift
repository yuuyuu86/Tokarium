import CoreGraphics
import Foundation

/// 画風。形は共通で、塗り方だけが違う。
enum Look: String, CaseIterable {
    case pixel, anime, realistic, picturebook
}

enum ArtRenderer {
    /// 形を画風に合わせて画像にする。
    /// `padding` は周りに足す余白（ドット絵の輪郭用）。
    static func render(_ model: ArtModel, look: Look, seed: UInt64 = 1, padding: Int = 0) -> CGImage? {
        let w = max(1, Int(ceil(model.size.width))) + padding * 2, h = max(1, Int(ceil(model.size.height))) + padding * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 上を y=0 にする
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: CGFloat(padding), y: CGFloat(padding))
        var rng = SeededRandom(seed: seed)
        let unit = min(model.size.width, model.size.height)

        switch look {
        case .pixel: paintPixel(ctx, model)
        case .anime: paintAnime(ctx, model, unit: unit)
        case .realistic: paintRealistic(ctx, model, unit: unit, rng: &rng)
        case .picturebook: paintPicturebook(ctx, model, unit: unit, rng: &rng)
        }
        guard let image = ctx.makeImage() else { return nil }
        return look == .pixel ? pixelOutline(image) : image
    }

    // MARK: ドット絵

    private static func bands(_ ctx: CGContext, _ layer: ArtLayer, top: Double, bottom: Double, alpha: Double = 1) {
        let box = layer.path.boundingBox
        ctx.saveGState()
        ctx.addPath(layer.path); ctx.clip()
        ctx.setFillColor(layer.colors.mid.cg(alpha)); ctx.fill(box)
        ctx.setFillColor(layer.colors.top.cg(alpha)); ctx.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * top))
        ctx.setFillColor(layer.colors.bottom.cg(alpha))
        ctx.fill(CGRect(x: box.minX, y: box.minY + box.height * (1 - bottom), width: box.width, height: box.height * bottom))
        ctx.restoreGState()
    }

    private static func withClip(_ ctx: CGContext, _ clip: CGPath?, _ body: () -> Void) {
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip() }
        body()
        ctx.restoreGState()
    }

    private static func paintPixel(_ ctx: CGContext, _ model: ArtModel) {
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        for layer in model.layers {
            withClip(ctx, layer.clip) {
                switch layer.role {
                case .body: bands(ctx, layer, top: 0.28, bottom: 0.32)
                default:
                    ctx.addPath(layer.path)
                    ctx.setFillColor(layer.colors.mid.cg()); ctx.fillPath()
                }
            }
        }
        for s in model.strokes {
            ctx.addPath(s.path); ctx.setStrokeColor(s.color.cg()); ctx.setLineWidth(max(1, s.width)); ctx.strokePath()
        }
        for eye in model.eyes {
            let x = floor(eye.center.x), y = floor(eye.center.y)
            if eye.radius >= 1.5 {
                ctx.setFillColor(RGB(0xFFFFFF).cg()); ctx.fill(CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                ctx.setFillColor(eye.iris.darker(0.5).cg()); ctx.fill(CGRect(x: x, y: y - 1, width: 1, height: 2))
            } else {
                ctx.setFillColor(RGB(0xFFFFFF).cg()); ctx.fill(CGRect(x: x - 1, y: y, width: 1, height: 1))
                ctx.setFillColor(RGB(0x101018).cg()); ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    /// 半端な透明をなくし、1ドットの輪郭をつける。
    private static func pixelOutline(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // 透明度を 0 か 255 にそろえる
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = px[i + 3]
            if a < 110 { px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0 } else if a < 255 {
                let f = 255.0 / Double(a)
                px[i] = UInt8(min(255, Double(px[i]) * f)); px[i + 1] = UInt8(min(255, Double(px[i + 1]) * f))
                px[i + 2] = UInt8(min(255, Double(px[i + 2]) * f)); px[i + 3] = 255
            }
        }
        let src = px
        for y in 0..<h {
            for x in 0..<w where src[(y * w + x) * 4 + 3] == 0 {
                var neighbor: Int?
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, nx < w, ny >= 0, ny < h, src[(ny * w + nx) * 4 + 3] == 255 { neighbor = (ny * w + nx) * 4; break }
                }
                if let n = neighbor {
                    let i = (y * w + x) * 4
                    px[i] = UInt8(Double(src[n]) * 0.3); px[i + 1] = UInt8(Double(src[n + 1]) * 0.3)
                    px[i + 2] = UInt8(min(255, Double(src[n + 2]) * 0.3 + 20)); px[i + 3] = 255
                }
            }
        }
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    // MARK: アニメ調（はっきりした色・太い線・影を段で塗る）

    private static func paintAnime(_ ctx: CGContext, _ model: ArtModel, unit: CGFloat) {
        let line = max(1, unit * 0.045)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        for layer in model.layers {
            let mid = layer.colors.mid.saturated(1.25)
            withClip(ctx, layer.clip) {
                switch layer.role {
                case .body:
                    let box = layer.path.boundingBox
                    ctx.saveGState()
                    ctx.addPath(layer.path); ctx.clip()
                    ctx.setFillColor(mid.cg()); ctx.fill(box)
                    // 下側の明るい腹と、段の影
                    ctx.setFillColor(layer.colors.bottom.saturated(1.2).lighter(0.1).cg())
                    ctx.fillEllipse(in: CGRect(x: box.minX - box.width * 0.1, y: box.minY + box.height * 0.62, width: box.width * 1.2, height: box.height * 0.8))
                    ctx.setFillColor(mid.darker(0.35).cg(0.35))
                    ctx.fillEllipse(in: CGRect(x: box.minX + box.width * 0.05, y: box.minY + box.height * 0.8, width: box.width * 1.1, height: box.height * 0.6))
                    // つやの帯
                    ctx.setFillColor(RGB(0xFFFFFF).cg(0.55))
                    ctx.fillEllipse(in: CGRect(x: box.minX + box.width * 0.35, y: box.minY + box.height * 0.12, width: box.width * 0.4, height: max(1, box.height * 0.1)))
                    ctx.restoreGState()
                    ctx.addPath(layer.path); ctx.setStrokeColor(mid.darker(0.65).cg()); ctx.setLineWidth(line); ctx.strokePath()
                case .fin:
                    ctx.addPath(layer.path); ctx.setFillColor(mid.lighter(0.1).cg(0.95)); ctx.fillPath()
                    ctx.addPath(layer.path); ctx.setStrokeColor(mid.darker(0.6).cg()); ctx.setLineWidth(line * 0.8); ctx.strokePath()
                case .pattern:
                    ctx.addPath(layer.path); ctx.setFillColor(mid.cg()); ctx.fillPath()
                case .detail, .glow:
                    ctx.addPath(layer.path); ctx.setFillColor(mid.cg()); ctx.fillPath()
                    ctx.addPath(layer.path); ctx.setStrokeColor(mid.darker(0.6).cg()); ctx.setLineWidth(line * 0.6); ctx.strokePath()
                case .dark:
                    ctx.addPath(layer.path); ctx.setFillColor(RGB(0x221A30).cg()); ctx.fillPath()
                }
            }
        }
        for s in model.strokes {
            ctx.addPath(s.path); ctx.setStrokeColor(s.color.saturated(1.2).darker(0.2).cg()); ctx.setLineWidth(max(1, s.width)); ctx.strokePath()
        }
        for eye in model.eyes {
            let r = eye.radius * 1.35
            let c = eye.center
            ctx.setFillColor(RGB(0xFFFFFF).cg()); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setStrokeColor(RGB(0x1A1020).cg()); ctx.setLineWidth(line * 0.7)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let pr = r * 0.72
            ctx.setFillColor(eye.iris.darker(0.6).cg()); ctx.fillEllipse(in: CGRect(x: c.x - pr + r * 0.15, y: c.y - pr, width: pr * 2, height: pr * 2))
            ctx.setFillColor(RGB(0xFFFFFF).cg())
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.1, y: c.y - r * 0.55, width: r * 0.55, height: r * 0.55))
            ctx.fillEllipse(in: CGRect(x: c.x + r * 0.3, y: c.y + r * 0.15, width: r * 0.25, height: r * 0.25))
        }
    }

    // MARK: リアル（なめらかな陰影・半透明のひれ・うろこや岩肌の質感）

    private static func paintRealistic(_ ctx: CGContext, _ model: ArtModel, unit: CGFloat, rng: inout SeededRandom) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for layer in model.layers {
            withClip(ctx, layer.clip) {
                let box = layer.path.boundingBox
                switch layer.role {
                case .body:
                    ctx.saveGState()
                    ctx.addPath(layer.path); ctx.clip()
                    let colors = [layer.colors.top.darker(0.12).cg(), layer.colors.mid.cg(), layer.colors.bottom.lighter(0.08).cg()] as CFArray
                    if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) {
                        ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
                    }
                    texture(ctx, layer.texture, box: box, color: layer.colors.mid, unit: unit, rng: &rng)
                    // 縁を暗く、上を明るく
                    let rim = [RGB(0x000000).cg(0), RGB(0x000000).cg(0.28)] as CFArray
                    if let g = CGGradient(colorsSpace: space, colors: rim, locations: [0.55, 1]) {
                        ctx.drawRadialGradient(g, startCenter: CGPoint(x: box.midX, y: box.midY), startRadius: 0,
                                               endCenter: CGPoint(x: box.midX, y: box.midY), endRadius: max(box.width, box.height) * 0.62, options: [.drawsAfterEndLocation])
                    }
                    let spec = [RGB(0xFFFFFF).cg(0.35), RGB(0xFFFFFF).cg(0)] as CFArray
                    if let g = CGGradient(colorsSpace: space, colors: spec, locations: [0, 1]) {
                        let c = CGPoint(x: box.minX + box.width * 0.62, y: box.minY + box.height * 0.28)
                        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: box.width * 0.3, options: [])
                    }
                    ctx.restoreGState()
                    ctx.addPath(layer.path); ctx.setStrokeColor(layer.colors.mid.darker(0.6).cg(0.35)); ctx.setLineWidth(max(0.5, unit * 0.012)); ctx.strokePath()
                case .fin:
                    ctx.saveGState()
                    ctx.addPath(layer.path); ctx.clip()
                    ctx.setFillColor(layer.colors.mid.cg(0.5)); ctx.fill(box)
                    if let o = layer.rayOrigin {
                        ctx.setStrokeColor(layer.colors.mid.darker(0.4).cg(0.4)); ctx.setLineWidth(max(0.5, unit * 0.01))
                        for i in 0...14 {
                            let t = CGFloat(i) / 14
                            let far = CGPoint(x: box.minX + box.width * t, y: o.y < box.midY ? box.maxY : box.minY)
                            let alt = CGPoint(x: o.x < box.midX ? box.maxX : box.minX, y: box.minY + box.height * t)
                            ctx.move(to: o); ctx.addLine(to: abs(o.x - box.midX) > abs(o.y - box.midY) ? alt : far)
                        }
                        ctx.strokePath()
                    }
                    ctx.restoreGState()
                case .pattern:
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: unit * 0.02, color: layer.colors.mid.cg(0.6))
                    ctx.addPath(layer.path); ctx.setFillColor(layer.colors.mid.cg(0.9)); ctx.fillPath()
                    ctx.restoreGState()
                case .detail:
                    ctx.addPath(layer.path); ctx.setFillColor(layer.colors.mid.cg(layer.alpha)); ctx.fillPath()
                case .dark:
                    ctx.saveGState()
                    ctx.addPath(layer.path); ctx.clip()
                    let colors = [RGB(0x05060A).cg(), RGB(0x1A1D26).cg()] as CFArray
                    if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                        ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
                    }
                    ctx.restoreGState()
                case .glow:
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: unit * 0.15, color: layer.colors.mid.cg())
                    ctx.addPath(layer.path); ctx.setFillColor(layer.colors.mid.lighter(0.3).cg()); ctx.fillPath()
                    ctx.restoreGState()
                }
            }
        }
        for s in model.strokes {
            ctx.addPath(s.path); ctx.setStrokeColor(s.color.cg(0.85)); ctx.setLineWidth(max(0.6, s.width * 0.8)); ctx.setLineCap(.round); ctx.strokePath()
        }
        for eye in model.eyes {
            let r = eye.radius, c = eye.center
            let colors = [RGB(0xE8C060).mix(eye.iris, 0.3).cg(), eye.iris.darker(0.4).cg()] as CFArray
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.clip()
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            ctx.restoreGState()
            ctx.setFillColor(RGB(0x050505).cg()); ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1))
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.85)); ctx.fillEllipse(in: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.5, width: r * 0.35, height: r * 0.35))
        }
    }

    private static func texture(_ ctx: CGContext, _ t: Texture, box: CGRect, color: RGB, unit: CGFloat, rng: inout SeededRandom) {
        let step = max(1.5, unit * 0.06)
        switch t {
        case .none, .sand, .metal: return
        case .scales:
            ctx.setLineWidth(max(0.5, unit * 0.01))
            ctx.setStrokeColor(color.darker(0.5).cg(0.18))
            var row = 0
            var y = box.minY
            while y < box.maxY + step {
                var x = box.minX + (row % 2 == 0 ? 0 : step / 2)
                while x < box.maxX + step {
                    ctx.addArc(center: CGPoint(x: x, y: y), radius: step * 0.6, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
                    ctx.strokePath()
                    x += step
                }
                y += step * 0.6; row += 1
            }
        case .stone, .coral:
            let n = Int(box.width * box.height / (step * step) * 0.8)
            for _ in 0..<min(n, 1500) {
                let x = CGFloat.random(in: box.minX...box.maxX, using: &rng), y = CGFloat.random(in: box.minY...box.maxY, using: &rng)
                let r = step * CGFloat.random(in: 0.1...0.35, using: &rng)
                ctx.setFillColor((Bool.random(using: &rng) ? color.darker(0.35) : color.lighter(0.25)).cg(t == .coral ? 0.45 : 0.3))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        case .wood:
            ctx.setStrokeColor(color.darker(0.45).cg(0.35)); ctx.setLineWidth(max(0.5, unit * 0.015))
            var y = box.minY
            while y < box.maxY {
                ctx.move(to: CGPoint(x: box.minX, y: y))
                ctx.addCurve(to: CGPoint(x: box.maxX, y: y + step * 0.5), control1: CGPoint(x: box.midX, y: y - step), control2: CGPoint(x: box.midX, y: y + step))
                y += step * 0.8
            }
            ctx.strokePath()
        case .leaf:
            ctx.setStrokeColor(color.lighter(0.4).cg(0.25)); ctx.setLineWidth(max(0.5, unit * 0.01))
            ctx.move(to: CGPoint(x: box.midX, y: box.maxY)); ctx.addLine(to: CGPoint(x: box.midX, y: box.minY)); ctx.strokePath()
        }
    }

    // MARK: 絵本風（やわらかい色・色鉛筆の線・紙の風合い）

    private static func paintPicturebook(_ ctx: CGContext, _ model: ArtModel, unit: CGFloat, rng: inout SeededRandom) {
        func soft(_ c: RGB) -> RGB { c.saturated(0.8).lighter(0.22) }
        let line = max(1, unit * 0.025)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        for layer in model.layers {
            withClip(ctx, layer.clip) {
                let mid = soft(layer.colors.mid)
                switch layer.role {
                case .dark:
                    ctx.addPath(layer.path); ctx.setFillColor(RGB(0x4A3F5A).cg(0.9)); ctx.fillPath()
                case .pattern:
                    ctx.addPath(layer.path); ctx.setFillColor(mid.cg(0.85)); ctx.fillPath()
                default:
                    let box = layer.path.boundingBox
                    ctx.saveGState()
                    ctx.addPath(layer.path); ctx.clip()
                    ctx.setFillColor(mid.cg(layer.role == .fin ? 0.75 : 0.95)); ctx.fill(box)
                    // 水彩のにじみ
                    ctx.setFillColor(soft(layer.colors.bottom).darker(0.1).cg(0.3))
                    ctx.fillEllipse(in: CGRect(x: box.minX, y: box.minY + box.height * 0.55, width: box.width, height: box.height * 0.7))
                    for _ in 0..<40 {
                        let x = CGFloat.random(in: box.minX...max(box.minX + 1, box.maxX), using: &rng)
                        let y = CGFloat.random(in: box.minY...max(box.minY + 1, box.maxY), using: &rng)
                        ctx.setFillColor(RGB(0xFFFFFF).cg(0.12))
                        ctx.fillEllipse(in: CGRect(x: x, y: y, width: line * 1.5, height: line * 1.5))
                    }
                    ctx.restoreGState()
                    if layer.role != .detail {
                        ctx.addPath(layer.path); ctx.setStrokeColor(mid.darker(0.45).cg(0.7)); ctx.setLineWidth(line); ctx.strokePath()
                    }
                }
            }
        }
        for s in model.strokes {
            ctx.addPath(s.path); ctx.setStrokeColor(soft(s.color).darker(0.2).cg(0.8)); ctx.setLineWidth(max(1, s.width * 0.8)); ctx.strokePath()
        }
        for eye in model.eyes {
            let r = max(1, eye.radius * 0.8), c = eye.center
            ctx.setFillColor(RGB(0x3A2E40).cg()); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.9)); ctx.fillEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.6, width: r * 0.5, height: r * 0.5))
            ctx.setFillColor(RGB(0xF4A0B0).cg(0.45))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 2.2, y: c.y + r * 1.2, width: r * 1.8, height: r * 1.0))
        }
    }
}

/// 描いた画像の置き場。同じ形・画風・大きさは一度しか描かない。
final class ArtCache {
    static let shared = ArtCache()
    private var images: [String: CGImage] = [:]
    private let lock = NSLock()

    func image(_ key: String, make: () -> CGImage?) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let img = images[key] { return img }
        if images.count > 1500 { images.removeAll() }
        guard let img = make() else { return nil }
        images[key] = img
        return img
    }
}
