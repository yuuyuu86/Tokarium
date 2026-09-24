import CoreGraphics
import Foundation

enum TailShape { case fork, round, fan, veil, pointed, crescent, spade, double }
enum FinShape { case none, small, tall, sail, spiky, long, veil }

enum FishPattern {
    /// 縦じま（数、太さ=体長比、色、縁取り）。
    case vStripes(count: Int, width: Double, color: UInt32, edge: UInt32? = nil, from: Double = 0.1, to: Double = 0.85)
    /// 横の帯（中心の高さ -1〜1、太さ、色、範囲）。
    case hBand(y: Double, thickness: Double, color: UInt32, from: Double = 0, to: Double = 1)
    /// 体の後ろ側の色（ネオンテトラの赤など）。範囲は体の前後 0〜1、下側だけ。
    case lowerRear(color: UInt32, from: Double)
    /// 頭の色。
    case head(color: UInt32, fraction: Double)
    /// 体の後半の色。
    case rear(color: UInt32, from: Double)
    /// 斑点（数、大きさ、色）。
    case spots(count: Int, size: Double, color: UInt32)
    /// 錦鯉のような大きなまだら。
    case patches(count: Int, color: UInt32)
    /// ラスボラの三角の黒い模様。
    case wedge(color: UInt32)
    /// 尾の付け根の目玉模様。
    case eyeSpot(color: UInt32)
}

/// 魚の設計図。すべての画風がここから描く。
struct FishDesign {
    /// 画像の幅（水槽のドット数）。
    var length: Double = 14
    /// 画像の高さ / 幅。
    var aspect: Double = 0.45
    /// 尾の長さ（幅に対する割合）。
    var tailFrac: Double = 0.24
    /// 体の半分の高さ（画像の高さの半分に対する割合）。
    var depth: Double = 0.6
    var peduncle: Double = 0.35
    var hump: Double = 0.45
    var blunt: Double = 0.5
    var belly: Double = 1.0
    var tail: TailShape = .fork
    var tailSpread: Double = 0.75
    var dorsal: FinShape = .small
    var dorsalHeight: Double = 0.35
    var anal: FinShape = .small
    var analHeight: Double = 0.25
    var pectoral = true
    var filaments = false
    var barbels = false
    var bulgingEyes = false
    var eyeSize: Double = 1.0

    var back: UInt32 = 0x6E8FA8
    var body: UInt32 = 0xA8C4D8
    var bellyColor: UInt32 = 0xE0EAF0
    var fin: UInt32 = 0xA8C0D0
    var iris: UInt32 = 0x202020
    var patterns: [FishPattern] = []
    var scales = true

    var canvas: CGSize { CGSize(width: length, height: max(4, length * aspect)) }
}

