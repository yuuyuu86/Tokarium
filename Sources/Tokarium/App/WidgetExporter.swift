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
}

/// ウィジェット用に、水槽の小さな画像と状態を書き出す。
@MainActor
enum WidgetExporter {
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
                                  sick: store.state.tank.fish.filter { $0.isAlive && $0.isSick }.count)
        let folder = folder(store)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder.tokarium.encode(snap).write(to: folder.appendingPathComponent("snapshot.json"), options: .atomic)
            if let cg = Snapshot.render(store: store, size: CGSize(width: 480, height: 300), scale: 1),
               let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("tank.png"), options: .atomic)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            AppLog.error("ウィジェット用の情報を書き出せませんでした: \(error.localizedDescription)")
        }
    }
}
