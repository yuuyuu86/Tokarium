import CoreGraphics
import Foundation

/// 文字で描いたドット絵。' ' と '.' は透明。右向きで描く。
struct PixelSprite {
    let rows: [String]
    let palette: [Character: UInt32]
    /// 自動で付ける輪郭の色（nil なら付けない）。
    var outline: UInt32? = nil
    /// 尾びれとして揺らす左端の列数（魚のみ）。
    var tailColumns: Int = 0
    /// 1ドットを何ピクセルで描くか。
    var scale: Int = 1

    var width: Int { (rows.map(\.count).max() ?? 0) + (outline == nil ? 0 : 2) }
    var height: Int { rows.count + (outline == nil ? 0 : 2) }
}

enum SpriteLibrary {
    private static let eye: [Character: UInt32] = ["e": 0xFFFFFF, "k": 0x101018]

    private static func pal(_ p: [Character: UInt32]) -> [Character: UInt32] {
        p.merging(eye) { a, _ in a }
    }

    static let fish: [String: PixelSprite] = [
        "neon": PixelSprite(rows: [
            "....SSSSS...",
            "t..BBBBBBBB.",
            "ttBBBBBBBBek",
            "t.RRRRRRRSS.",
            "...RRRRSS...",
        ], palette: pal(["S": 0xD8E4EE, "B": 0x43D9FF, "R": 0xFF3B5C, "t": 0xA8C0D0]), outline: 0x1C2A44, tailColumns: 2),

        "guppy": PixelSprite(rows: [
            "TT...........",
            "TTU...GGGG...",
            "TUTT.GGGGGGG.",
            "TTUTGGGGGGGek",
            "TUTT.GGGGGGG.",
            "TTU...GGGG...",
            "TT...........",
        ], palette: pal(["T": 0xFF7AA8, "U": 0xFFB347, "G": 0xC9D6B0]), outline: 0x4A3050, tailColumns: 4),

        "cory": PixelSprite(rows: [
            "....CD......",
            "..CCCCCCC...",
            "tCCDCCDCCCe.",
            "ttCCCCCCCCCk",
            "t.WWWWWWWWw.",
        ], palette: pal(["C": 0xC8B89A, "D": 0x6B5A48, "W": 0xEFE3C6, "w": 0xD8C8A8, "t": 0xB8A888]), outline: 0x3A3028, tailColumns: 2),

        "goldfish": PixelSprite(rows: [
            ".......OO.....",
            ".....OOOOOO...",
            "FF..OOOOOOOOO.",
            "FFFOOOYYOOOOek",
            "FFFOOYYYYOOOOO",
            "FF..OOYYYYOOO.",
            ".....OOOOOO...",
            ".......F......",
        ], palette: pal(["O": 0xFF8C1A, "Y": 0xFFC04D, "F": 0xFFB070]), outline: 0x6A2A08, tailColumns: 3),

        "betta": PixelSprite(rows: [
            "VV....RRRR....",
            "VVV..RRRRRRR..",
            "VVVVRRRRRRRRek",
            "VVVVRRRRRRRRR.",
            "VVVV.RRRRRR...",
            "VVV...VVVV....",
            "VV...VVVV.....",
        ], palette: pal(["R": 0xD81B60, "V": 0x8E24AA]), outline: 0x2A0A2A, tailColumns: 4),

        "angel": PixelSprite(rows: [
            ".....A......",
            ".....AA.....",
            "....AKAA....",
            "...AAKAAA...",
            "t.AAAKAAAAA.",
            "ttAAAKAAAAek",
            "t.AAAKAAAAA.",
            "...AAKAAA...",
            "....AKAA....",
            ".....AA.....",
            ".....A......",
        ], palette: pal(["A": 0xE8E8D8, "K": 0x3A3A3A, "t": 0xC8C8B8]), outline: 0x2A2A30, tailColumns: 2),

        "clown": PixelSprite(rows: [
            "....OOOOO.....",
            "t..OWOOWOOO...",
            "ttOOWOOWOOOWek",
            "ttOOWOOWOOOWOO",
            "t..OWOOWOOO...",
            "....OOOOO.....",
        ], palette: pal(["O": 0xFF7B1C, "W": 0xFFFFFF, "t": 0xFF9A4C]), outline: 0x2A1208, tailColumns: 2),

        "puffer": PixelSprite(rows: [
            "....GGGGG....",
            "..GGDGGDGGG..",
            "t.GGGGGGGGGe.",
            "ttGGDGGGDGGGk",
            "ttYYYYYYYYYYY",
            "t.YYYYYYYYYY.",
            "...YYYYYYY...",
        ], palette: pal(["G": 0x7CC242, "Y": 0xF4F0C0, "D": 0x2D5A1A, "t": 0x9CD262]), outline: 0x1E3A12, tailColumns: 2),
    ]

    private static func tallGrass() -> [String] {
        let pattern = ["..gG..", ".gG...", ".gG...", "..gG..", "...gG.", "...gG."]
        var rows = ["...g..", "..gg.."]
        for i in 0..<20 { rows.append(pattern[i % pattern.count]) }
        rows.append(".gGgG.")
        return rows
    }

