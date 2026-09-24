import CoreGraphics
import Foundation

enum ArtRenderer {
    /// 形をドット絵の画像にする。1ピクセルが水槽の1ドット。
    /// `padding` は周りに足す余白（輪郭用）。
    static func render(_ model: ArtModel, padding: Int = 1) -> CGImage? {
        let w = max(1, Int(ceil(model.size.width))) + padding * 2, h = max(1, Int(ceil(model.size.height))) + padding * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 上を y=0 にする
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: CGFloat(padding), y: CGFloat(padding))
        paintPixel(ctx, model)
        guard let image = ctx.makeImage() else { return nil }
        return pixelOutline(image)
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
