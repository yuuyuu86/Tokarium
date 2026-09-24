import CoreGraphics
import Foundation

/// 0〜1 の RGB 色。画風ごとに明るさや彩度を変えて使う。
struct RGB: Hashable {
    var r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r)); self.g = min(1, max(0, g)); self.b = min(1, max(0, b))
    }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    func darker(_ t: Double) -> RGB { mix(RGB(r: 0.02, g: 0.03, b: 0.08), t) }
    func lighter(_ t: Double) -> RGB { mix(RGB(r: 1, g: 1, b: 1), t) }

    var luminance: Double { 0.3 * r + 0.59 * g + 0.11 * b }

    func saturated(_ amount: Double) -> RGB {
        let l = luminance
        return RGB(r: l + (r - l) * amount, g: l + (g - l) * amount, b: l + (b - l) * amount)
    }

    var gray: RGB {
        let y = luminance * 0.75 + 0.12
        return RGB(r: y, g: y, b: y + 0.02)
    }

    func cg(_ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    var hex: UInt32 {
        (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }
}

/// 表面の質感（リアルな画風で使う）。
enum Texture {
    case none, scales, stone, wood, leaf, coral, metal, sand
}

/// 描画の単位。形を作る側は「どこに何色の何があるか」だけを決め、塗り方は画風が決める。
struct ArtLayer {
    enum Role {
        case body      // 立体として陰影をつける本体
        case fin       // 半透明になりうるひれ
        case pattern   // 本体に重ねる模様（clip の内側だけに描く）
        case detail    // 小さな部品（輪郭なし）
        case dark      // 窓や入口などの暗い穴
        case glow      // 光るもの
    }

    var path: CGPath
    /// 上・中・下の色。塗りつぶしの画風は中の色を主に使う。
    var colors: (top: RGB, mid: RGB, bottom: RGB)
    var role: Role
    var texture: Texture = .none
    var clip: CGPath? = nil
    var alpha: Double = 1
    /// ひれの筋を描くときの向き（根元の点）。
    var rayOrigin: CGPoint? = nil

    init(_ path: CGPath, _ color: RGB, role: Role, texture: Texture = .none, clip: CGPath? = nil, alpha: Double = 1) {
        self.path = path
        self.colors = (color, color, color)
        self.role = role
        self.texture = texture
        self.clip = clip
        self.alpha = alpha
    }

    init(_ path: CGPath, top: RGB, mid: RGB, bottom: RGB, role: Role, texture: Texture = .none, clip: CGPath? = nil) {
        self.path = path
        self.colors = (top, mid, bottom)
        self.role = role
        self.texture = texture
        self.clip = clip
    }
}

struct ArtEye {
    var center: CGPoint
    var radius: CGFloat
    var iris: RGB
}

/// 形を作った結果。
struct ArtModel {
    var size: CGSize
    var layers: [ArtLayer] = []
    var eyes: [ArtEye] = []
    /// 線（ひげなど）。
    var strokes: [(path: CGPath, color: RGB, width: CGFloat)] = []
}

/// 見た目を毎回同じにするための乱数。
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

extension String {
    /// 文字列から安定した乱数の種を作る。
    var stableSeed: UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}

// MARK: - パスの小道具

enum Shapes {
    /// 点を滑らかにつないだ閉じた形。
    static func smoothClosed(_ pts: [CGPoint], tension: CGFloat = 0.5) -> CGPath {
        let p = CGMutablePath()
        guard pts.count > 2 else { return p }
        let n = pts.count
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n {
            let cur = pts[i], next = pts[(i + 1) % n]
            p.addQuadCurve(to: mid(cur, next), control: cur)
        }
        p.closeSubpath()
        return p
    }

    static func polygon(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts)
        p.closeSubpath()
        return p
    }

    static func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }

    static func rect(_ r: CGRect, radius: CGFloat = 0) -> CGPath {
        radius > 0 ? CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
            : CGPath(rect: r, transform: nil)
    }

    /// 細長い葉（根元から先へ曲がる）。
    static func blade(base: CGPoint, length: CGFloat, width: CGFloat, bend: CGFloat, angle: CGFloat = 0) -> CGPath {
        let tip = CGPoint(x: base.x + bend + sin(angle) * length, y: base.y - cos(angle) * length)
        let midL = CGPoint(x: base.x - width / 2 + bend * 0.4, y: base.y - length * 0.5)
        let midR = CGPoint(x: base.x + width / 2 + bend * 0.6, y: base.y - length * 0.5)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: base.x - width / 2, y: base.y))
        p.addQuadCurve(to: tip, control: midL)
        p.addQuadCurve(to: CGPoint(x: base.x + width / 2, y: base.y), control: midR)
        p.closeSubpath()
        return p
    }
}
