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
