import AppKit
import SwiftUI

/// 操作パネルを除いた水槽だけの写真を撮る。
@MainActor
enum Snapshot {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tokarium", isDirectory: true)
    }

    /// いまの水槽を画像にして、ピクチャ/Tokarium に保存し、クリップボードにも入れる。
    @discardableResult
    static func take(store: GameStore, size: CGSize) -> URL? {
        let tank = store.state.tank
        let style = store.style
        let engine = store.engine
        let ambient = store.settings.timeOfDay ? Ambient.at(Date()) : .day
        let treasure = store.state.treasureX
        let view = Canvas { ctx, size in
            style.drawBackground(&ctx, size: size, tank: tank)
            style.drawLive(&ctx, size: size, tank: tank, engine: engine, selected: nil, treasureX: treasure, ambient: ambient)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = folder.appendingPathComponent("Tokarium-\(f.string(from: Date())).png")
            try png.write(to: url)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([NSImage(cgImage: cg, size: size)])
            return url
        } catch {
            AppLog.error("写真を保存できませんでした: \(error.localizedDescription)")
            return nil
        }
    }
}
