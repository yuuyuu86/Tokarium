import AppKit
import SwiftUI

/// 操作パネルを除いた水槽だけの写真を撮る。
@MainActor
enum Snapshot {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Tokarium", isDirectory: true)
    }

    /// いまの水槽を画像にする（操作パネルなし）。
    static func render(store: GameStore, size: CGSize, scale: CGFloat = 2, nameplate: Bool = true) -> CGImage? {
        let tank = store.state.tank
        let style = store.style
        let engine = store.engine
        let ambient = store.settings.timeOfDay ? Ambient.at(Date()) : .day
        let treasure = store.state.treasureX
        let favorite = nameplate ? store.favoriteFish : nil
        let view = ZStack(alignment: .bottomLeading) {
            Canvas { ctx, size in
                style.drawBackground(&ctx, size: size, tank: tank)
                style.drawLive(&ctx, size: size, tank: tank, engine: engine, selected: favorite?.id, treasureX: treasure, ambient: ambient)
            }
            if let f = favorite {
                // 主役の魚の名札
                HStack(spacing: 10) {
                    FishIcon(fish: f).frame(width: 44, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("♥ \(f.name)").font(.pixel(.headline)).foregroundStyle(PixelPalette.text)
                        Text("\(f.species.name)・\(f.stage.label)・\(Int(f.ageDays()))日齢").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    }
                }
                .padding(12)
                .background(PixelFrame(fill: PixelPalette.deep.opacity(0.9), border: PixelPalette.sand, step: 2))
                .padding(16)
                .environment(store)
            }
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// いまの水槽を画像にして、ピクチャ/Tokarium に保存し、クリップボードにも入れる。
    @discardableResult
    static func take(store: GameStore, size: CGSize) -> URL? {
        guard let cg = render(store: store, size: size) else { return nil }
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
