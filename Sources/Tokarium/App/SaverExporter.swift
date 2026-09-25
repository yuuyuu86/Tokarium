import AppKit
import Foundation

/// スクリーンセーバーに渡す水槽の中身（Saver/TokariumSaver.swift と同じ形）。
struct SaverScene: Codable {
    var tank: Tank
    var timeOfDay: Bool
    var seasons: Bool
    var updatedAt: Date
}

/// スクリーンセーバー用に水槽の中身を書き出し、スクリーンセーバーを入れる。
@MainActor
enum SaverExporter {
    /// スクリーンセーバーはサンドボックスの中で動くので、その中の場所にも書く。
    private static var sandboxFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support")
    }

    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Tokarium.saver")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedURL.path) }

    static func update(store: GameStore) {
        let scene = SaverScene(tank: store.state.tank, timeOfDay: store.settings.timeOfDay, seasons: store.settings.seasons, updatedAt: Date())
        guard let data = try? JSONEncoder.tokarium.encode(scene) else { return }
        try? data.write(to: store.dir.appendingPathComponent("saver-scene.json"), options: .atomic)
        // 実際のデータ（テストでない）のときだけ、スクリーンセーバーのサンドボックスにも置く
        guard store.dir == GameStore.defaultDirectory, ProcessInfo.processInfo.environment["TOKARIUM_DATA_DIR"] == nil,
              FileManager.default.fileExists(atPath: sandboxFolder.path) else { return }
        let dir = sandboxFolder.appendingPathComponent("Tokarium", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("saver-scene.json"), options: .atomic)
    }

    /// アプリに入っているスクリーンセーバーを ~/Library/Screen Savers に入れ、設定を開く。
    static func install(store: GameStore) throws {
        guard let source = Bundle.main.url(forResource: "Tokarium", withExtension: "saver") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedURL.path) { try fm.removeItem(at: installedURL) }
        try fm.copyItem(at: source, to: installedURL)
        update(store: store)
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