    static let decorations: [String: PixelSprite] = [
        "grass": PixelSprite(rows: [
            "..g....",
            "..g..g.",
            ".gG..g.",
            ".gG.gG.",
            "gG..gG.",
            "gG.gG.g",
            ".gGgG.g",
            ".gGgGgG",
            "..gGgG.",
            "..gGgG.",
        ], palette: ["g": 0x4CC05A, "G": 0x2E7D32], outline: nil, scale: 2),
        "tallgrass": PixelSprite(rows: tallGrass(), palette: ["g": 0x5BC96A, "G": 0x2E7D32], outline: nil, scale: 2),
        "rock": PixelSprite(rows: [
            "....hhhh....",
            "..hhrrrrrr..",
            ".hrrrrrrrrR.",
            "hrrrrrrrrRRR",
            "rrrrrrrrRRRR",
            "RRRRRRRRRRRR",
        ], palette: ["h": 0xB0B5BD, "r": 0x8A8F99, "R": 0x6B707A], outline: 0x3A3E46, scale: 2),
        "shell": PixelSprite(rows: [
            "..pPp..",
            ".pPpPp.",
            "pPpPpPp",
            ".PPPPP.",
        ], palette: ["p": 0xFFC9D6, "P": 0xE89AAC], outline: 0x7A4A56),
        "wood": PixelSprite(rows: [
            "..................ww..",
            "...............wwWW...",
            "ww.....wwwwwwwwWWW....",
            ".wwwwwwwWWWWWWWW......",
            "..WWWWWWWW....WW......",
            "...WW..........WW.....",
        ], palette: ["w": 0x9D7E5C, "W": 0x6D5238], outline: 0x3A2A1A, scale: 2),
        "coral": PixelSprite(rows: [
            "c...c..c",
            "c.c.c.cc",
            "cCc.cCc.",
            ".cCcCc..",
            "..CCC...",
            "..CC....",
            "..CC....",
        ], palette: ["c": 0xFF7F9E, "C": 0xE0426C], outline: 0x6A1A30, scale: 2),
        "airstone": PixelSprite(rows: [
            ".ssss.",
            "sSSSSs",
        ], palette: ["s": 0x9AA0A8, "S": 0x6D737B], outline: 0x33363C),
        "chest": PixelSprite(rows: [
            ".bbbbbbbbb.",
            "bBBBBBBBBBb",
            "bbbbyybbbbb",
            "yyyyyyyyyyy",
            "bBBByyBBBBb",
            "bbbbbbbbbbb",
            "bBBBBBBBBBb",
        ], palette: ["b": 0x9B6A3B, "B": 0x6E4520, "y": 0xFFD54F], outline: 0x2E1A0A, scale: 2),
        "castle": PixelSprite(rows: [
            "...f.........f...",
            "...ff........ff..",
            "...s.........s...",
            "..sss.......sss..",
            "..s.s.s.s.s.s.s..",
            "..sssssssssssss..",
            "..sSsssssssssSs..",
            "..sssssssssssss..",
            "..ssssssdssssss..",
            "..sssssdddsssss..",
            "..sssssdddsssss..",
        ], palette: ["s": 0xC0B8A8, "S": 0x5A5448, "d": 0x3A3530, "f": 0xE53935], outline: 0x3A3630, scale: 3),
    ]

    // MARK: 画像化

    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    /// - Parameters:
    ///   - frame: 0 か 1。1 のとき尾びれを1段ずらす。
    ///   - dead: 灰色にして上下反転する。
    static func image(for sprite: PixelSprite, key: String, frame: Int = 0, dead: Bool = false) -> CGImage? {
        let cacheKey = "\(key)-\(frame)-\(dead)"
        lock.lock(); defer { lock.unlock() }
        if let img = cache[cacheKey] { return img }
        guard let img = render(sprite, frame: frame, dead: dead) else { return nil }
        cache[cacheKey] = img
        return img
    }

    private static func render(_ sprite: PixelSprite, frame: Int, dead: Bool) -> CGImage? {
        let pad = sprite.outline == nil ? 0 : 1
        let w = sprite.width, h = sprite.height
        var grid = [[UInt32?]](repeating: [UInt32?](repeating: nil, count: w), count: h)
        for (r, row) in sprite.rows.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." && ch != " " {
                if let color = sprite.palette[ch] { grid[r + pad][c + pad] = color }
            }
        }
        // 尾びれを揺らす: 左端の列を1段上へずらす
        if frame == 1 && sprite.tailColumns > 0 {
            for c in pad..<(pad + sprite.tailColumns) {
                let column = (0..<h).map { grid[$0][c] }
                for r in 0..<h { grid[r][c] = r + 1 < h ? column[r + 1] : nil }
            }
        }
        if let outline = sprite.outline {
            let filled = grid
            for r in 0..<h {
                for c in 0..<w where filled[r][c] == nil {
                    let neighbors = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
                    if neighbors.contains(where: { $0.0 >= 0 && $0.0 < h && $0.1 >= 0 && $0.1 < w && filled[$0.0][$0.1] != nil }) {
                        grid[r][c] = outline
                    }
                }
            }
        }
        if dead {
            grid = grid.reversed().map { row in row.map { $0.map(desaturate) } }
        }

        // RGBA の順にバイトで並べる
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for r in 0..<h {
            for c in 0..<w {
                guard let rgb = grid[r][c] else { continue }
                let i = (r * w + c) * 4
                pixels[i] = UInt8((rgb >> 16) & 0xFF)
                pixels[i + 1] = UInt8((rgb >> 8) & 0xFF)
                pixels[i + 2] = UInt8(rgb & 0xFF)
                pixels[i + 3] = 0xFF
            }
        }
        let space = CGColorSpaceCreateDeviceRGB()
        return pixels.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }

    private static func desaturate(_ rgb: UInt32) -> UInt32 {
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        let y = UInt32(min(255, (0.3 * r + 0.59 * g + 0.11 * b) * 0.8 + 30))
        return (y << 16) | (y << 8) | y
    }
}
