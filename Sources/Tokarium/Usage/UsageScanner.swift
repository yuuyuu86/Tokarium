import Foundation

/// 利用記録を読み取り専用で走査し、帳簿を更新する。
actor UsageScanner {
    private var ledger: UsageLedger
    private let ledgerURL: URL
    nonisolated private let readers: [UsageReader]

    init(ledgerURL: URL, startDate: Date, readers: [UsageReader] = UsageReaders.all) {
        self.ledgerURL = ledgerURL
        self.readers = readers
        if let data = try? Data(contentsOf: ledgerURL),
           let loaded = try? JSONDecoder.tokarium.decode(UsageLedger.self, from: data) {
            ledger = loaded
        } else {
            ledger = UsageLedger(startDate: startDate)
        }
    }

    var currentLedger: UsageLedger { ledger }

    /// バックアップから復元した帳簿に置きかえる。
    func replaceLedger(_ new: UsageLedger) {
        ledger = new
        save()
    }

    /// 検出できた対応元のID。
    nonisolated func detectedSources() -> Set<String> {
        let ctx = ScanContext(ledger: UsageLedger(startDate: Date()), includeEstimated: false)
        return Set(readers.filter { $0.isDetected(ctx) }.map(\.info.id))
    }

    func scan(enabled: Set<String>, includeEstimated: Bool) -> ScanSnapshot {
        let ctx = ScanContext(ledger: ledger, includeEstimated: includeEstimated)
        var statuses: [String: SourceStatus] = [:]
        for reader in readers {
            let id = reader.info.id
            guard enabled.contains(id) else { statuses[id] = .disabled; continue }
            guard reader.isDetected(ctx) else { statuses[id] = .notFound; continue }
            do {
                try reader.scan(ctx)
                statuses[id] = .ok
            } catch {
                statuses[id] = Self.status(for: error)
            }
        }
        ledger = ctx.ledger
        // 24時間より古い応答は枠の推定に使わない
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        ledger.claudeRecent = ledger.claudeRecent.filter { $0.value.date > cutoff }
        ledger.pruneIfNeeded()
        save()
        return ScanSnapshot(ledger: ledger, statuses: statuses, scannedAt: Date())
    }

    private static func status(for error: Error) -> SourceStatus {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError) {
            return .error(message: String(localized: "読み取りの許可がありません。"),
                          hint: String(localized: "システム設定 ＞ プライバシーとセキュリティ ＞ フルディスクアクセス で Tokarium を許可してください。"))
        }
        switch error {
        case ReaderError.permissionDenied(let m):
            return .error(message: m, hint: String(localized: "システム設定 ＞ プライバシーとセキュリティ ＞ フルディスクアクセス で Tokarium を許可してください。"))
        case ReaderError.unsupportedFormat(let m):
            return .error(message: String(localized: "記録の形式が変わった可能性があります（\(m)）。"),
                          hint: String(localized: "Tokarium のアップデートで対応します。水槽はそのまま遊べます。"))
        case ReaderError.unreadable(let m):
            return .error(message: m, hint: String(localized: "対象のアプリを終了してから「今すぐ読み取る」を押してください。"))
        default:
            return .error(message: error.localizedDescription, hint: String(localized: "しばらくしてから「今すぐ読み取る」を押してください。"))
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.tokarium.encode(ledger)
            try data.write(to: ledgerURL, options: .atomic)
        } catch {
            AppLog.error("帳簿を保存できませんでした: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    static var tokarium: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var tokarium: JSONDecoder {
        let d = JSONDecoder()
        return d
    }
}