enum FishArtBuilder {
    /// 設計図から形を作る。`scale` は1ドットあたりのピクセル数、`phase` は尾の振れ（-1〜1）。
    static func build(_ d: FishDesign, scale s: CGFloat, phase: Double, dead: Bool = false) -> ArtModel {
        let W = CGFloat(d.canvas.width) * s, H = CGFloat(d.canvas.height) * s
        var model = ArtModel(size: CGSize(width: W, height: H))
        func c(_ hex: UInt32) -> RGB { dead ? RGB(hex).gray : RGB(hex) }

        let m = s * 0.5
        let cy = H / 2
        let tailLen = W * CGFloat(d.tailFrac)
        let bx0 = m + tailLen            // 尾の付け根
        let bx1 = W - m                   // 口先
        let bl = bx1 - bx0
        let bh = (H / 2 - m) * CGFloat(d.depth)
        let ph = bh * CGFloat(d.peduncle)
        let hx = bx0 + bl * CGFloat(d.hump)
        let belly = bh * CGFloat(d.belly)
        let blunt = CGFloat(d.blunt)

        // 体
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: bx0, y: cy - ph))
        bodyPath.addCurve(to: CGPoint(x: hx, y: cy - bh),
                          control1: CGPoint(x: bx0 + (hx - bx0) * 0.45, y: cy - ph),
                          control2: CGPoint(x: bx0 + (hx - bx0) * 0.55, y: cy - bh))
        bodyPath.addCurve(to: CGPoint(x: bx1, y: cy + bh * 0.05),
                          control1: CGPoint(x: hx + (bx1 - hx) * 0.55, y: cy - bh),
                          control2: CGPoint(x: bx1, y: cy - bh * blunt))
        bodyPath.addCurve(to: CGPoint(x: hx, y: cy + belly),
                          control1: CGPoint(x: bx1, y: cy + belly * blunt),
                          control2: CGPoint(x: hx + (bx1 - hx) * 0.55, y: cy + belly))
        bodyPath.addCurve(to: CGPoint(x: bx0, y: cy + ph),
                          control1: CGPoint(x: bx0 + (hx - bx0) * 0.55, y: cy + belly),
                          control2: CGPoint(x: bx0 + (hx - bx0) * 0.45, y: cy + ph))
        bodyPath.closeSubpath()

        let finColor = c(d.fin)
        let sway = CGFloat(phase) * (H / 2) * 0.18

        // 尾
        let spread = (H / 2 - m) * CGFloat(d.tailSpread)
        let tailPath = CGMutablePath()
        let tx = m, base = bx0 + s * 0.8
        switch d.tail {
        case .fork, .crescent:
            let notch = d.tail == .crescent ? 0.2 : 0.55
            tailPath.move(to: CGPoint(x: base, y: cy - ph))
            tailPath.addQuadCurve(to: CGPoint(x: tx, y: cy - spread + sway), control: CGPoint(x: tx + tailLen * 0.5, y: cy - ph * 1.2 + sway))
            tailPath.addQuadCurve(to: CGPoint(x: tx, y: cy + spread + sway),
                                  control: CGPoint(x: tx + tailLen * CGFloat(notch) * 1.4, y: cy + sway))
            tailPath.addQuadCurve(to: CGPoint(x: base, y: cy + ph), control: CGPoint(x: tx + tailLen * 0.5, y: cy + ph * 1.2 + sway))
        case .round, .spade:
            tailPath.move(to: CGPoint(x: base, y: cy - ph))
            tailPath.addCurve(to: CGPoint(x: tx, y: cy + sway),
                              control1: CGPoint(x: base - tailLen * 0.3, y: cy - spread + sway),
                              control2: CGPoint(x: tx, y: cy - spread * (d.tail == .spade ? 0.3 : 0.9) + sway))
            tailPath.addCurve(to: CGPoint(x: base, y: cy + ph),
                              control1: CGPoint(x: tx, y: cy + spread * (d.tail == .spade ? 0.3 : 0.9) + sway),
                              control2: CGPoint(x: base - tailLen * 0.3, y: cy + spread + sway))
        case .fan, .double:
            tailPath.move(to: CGPoint(x: base, y: cy - ph))
            tailPath.addLine(to: CGPoint(x: tx + tailLen * 0.1, y: cy - spread + sway))
            tailPath.addQuadCurve(to: CGPoint(x: tx + tailLen * 0.1, y: cy + spread + sway),
                                  control: CGPoint(x: tx - tailLen * 0.15, y: cy + sway))
            tailPath.addLine(to: CGPoint(x: base, y: cy + ph))
            if d.tail == .double {
                tailPath.move(to: CGPoint(x: base, y: cy))
                tailPath.addLine(to: CGPoint(x: tx + tailLen * 0.35, y: cy + sway))
            }
        case .veil:
            tailPath.move(to: CGPoint(x: base, y: cy - ph))
            tailPath.addCurve(to: CGPoint(x: tx, y: cy + spread * 0.9 + sway),
                              control1: CGPoint(x: base - tailLen * 0.4, y: cy - spread + sway),
                              control2: CGPoint(x: tx - tailLen * 0.1, y: cy - spread * 0.2 + sway))
            tailPath.addQuadCurve(to: CGPoint(x: base, y: cy + ph),
                                  control: CGPoint(x: base - tailLen * 0.3, y: cy + spread * 1.1 + sway))
        case .pointed:
            tailPath.move(to: CGPoint(x: base, y: cy - ph))
            tailPath.addQuadCurve(to: CGPoint(x: tx, y: cy + sway), control: CGPoint(x: tx + tailLen * 0.5, y: cy - ph * 0.8 + sway))
            tailPath.addQuadCurve(to: CGPoint(x: base, y: cy + ph), control: CGPoint(x: tx + tailLen * 0.5, y: cy + ph * 0.8 + sway))
        }
        tailPath.closeSubpath()
        var tailLayer = ArtLayer(tailPath, finColor, role: .fin)
        tailLayer.rayOrigin = CGPoint(x: base, y: cy)
        model.layers.append(tailLayer)

        // 背びれ・しりびれ
        func fin(_ shape: FinShape, top: Bool, height: Double) {
            guard shape != .none else { return }
            let dir: CGFloat = top ? -1 : 1
            let edge = top ? cy - bh * 0.92 : cy + belly * 0.92
            let fh = (H / 2 - m) * CGFloat(height)
            let p = CGMutablePath()
            var start: CGFloat = bx0 + bl * 0.3, end: CGFloat = bx0 + bl * 0.62
            switch shape {
            case .none: return
            case .small:
                p.move(to: CGPoint(x: start, y: edge))
                p.addQuadCurve(to: CGPoint(x: start + (end - start) * 0.35, y: edge + dir * fh), control: CGPoint(x: start, y: edge + dir * fh * 0.6))
                p.addQuadCurve(to: CGPoint(x: end, y: edge), control: CGPoint(x: end - (end - start) * 0.2, y: edge + dir * fh * 0.4))
            case .tall:
                start = bx0 + bl * 0.25; end = bx0 + bl * 0.55
                p.move(to: CGPoint(x: end, y: edge))
                p.addQuadCurve(to: CGPoint(x: bx0 - tailLen * 0.3, y: edge + dir * fh), control: CGPoint(x: start + (end - start) * 0.6, y: edge + dir * fh * 0.9))
                p.addQuadCurve(to: CGPoint(x: start, y: edge), control: CGPoint(x: start, y: edge + dir * fh * 0.3))
            case .sail, .veil:
                start = bx0 + bl * (shape == .veil ? 0.05 : 0.15); end = bx0 + bl * 0.65
                p.move(to: CGPoint(x: end, y: edge))
                p.addCurve(to: CGPoint(x: start - tailLen * (shape == .veil ? 0.5 : 0.1), y: edge + dir * fh * 0.8 + sway * 0.3),
                           control1: CGPoint(x: end - (end - start) * 0.2, y: edge + dir * fh * 1.1),
                           control2: CGPoint(x: start, y: edge + dir * fh * 1.2))
                p.addQuadCurve(to: CGPoint(x: start, y: edge), control: CGPoint(x: start - s, y: edge + dir * fh * 0.3))
            case .spiky:
                start = bx0 + bl * 0.1; end = bx0 + bl * 0.7
                p.move(to: CGPoint(x: start, y: edge))
                let spikes = 6
                for i in 0..<spikes {
                    let x0 = start + (end - start) * CGFloat(i) / CGFloat(spikes)
                    let x1 = start + (end - start) * CGFloat(i + 1) / CGFloat(spikes)
                    p.addLine(to: CGPoint(x: x0 - s * 0.5, y: edge + dir * fh * (i % 2 == 0 ? 1 : 0.8)))
                    p.addLine(to: CGPoint(x: x1, y: edge + dir * fh * 0.25))
                }
                p.addLine(to: CGPoint(x: end, y: edge))
            case .long:
                start = bx0 + bl * 0.05; end = bx0 + bl * 0.75
                p.move(to: CGPoint(x: start, y: edge))
                p.addQuadCurve(to: CGPoint(x: end, y: edge), control: CGPoint(x: (start + end) / 2, y: edge + dir * fh * 1.6))
            }
            p.closeSubpath()
            var layer = ArtLayer(p, finColor, role: .fin)
            layer.rayOrigin = CGPoint(x: (start + end) / 2, y: edge)
            model.layers.append(layer)
        }
        fin(d.dorsal, top: true, height: d.dorsalHeight)
        fin(d.anal, top: false, height: d.analHeight)

        if d.filaments {
            let p = CGMutablePath()
            let x0 = bx0 + bl * 0.6
            p.move(to: CGPoint(x: x0, y: cy + belly * 0.8))
            p.addQuadCurve(to: CGPoint(x: x0 - bl * 0.5, y: H - m), control: CGPoint(x: x0 - bl * 0.1, y: H - m + sway * 0.2))
            model.strokes.append((p, finColor.darker(0.2), max(1, s * 0.6)))
        }

        // 本体
        var bodyLayer = ArtLayer(bodyPath, top: c(d.back), mid: c(d.body), bottom: c(d.bellyColor), role: .body,
                                 texture: d.scales ? .scales : .none)
        bodyLayer.rayOrigin = nil
        model.layers.append(bodyLayer)

        // 模様
        var rng = SeededRandom(seed: UInt64(d.length * 1000) &+ UInt64(d.back))
        for pat in d.patterns {
            let path = CGMutablePath()
            var color: UInt32 = 0
            switch pat {
            case let .vStripes(count, width, col, edge, from, to):
                color = col
                for i in 0..<count {
                    let t = count == 1 ? (from + to) / 2 : from + (to - from) * Double(i) / Double(count - 1)
                    let x = bx0 + bl * CGFloat(t)
                    let w = max(s, bl * CGFloat(width))
                    let r = CGRect(x: x - w / 2, y: 0, width: w, height: H)
                    if let edge {
                        let er = r.insetBy(dx: -max(s * 0.5, w * 0.18), dy: 0)
                        model.layers.append(ArtLayer(Shapes.rect(er), c(edge), role: .pattern, clip: bodyPath))
                    }
                    path.addPath(Shapes.ellipse(CGRect(x: r.minX, y: -H * 0.2, width: r.width, height: H * 1.4)))
                }
            case let .hBand(y, thickness, col, from, to):
                color = col
                let h = max(s, bh * CGFloat(thickness))
                let yy = cy + bh * CGFloat(y)
                path.addRect(CGRect(x: bx0 + bl * CGFloat(from), y: yy - h / 2, width: bl * CGFloat(to - from), height: h))
            case let .lowerRear(col, from):
                color = col
                path.addRect(CGRect(x: bx0 - s, y: cy + bh * 0.05, width: bl * CGFloat(from) + s, height: H))
            case let .head(col, fraction):
                color = col
                path.addRect(CGRect(x: bx1 - bl * CGFloat(fraction), y: 0, width: bl * CGFloat(fraction) + s, height: H))
            case let .rear(col, from):
                color = col
                path.addRect(CGRect(x: 0, y: 0, width: bx0 + bl * CGFloat(from), height: H))
            case let .spots(count, size, col):
                color = col
                for _ in 0..<count {
                    let x = bx0 + bl * CGFloat.random(in: 0.1...0.85, using: &rng)
                    let y = cy + bh * CGFloat.random(in: -0.75...0.65, using: &rng)
                    let r = max(s * 0.6, bl * CGFloat(size))
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            case let .patches(count, col):
                color = col
                for _ in 0..<count {
                    let x = bx0 + bl * CGFloat.random(in: 0.05...0.8, using: &rng)
                    let y = cy + bh * CGFloat.random(in: -1...0.2, using: &rng)
                    let w = bl * CGFloat.random(in: 0.18...0.34, using: &rng)
                    path.addPath(Shapes.smoothClosed((0..<7).map { i in
                        let a = CGFloat(i) / 7 * .pi * 2
                        let rr = w * CGFloat.random(in: 0.6...1, using: &rng)
                        return CGPoint(x: x + cos(a) * rr, y: y + sin(a) * rr * 0.7)
                    }))
                }
            case let .wedge(col):
                color = col
                path.addLines(between: [CGPoint(x: bx0 + bl * 0.1, y: cy - bh * 0.1), CGPoint(x: bx0 + bl * 0.55, y: cy - bh * 0.5),
                                        CGPoint(x: bx0 + bl * 0.55, y: cy + bh * 0.55)])
                path.closeSubpath()
            case let .eyeSpot(col):
                color = col
                let r = max(s, bh * 0.35)
                path.addEllipse(in: CGRect(x: bx0 + bl * 0.1 - r, y: cy - bh * 0.3 - r, width: r * 2, height: r * 2))
            }
            model.layers.append(ArtLayer(path, c(color), role: .pattern, clip: bodyPath))
        }

        // 胸びれ
        if d.pectoral {
            let px = bx1 - bl * 0.3, py = cy + bh * 0.25
            let p = Shapes.ellipse(CGRect(x: px - bl * 0.12, y: py - bh * 0.18, width: bl * 0.16, height: bh * 0.36))
            var layer = ArtLayer(p, finColor.lighter(0.1), role: .fin)
            layer.rayOrigin = CGPoint(x: px + bl * 0.04, y: py)
            model.layers.append(layer)
        }

        // ひげ
        if d.barbels {
            for i in 0..<2 {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: bx1 - s * 0.5, y: cy + bh * 0.3))
                p.addQuadCurve(to: CGPoint(x: bx1 - s * CGFloat(1 + i * 2), y: cy + bh * 1.05), control: CGPoint(x: bx1 + s, y: cy + bh * 0.9))
                model.strokes.append((p, c(d.back).darker(0.2), max(1, s * 0.35)))
            }
        }

        // 目
        let er = max(s * 0.7, bh * 0.2 * CGFloat(d.eyeSize))
        var ec = CGPoint(x: bx1 - bl * 0.13, y: cy - bh * 0.22)
        if d.bulgingEyes { ec.y = cy - bh * 0.55 }
        model.eyes.append(ArtEye(center: ec, radius: er, iris: c(d.iris)))
        return model
    }
}
