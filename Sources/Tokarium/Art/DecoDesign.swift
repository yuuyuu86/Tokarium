import CoreGraphics
import Foundation

/// 装飾の設計図。すべての画風がここから描く。座標は 0〜1（y は上が 0、下が 1）。
enum DecoDesign {
    case grass(color: UInt32, blades: Int, height: Double)
    case ribbon(color: UInt32, blades: Int)                  // バリスネリア
    case sword(color: UInt32)                                // 広い葉
    case fern(color: UInt32)
    case ball(color: UInt32)                                 // マリモ
    case lotus(leaf: UInt32, flower: UInt32)
    case rock(color: UInt32, lumps: Int)
    case pebbles(colors: [UInt32])
    case stack(color: UInt32)
    case branchCoral(color: UInt32)
    case fanCoral(color: UInt32)
    case brainCoral(color: UInt32)
    case tubeCoral(color: UInt32, tip: UInt32)
    case anemone(color: UInt32, tip: UInt32)
    case scallop(color: UInt32)
    case conch(color: UInt32)
    case starfish(color: UInt32)
    case wood(color: UInt32)
    case parts([DecoPart])
}

struct DecoPart {
    enum Shape {
        case rect(CGRect, radius: CGFloat = 0)
        case ellipse(CGRect)
        case poly([CGPoint])
        case smooth([CGPoint])
        /// 上が丸いアーチ形の穴や窓。
        case arch(CGRect)
    }
    var shape: Shape
    var color: UInt32
    var role: ArtLayer.Role = .body
    var texture: Texture = .none

    static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UInt32, role: ArtLayer.Role = .body, radius: CGFloat = 0, texture: Texture = .none) -> DecoPart {
        DecoPart(shape: .rect(CGRect(x: x, y: y, width: w, height: h), radius: radius), color: color, role: role, texture: texture)
    }
    static func e(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UInt32, role: ArtLayer.Role = .body, texture: Texture = .none) -> DecoPart {
        DecoPart(shape: .ellipse(CGRect(x: x, y: y, width: w, height: h)), color: color, role: role, texture: texture)
    }
    static func p(_ pts: [(CGFloat, CGFloat)], _ color: UInt32, role: ArtLayer.Role = .body, smooth: Bool = false, texture: Texture = .none) -> DecoPart {
        let cg = pts.map { CGPoint(x: $0.0, y: $0.1) }
        return DecoPart(shape: smooth ? .smooth(cg) : .poly(cg), color: color, role: role, texture: texture)
    }
    static func a(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UInt32 = 0x1C1A20, role: ArtLayer.Role = .dark) -> DecoPart {
        DecoPart(shape: .arch(CGRect(x: x, y: y, width: w, height: h)), color: color, role: role)
    }
}

