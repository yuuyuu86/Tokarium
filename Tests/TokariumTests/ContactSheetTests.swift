import AppKit
import Foundation
import Testing
@testable import Tokarium

/// 全ての魚と装飾を並べた画像を書き出す（TOKARIUM_SHEET にフォルダを指定したときだけ）。
@Test func renderContactSheet() throws {
    guard let dir = ProcessInfo.processInfo.environment["TOKARIUM_SHEET"] else { return }
    for style in AquariumStyles.all {
        let cell: CGFloat = 150, cols = 8
        let items = Catalog.fish.count + Catalog.decorations.count
        let rows = (items + cols - 1) / cols
        let size = CGSize(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.45, blue: 0.7, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.interpolationQuality = .none
        var i = 0
        func place(_ img: CGImage, dots: CGSize, name: String) {
            let col = i % cols, row = i / cols
            let box = CGRect(x: CGFloat(col) * cell + 8, y: size.height - CGFloat(row + 1) * cell + 22, width: cell - 16, height: cell - 30)
            let k = min(box.width / dots.width, box.height / dots.height)
            let w = dots.width * k, h = dots.height * k
            ctx.draw(img, in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
            (name as NSString).draw(at: CGPoint(x: CGFloat(col) * cell + 6, y: size.height - CGFloat(row + 1) * cell + 4),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
            i += 1
        }
        for sp in Catalog.fish {
            if let art = style.fishImage(sp.id, frame: 1, dead: false) { place(art.image, dots: art.dots, name: sp.name) }
        }
        for d in Catalog.decorations {
            if let art = style.decorationImage(d.id) { place(art.image, dots: art.dots, name: d.name) }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/sheet-\(style.id).png"))
    }
}

@Test func everyItemRenders() {
    for style in AquariumStyles.all {
        for sp in Catalog.fish {
            for dead in [false, true] {
                #expect(style.fishImage(sp.id, frame: 1, dead: dead) != nil, "\(style.id) \(sp.id)")
            }
        }
        for d in Catalog.decorations {
            #expect(style.decorationImage(d.id) != nil, "\(style.id) \(d.id)")
        }
    }
    #expect(Set(Catalog.fish.map(\.id)).count == Catalog.fish.count)
    #expect(Set(Catalog.decorations.map(\.id)).count == Catalog.decorations.count)
}
