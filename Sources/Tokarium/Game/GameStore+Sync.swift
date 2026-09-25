import Foundation

// MARK: - iCloud Drive で同期

extension GameStore {
    /// iCloud Drive の中の Tokarium フォルダ（iCloud Drive が使えなければ nil）。
    static var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Tokarium", isDirectory: true)
    }

    /// 同期を始める。iCloud Drive に新しい水槽があればそれを使い、なければこの Mac の水槽を置く。
    func startICloudSync() {
        guard let folder = Self.iCloudFolder else {
            settings.iCloudSync = false
            toast = String(localized: "iCloud Drive が見つかりません。システム設定で iCloud Drive をオンにしてください")
            return
        }
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("earned"), withIntermediateDirectories: true)
        lastPulledModified = nil
        if pullFromICloud() {
            toast = String(localized: "iCloud Drive の水槽を読み込みました")
        } else {
            pushToICloud()
            toast = String(localized: "この Mac の水槽を iCloud Drive に置きました")
        }
    }

    /// 他の Mac が保存した新しい水槽があれば読み込む。読み込んだら true。
    @discardableResult
    func pullFromICloud() -> Bool {
        guard let folder = Self.iCloudFolder else { return false }
        // ほかの Mac のコインは1分に1回だけ数え直す
        if lastEarnedRefreshAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true {
            lastEarnedRefreshAt = Date()
            refreshOtherMacsEarned(folder)
        }
        let url = folder.appendingPathComponent("game.json")
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              modified != lastPulledModified else { return false }
        lastPulledModified = modified
        guard let data = try? Data(contentsOf: url), let remote = try? JSONDecoder.tokarium.decode(GameState.self, from: data),
              remote.savedBy != settings.machineID, let remoteSaved = remote.savedAt,
              remoteSaved > (state.savedAt ?? .distantPast) else { return false }
        // 通貨の付与開始日時はこの Mac のものを使う（この Mac の利用記録の基準）
        let createdAt = state.createdAt
        state = remote
        state.createdAt = min(createdAt, remote.createdAt)
        write(state, to: "game.json")
        AppLog.info("iCloud Drive から水槽を読み込みました")
        return true
    }

    func pushToICloud() {
        guard let folder = Self.iCloudFolder else { return }
        lastPushedAt = Date()
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("earned"), withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("game.json")
            try JSONEncoder.tokarium.encode(state).write(to: url, options: .atomic)
            lastPulledModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            // この Mac で得たコイン（ほかの Mac の残高に足される）
            let earned = ["coins": ledger.coinsEarned]
            try JSONEncoder.tokarium.encode(earned).write(to: folder.appendingPathComponent("earned/\(settings.machineID).json"), options: .atomic)
        } catch {
            AppLog.error("iCloud Drive に保存できませんでした: \(error.localizedDescription)")
        }
    }

    func refreshOtherMacsEarned(_ folder: URL) {
        let dir = folder.appendingPathComponent("earned")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        otherMacsEarned = files.filter { $0.pathExtension == "json" && $0.deletingPathExtension().lastPathComponent != settings.machineID }
            .compactMap { try? JSONDecoder.tokarium.decode([String: Int].self, from: Data(contentsOf: $0))["coins"] }
            .reduce(0, +)
    }
}
