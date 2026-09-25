import Foundation

/// 読み取り機能が記録を報告する窓口。付与開始前の記録と重複を除外する。
final class ScanContext {
    var ledger: UsageLedger
    let includeEstimated: Bool
    let fileManager = FileManager.default
    let home: URL

    init(ledger: UsageLedger, includeEstimated: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.ledger = ledger
        self.includeEstimated = includeEstimated
        self.home = home
    }

    /// 記録1件を報告する。`key` が既に見たものなら無視する。
    /// - Returns: 新たに計上したか
    @discardableResult
    func record(source: SourceInfo, key: String?, date: Date?, tokens: TokenBreakdown) -> Bool {
        // 時刻が不明な記録は付与しない（開始前の利用を含めないため）
        guard let date, date >= ledger.startDate else { return false }
        // 整理済みの期間の記録は数えない（整理したIDで二重に数えないため）
        if let pruned = ledger.prunedBefore, date < pruned { return false }
        guard !tokens.isEmpty else { return false }
        if let key {
            guard ledger.seen[key] == nil else { return false }
            ledger.seen[key] = date
        }
        var totals = ledger.sources[source.id] ?? SourceTotals()
        totals.tokens = totals.tokens + tokens
        totals.records += 1
        if totals.lastRecordAt.map({ date > $0 }) ?? true { totals.lastRecordAt = date }
        let credit = source.kind == .measured || (source.kind == .estimated && includeEstimated)
        if credit {
            totals.creditedWeighted += tokens.weighted
            ledger.daily[DayKey.key(date), default: [:]][source.id, default: 0] += tokens.weighted
        } else {
            totals.uncreditedWeighted += tokens.weighted
        }
        ledger.sources[source.id] = totals
        return true
    }

    // MARK: ファイル走査

    /// ディレクトリ以下から、付与開始後に更新された拡張子一致のファイルを列挙する。
    func files(under root: URL, ext: String) -> [URL] {
        var result: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let e = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return []
        }
        for case let url as URL in e {
            guard url.pathExtension == ext else { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            // 付与開始より前に最後に更新されたファイルには、対象の記録がない
            if let m = v.contentModificationDate, m < ledger.startDate { continue }
            result.append(url)
        }
        return result
    }

    func exists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
    }

    /// 追記型ファイル（JSONL）の未読部分を行単位で返す。途中の行は次回に回す。
    func readNewLines(_ url: URL, filter: Data? = nil, _ body: (Data) -> Void) {
        let path = url.path
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return }
        let modified = attrs[.modificationDate] as? Date ?? Date()
        var state = ledger.files[path] ?? FileState()
        if size < state.offset { state.offset = 0 } // 書き直された
        if size == state.offset && modified == state.modified { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return }
            guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
            let complete = data[data.startIndex...lastNewline]
            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let filter, line.range(of: filter) == nil { continue }
                body(Data(line))
            }
            state.offset += UInt64(complete.count)
            state.size = size
            state.modified = modified
            ledger.files[path] = state
        } catch {
            return
        }
    }

    /// 丸ごと書き直されるファイルが前回から変わったか。変わっていれば記録して true。
    func fileChanged(_ url: URL) -> Bool {
        let path = url.path
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return false }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attrs[.modificationDate] as? Date ?? Date()
        let old = ledger.files[path]
        if old?.size == size && old?.modified == modified { return false }
        ledger.files[path] = FileState(offset: size, size: size, modified: modified)
        return true
    }
}

enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func int(_ v: Any?) -> Int64 {
        switch v {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s) ?? 0
        default: return 0
        }
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ v: Any?) -> Date? {
        switch v {
        case let s as String:
            return isoFrac.date(from: s) ?? iso.date(from: s)
        case let n as NSNumber:
            let d = n.doubleValue
            // ミリ秒/秒の両方に対応
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        default:
            return nil
        }
    }
}

extension Data {
    static func utf8(_ s: String) -> Data { Data(s.utf8) }
}
