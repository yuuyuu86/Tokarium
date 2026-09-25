import Foundation

// MARK: - バックアップと復元

/// 書き出すデータ一式。
struct TokariumBackup: Codable {
    var format = 1
    var exportedAt: Date
    var appVersion: String
    var game: GameState
    var settings: AppSettings
    var ledger: UsageLedger
}

extension GameStore {
    func makeBackup() -> TokariumBackup {
        save()
        return TokariumBackup(exportedAt: Date(), appVersion: Diagnostics.appVersion, game: state, settings: settings, ledger: ledger)
    }

    func exportBackup(to url: URL) throws {
        let data = try JSONEncoder.tokarium.encode(makeBackup())
        try data.write(to: url, options: .atomic)
        toast = String(localized: "バックアップを書き出しました")
    }

    /// バックアップから復元する。この Mac の識別子と、この Mac でだけ意味のある設定は残す。
    func importBackup(from url: URL) throws {
        let backup = try JSONDecoder.tokarium.decode(TokariumBackup.self, from: Data(contentsOf: url))
        var newSettings = backup.settings
        newSettings.machineID = settings.machineID
        newSettings.displayMode = settings.displayMode
        newSettings.desktopScreens = settings.desktopScreens
        state = backup.game
        state.lastSimulatedAt = min(state.lastSimulatedAt, Date())
        engine.reset()
        settings = newSettings
        ledger = backup.ledger
        Task { await scanner.replaceLedger(backup.ledger) }
        save()
        toast = String(localized: "バックアップから復元しました")
    }
}

// MARK: - 自動バックアップ

/// 1日1回、水槽のデータを自動で保存し、数世代残す。
enum AutoBackup {
    static let keep = 7
    static let interval: TimeInterval = 24 * 3600

    struct Item: Identifiable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    static func folder(in dir: URL) -> URL { dir.appendingPathComponent("backups", isDirectory: true) }

    /// 新しい順。
    static func list(in dir: URL) -> [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(in: dir), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("auto-") && $0.pathExtension == "json" }
            .compactMap { url in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Item(url: url, date: $0) }
            }
            .sorted { $0.date > $1.date }
    }
}

extension GameStore {
    /// 前の自動バックアップから1日たっていれば、新しく保存して古いものを消す。
    func autoBackupIfNeeded(now: Date = Date(), force: Bool = false) {
        let items = AutoBackup.list(in: dir)
        if !force, let latest = items.first, now.timeIntervalSince(latest.date) < AutoBackup.interval { return }
        let folder = AutoBackup.folder(in: dir)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = folder.appendingPathComponent("auto-\(f.string(from: now)).json")
            try JSONEncoder.tokarium.encode(makeBackup()).write(to: url, options: .atomic)
            for old in AutoBackup.list(in: dir).dropFirst(AutoBackup.keep) { try? FileManager.default.removeItem(at: old.url) }
        } catch {
            AppLog.error("自動バックアップに失敗しました: \(error.localizedDescription)")
        }
    }

    var autoBackups: [AutoBackup.Item] { AutoBackup.list(in: dir) }
}