enum DecoArtBuilder {
    static func build(_ design: DecoDesign, size: CGSize, seed: UInt64) -> ArtModel {
        let W = size.width, H = size.height
        var model = ArtModel(size: size)
        var rng = SeededRandom(seed: seed)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * W, y: y * H) }
        func add(_ path: CGPath, _ hex: UInt32, role: ArtLayer.Role = .body, texture: Texture = .none, shade: Bool = true) {
            let c = RGB(hex)
            if shade {
                model.layers.append(ArtLayer(path, top: c.lighter(0.18), mid: c, bottom: c.darker(0.3), role: role, texture: texture))
            } else {
                model.layers.append(ArtLayer(path, c, role: role, texture: texture))
            }
        }

        switch design {
        case let .grass(color, blades, height):
            let c = RGB(color)
            for i in 0..<blades {
                let t = CGFloat(i) / CGFloat(max(1, blades - 1))
                let base = pt(0.15 + 0.7 * t, 1)
                let len = H * CGFloat(height) * CGFloat.random(in: 0.6...1, using: &rng)
                let path = Shapes.blade(base: base, length: len, width: W * 0.16, bend: W * CGFloat.random(in: -0.25...0.25, using: &rng))
                let shade = i % 2 == 0 ? c : c.darker(0.25)
                model.layers.append(ArtLayer(path, top: shade.lighter(0.15), mid: shade, bottom: shade.darker(0.25), role: .body, texture: .leaf))
            }
        case let .ribbon(color, blades):
            let c = RGB(color)
            for i in 0..<blades {
                let base = pt(0.2 + 0.6 * CGFloat(i) / CGFloat(max(1, blades - 1)), 1)
                let p = CGMutablePath()
                let w = W * 0.1
                let bend = W * CGFloat.random(in: -0.4...0.4, using: &rng)
                p.move(to: CGPoint(x: base.x - w / 2, y: base.y))
                p.addCurve(to: CGPoint(x: base.x + bend, y: 0), control1: CGPoint(x: base.x - w - bend, y: H * 0.6), control2: CGPoint(x: base.x + bend * 1.5, y: H * 0.3))
                p.addCurve(to: CGPoint(x: base.x + w / 2, y: base.y), control1: CGPoint(x: base.x + bend * 1.5 + w, y: H * 0.3), control2: CGPoint(x: base.x + w - bend, y: H * 0.6))
                p.closeSubpath()
                let shade = i % 2 == 0 ? c : c.lighter(0.15)
                model.layers.append(ArtLayer(p, top: shade.lighter(0.2), mid: shade, bottom: shade.darker(0.3), role: .body, texture: .leaf))
            }
        case let .sword(color):
            let c = RGB(color)
            for i in 0..<7 {
                let angle = CGFloat(i - 3) * 0.32
                let path = Shapes.blade(base: pt(0.5, 1), length: H * (0.95 - abs(CGFloat(i - 3)) * 0.1), width: W * 0.28, bend: 0, angle: angle)
                let shade = i % 2 == 0 ? c : c.darker(0.2)
                model.layers.append(ArtLayer(path, top: shade.lighter(0.2), mid: shade, bottom: shade.darker(0.3), role: .body, texture: .leaf))
            }
        case let .fern(color):
            let c = RGB(color)
            for stem in 0..<3 {
                let bx = W * (0.3 + 0.2 * CGFloat(stem))
                let len = H * (0.7 + 0.15 * CGFloat(stem % 2))
                model.strokes.append((Shapes.polygon([CGPoint(x: bx, y: H), CGPoint(x: bx + W * 0.05, y: H - len)]), c.darker(0.4), max(1, W * 0.03)))
                for j in 0..<7 {
                    let y = H - len * CGFloat(j + 1) / 8
                    for side in [-1.0, 1.0] {
                        let leaf = Shapes.blade(base: CGPoint(x: bx + W * 0.02, y: y), length: W * 0.2 * CGFloat(1 - Double(j) * 0.08),
                                                width: W * 0.07, bend: 0, angle: CGFloat(side) * 1.1)
                        model.layers.append(ArtLayer(leaf, top: c.lighter(0.2), mid: c, bottom: c.darker(0.2), role: .body, texture: .leaf))
                    }
                }
            }
        case let .ball(color):
            add(Shapes.ellipse(CGRect(x: 0.05 * W, y: 0.1 * H, width: 0.9 * W, height: 0.9 * H)), color, texture: .leaf)
        case let .lotus(leaf, flower):
            let stem = CGMutablePath()
            stem.move(to: pt(0.5, 1)); stem.addQuadCurve(to: pt(0.5, 0.25), control: pt(0.35, 0.6))
            model.strokes.append((stem, RGB(leaf).darker(0.3), max(1, W * 0.04)))
            add(Shapes.ellipse(CGRect(x: 0, y: 0.45 * H, width: 0.55 * W, height: 0.16 * H)), leaf, texture: .leaf)
            add(Shapes.ellipse(CGRect(x: 0.45 * W, y: 0.6 * H, width: 0.55 * W, height: 0.16 * H)), leaf, texture: .leaf)
            for i in 0..<5 {
                let a = CGFloat(i - 2) * 0.45
                add(Shapes.blade(base: pt(0.5, 0.3), length: H * 0.28, width: W * 0.2, bend: 0, angle: a), flower)
            }
        case let .rock(color, lumps):
            var pts: [CGPoint] = []
            let n = 9 + lumps
            for i in 0..<n {
                let a = CGFloat.pi + CGFloat.pi * CGFloat(i) / CGFloat(n - 1)
                let rr = CGFloat.random(in: 0.8...1, using: &rng)
                pts.append(CGPoint(x: W / 2 + cos(a) * W / 2 * rr, y: H + sin(a) * H * rr * 0.98))
            }
            pts.append(CGPoint(x: W, y: H)); pts.append(CGPoint(x: 0, y: H))
            add(Shapes.smoothClosed(pts), color, texture: .stone)
        case let .pebbles(colors):
            for i in 0..<9 {
                let x = CGFloat.random(in: 0...0.8, using: &rng), w = CGFloat.random(in: 0.14...0.24, using: &rng)
                let y = CGFloat.random(in: 0.35...0.7, using: &rng)
                add(Shapes.ellipse(CGRect(x: x * W, y: y * H, width: w * W, height: w * W * 0.7)), colors[i % colors.count], texture: .stone)
            }
        case let .stack(color):
            let widths: [CGFloat] = [0.9, 0.7, 0.55, 0.38]
            var y = H
            for (i, w) in widths.enumerated() {
                let h = H * 0.24
                let c = RGB(color).mix(RGB(0x9A8F80), CGFloat(i) * 0.1)
                let r = CGRect(x: (W - w * W) / 2 + W * CGFloat.random(in: -0.04...0.04, using: &rng), y: y - h, width: w * W, height: h)
                model.layers.append(ArtLayer(Shapes.ellipse(r), top: c.lighter(0.2), mid: c, bottom: c.darker(0.3), role: .body, texture: .stone))
                y -= h * 0.85
            }
        case let .branchCoral(color):
            func branch(_ from: CGPoint, _ len: CGFloat, _ angle: CGFloat, _ depth: Int) {
                let to = CGPoint(x: from.x + sin(angle) * len, y: from.y - cos(angle) * len)
                let p = CGMutablePath(); p.move(to: from); p.addLine(to: to)
                model.strokes.append((p, RGB(color), max(1.5, W * 0.07 * CGFloat(depth + 1) / 3)))
                if depth > 0 {
                    branch(to, len * 0.7, angle - 0.45, depth - 1)
                    branch(to, len * 0.7, angle + 0.4, depth - 1)
                } else {
                    add(Shapes.ellipse(CGRect(x: to.x - W * 0.05, y: to.y - W * 0.05, width: W * 0.1, height: W * 0.1)), color, shade: false)
                }
            }
            branch(pt(0.5, 1), H * 0.35, 0, 3)
        case let .fanCoral(color):
            let fan = CGMutablePath()
            fan.move(to: pt(0.5, 1))
            fan.addCurve(to: pt(0.5, 1), control1: pt(-0.2, -0.1), control2: pt(1.2, -0.1))
            model.layers.append(ArtLayer(fan, top: RGB(color).lighter(0.2), mid: RGB(color), bottom: RGB(color).darker(0.2), role: .fin, texture: .coral))
            for i in 0..<9 {
                let a = CGFloat(i - 4) * 0.28
                let p = CGMutablePath(); p.move(to: pt(0.5, 1)); p.addLine(to: CGPoint(x: W / 2 + sin(a) * W * 0.5, y: H - cos(a) * H * 0.9))
                model.strokes.append((p, RGB(color).darker(0.35), max(1, W * 0.02)))
            }
        case let .brainCoral(color):
            let r = CGRect(x: 0, y: 0.1 * H, width: W, height: 1.8 * H)
            let dome = CGMutablePath(); dome.addEllipse(in: r)
            let clip = CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil)
            let domeClipped = dome.intersection(clip)
            add(domeClipped, color, texture: .coral)
            for i in 0..<5 {
                let p = CGMutablePath()
                let y = H * (0.3 + CGFloat(i) * 0.14)
                p.move(to: CGPoint(x: W * 0.1, y: y))
                for k in 0..<6 { p.addQuadCurve(to: CGPoint(x: W * (0.1 + 0.14 * CGFloat(k + 1)), y: y), control: CGPoint(x: W * (0.17 + 0.14 * CGFloat(k)), y: y + (k % 2 == 0 ? -1 : 1) * H * 0.07)) }
                model.strokes.append((p, RGB(color).darker(0.35), max(1, W * 0.02)))
            }
        case let .tubeCoral(color, tip):
            for i in 0..<5 {
                let x = W * (0.1 + 0.18 * CGFloat(i)), h = H * CGFloat.random(in: 0.5...1, using: &rng)
                add(Shapes.rect(CGRect(x: x, y: H - h, width: W * 0.13, height: h), radius: W * 0.05), color, texture: .coral)
                add(Shapes.ellipse(CGRect(x: x - W * 0.01, y: H - h - W * 0.03, width: W * 0.15, height: W * 0.07)), tip, role: .detail, shade: false)
            }
        case let .anemone(color, tip):
            add(Shapes.ellipse(CGRect(x: 0.2 * W, y: 0.55 * H, width: 0.6 * W, height: 0.5 * H)), color)
            for i in 0..<13 {
                let a = CGFloat(i - 6) * 0.2
                let t = Shapes.blade(base: pt(0.5, 0.7), length: H * 0.65, width: W * 0.07, bend: W * CGFloat.random(in: -0.1...0.1, using: &rng), angle: a)
                model.layers.append(ArtLayer(t, top: RGB(tip), mid: RGB(tip).mix(RGB(color), 0.4), bottom: RGB(color), role: .body))
            }
        case let .scallop(color):
            let p = CGMutablePath()
            p.move(to: pt(0.5, 1))
            p.addCurve(to: pt(0.5, 1), control1: pt(-0.4, 0), control2: pt(1.4, 0))
            add(p, color, texture: .none)
            for i in 0..<5 {
                let a = CGFloat(i - 2) * 0.35
                let l = CGMutablePath(); l.move(to: pt(0.5, 1)); l.addLine(to: CGPoint(x: W / 2 + sin(a) * W * 0.45, y: H - cos(a) * H * 0.8))
                model.strokes.append((l, RGB(color).darker(0.3), max(1, W * 0.03)))
            }
        case let .conch(color):
            add(Shapes.smoothClosed([pt(0, 0.9), pt(0.2, 0.3), pt(0.55, 0.05), pt(0.95, 0.35), pt(1, 0.95)]), color)
            model.strokes.append((Shapes.smoothClosed([pt(0.3, 0.7), pt(0.5, 0.35), pt(0.8, 0.5), pt(0.6, 0.85)]), RGB(color).darker(0.3), max(1, W * 0.04)))
        case let .starfish(color):
            var pts: [CGPoint] = []
            for i in 0..<10 {
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let r = (i % 2 == 0 ? 0.5 : 0.22) * W
                pts.append(CGPoint(x: W / 2 + cos(a) * r, y: H * 0.55 + sin(a) * r * 0.9))
            }
            add(Shapes.smoothClosed(pts, tension: 0.3), color)
        case let .wood(color):
            add(Shapes.smoothClosed([pt(0, 0.62), pt(0.25, 0.5), pt(0.55, 0.42), pt(0.8, 0.12), pt(0.97, 0), pt(1, 0.2),
                                     pt(0.82, 0.45), pt(0.6, 0.75), pt(0.3, 1), pt(0.02, 1)]), color, texture: .wood)
            add(Shapes.smoothClosed([pt(0.38, 0.55), pt(0.3, 0.15), pt(0.22, 0), pt(0.3, 0.02), pt(0.42, 0.2), pt(0.5, 0.5)]), color, texture: .wood)
        case let .parts(parts):
            for part in parts {
                let path: CGPath
                switch part.shape {
                case let .rect(r, radius): path = Shapes.rect(CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H), radius: radius * W)
                case let .ellipse(r): path = Shapes.ellipse(CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H))
                case let .poly(pts): path = Shapes.polygon(pts.map { pt($0.x, $0.y) })
                case let .smooth(pts): path = Shapes.smoothClosed(pts.map { pt($0.x, $0.y) })
                case let .arch(r):
                    let rr = CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H)
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: rr.minX, y: rr.maxY))
                    p.addLine(to: CGPoint(x: rr.minX, y: rr.minY + rr.width / 2))
                    p.addArc(center: CGPoint(x: rr.midX, y: rr.minY + rr.width / 2), radius: rr.width / 2, startAngle: .pi, endAngle: 0, clockwise: false)
                    p.addLine(to: CGPoint(x: rr.maxX, y: rr.maxY))
                    p.closeSubpath()
                    path = p
                }
                add(path, part.color, role: part.role, texture: part.texture, shade: part.role == .body)
            }
        }
        return model
    }
}
