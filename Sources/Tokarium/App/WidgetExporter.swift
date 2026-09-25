import AppKit
import Foundation
import WidgetKit

/// ウィジェットに見せる情報。ウィジェット側（Widget/TokariumWidget.swift）と同じ形。
struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var coins: Int
    var food: Int
    var fishCount: Int
    var maxFish: Int
    var water: String
    var waterValue: Double
    var danger: [String]
    var sick: Int
    var favorite: FavoriteInfo?
}

struct FavoriteInfo: Codable {
    var name: String
    var species: String
    var days: Int
    var condition: String
    var health: Double
    var fullness: Double
    var isAlive: Bool
}

/// ウィジェット用に、水槽の小さな画像と状態を書き出す。
@MainActor
enum WidgetExporter {
    /// ドット絵をくっきり拡大する。
    private static func scaled(_ image: CGImage, by k: Int) -> CGImage? {
        let w = image.width * k, h = image.height * k
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func folder(_ store: GameStore) -> URL { store.dir.appendingPathComponent("widget", isDirectory: true) }
    private static var lastWrite: Date?
    private static var lastDanger: [String] = []

    /// 数分おき、または危険な魚が変わったときに書き出す。
    static func update(store: GameStore, force: Bool = false) {
        let danger = store.dangerFish.map(\.name)
        let due = lastWrite.map { Date().timeIntervalSince($0) > 5 * 60 } ?? true
        guard force || due || danger != lastDanger else { return }
        lastWrite = Date()
        lastDanger = danger
        let snap = WidgetSnapshot(updatedAt: Date(), coins: store.coins, food: store.state.food, fishCount: store.livingFish.count,
                                  maxFish: store.state.tank.size.maxFish, water: WaterCondition(store.state.tank.waterQuality).label,
                                  waterValue: store.state.tank.waterQuality, danger: danger,
                                  sick: store.state.tank.fish.filter { $0.isAlive && $0.isSick }.count,
                                  favorite: store.favoriteFish.map {
                                      FavoriteInfo(name: $0.name, species: $0.species.name, days: Int($0.ageDays()), condition: $0.condition.label,
                                                   health: $0.health, fullness: $0.fullness, isAlive: $0.isAlive)
                                  })
        let folder = folder(store)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder.tokarium.encode(snap).write(to: folder.appendingPathComponent("snapshot.json"), options: .atomic)
            // 主役の魚の大きなドット絵
            let favURL = folder.appendingPathComponent("favorite.png")
            if let f = store.favoriteFish, let art = store.style.fishImage(f, frame: 0),
               let big = scaled(art.image, by: 8), let png = NSBitmapImageRep(cgImage: big).representation(using: .png, properties: [:]) {
                try png.write(to: favURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: favURL)
            }
            if let cg = Snapshot.render(store: store, size: CGSize(width: 480, height: 300), scale: 1, nameplate: false),
               let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("tank.png"), options: .atomic)
            }
            WidgetCenter.shared.reloadAllTimelines()
            SaverExporter.update(store: store)
        } catch {
            AppLog.error("ウィジェット用の情報を書き出せませんでした: \(error.localizedDescription)")
        }
    }
}
