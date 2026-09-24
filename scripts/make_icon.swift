// アプリアイコン（ドット絵のネオンテトラ）を生成する
import AppKit

let fish = [
    "....SSSSS...",
    "t..BBBBBBBB.",
    "ttBBBBBBBBek",
    "t.RRRRRRRSS.",
    "...RRRRSS...",
]
let pal: [Character: NSColor] = [
    "S": NSColor(srgbRed: 0.85, green: 0.89, blue: 0.93, alpha: 1), "B": NSColor(srgbRed: 0.26, green: 0.85, blue: 1, alpha: 1),
    "R": NSColor(srgbRed: 1, green: 0.23, blue: 0.36, alpha: 1), "t": NSColor(srgbRed: 0.66, green: 0.75, blue: 0.82, alpha: 1),
    "e": .white, "k": NSColor(srgbRed: 0.06, green: 0.06, blue: 0.1, alpha: 1),
]
let outline = NSColor(srgbRed: 0.11, green: 0.16, blue: 0.27, alpha: 1)

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let clip = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    clip.addClip()
    NSGradient(starting: NSColor(srgbRed: 0.31, green: 0.71, blue: 0.9, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.25, blue: 0.45, alpha: 1))!.draw(in: rect, angle: -90)
    // 砂
    NSColor(srgbRed: 0.85, green: 0.75, blue: 0.52, alpha: 1).setFill()
    NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.16).fill()
    // 魚（輪郭つき）
    let cols = 14, rows = 7
    let p = (rect.width * 0.72 / CGFloat(cols)).rounded(.down)
    let ox = rect.midX - CGFloat(cols) * p / 2, oy = rect.midY - CGFloat(rows) * p / 2 + rect.height * 0.06
    var grid = [[NSColor?]](repeating: [NSColor?](repeating: nil, count: cols), count: rows)
    for (r, row) in fish.enumerated() { for (c, ch) in row.enumerated() { grid[r + 1][c + 1] = pal[ch] } }
    for r in 0..<rows { for c in 0..<cols where grid[r][c] == nil {
        let n = [(r-1,c),(r+1,c),(r,c-1),(r,c+1)].contains { $0.0 >= 0 && $0.0 < rows && $0.1 >= 0 && $0.1 < cols && pal.values.contains(grid[$0.0][$0.1] ?? .clear) }
        if n { grid[r][c] = outline }
    } }
    for r in 0..<rows { for c in 0..<cols { if let col = grid[r][c] {
        col.setFill()
        NSRect(x: ox + CGFloat(c) * p, y: oy + CGFloat(rows - 1 - r) * p, width: p, height: p).fill()
    } } }
    // 泡
    NSColor.white.withAlphaComponent(0.7).setFill()
    for (bx, by, b) in [(0.74, 0.72, 2.0), (0.8, 0.8, 1.0), (0.7, 0.86, 1.0)] {
        NSRect(x: rect.minX + rect.width * bx, y: rect.minY + rect.height * by, width: p * b, height: p * b).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(size: size).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
