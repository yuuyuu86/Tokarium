import Foundation
import SQLite3

/// 読み取り専用の最小限のSQLiteラッパー。
final class SQLiteReader {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let uri = "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + "?mode=ro"
        let rc = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw ReaderError.unreadable("データベースを開けませんでした（\(rc)）")
        }
        sqlite3_busy_timeout(handle, 2000)
        db = handle
    }

    deinit { sqlite3_close(db) }

    enum Value {
        case int(Int64), double(Double), text(String), null

        var int: Int64 {
            switch self {
            case .int(let v): return v
            case .double(let v): return Int64(v)
            case .text(let s): return Int64(s) ?? 0
            case .null: return 0
            }
        }
        var double: Double? {
            switch self {
            case .int(let v): return Double(v)
            case .double(let v): return v
            case .text(let s): return Double(s)
            case .null: return nil
            }
        }
        var text: String? {
            switch self {
            case .text(let s): return s
            case .int(let v): return String(v)
            case .double(let v): return String(v)
            case .null: return nil
            }
        }
    }

    func query(_ sql: String, _ args: [Int64] = [], row: ([Value]) -> Bool) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ReaderError.unsupportedFormat(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), a) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw ReaderError.unreadable(String(cString: sqlite3_errmsg(db))) }
            var values: [Value] = []
            for c in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: values.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: values.append(.double(sqlite3_column_double(stmt, c)))
                case SQLITE_NULL: values.append(.null)
                default:
                    if let p = sqlite3_column_text(stmt, c) { values.append(.text(String(cString: p))) } else { values.append(.null) }
                }
            }
            if !row(values) { break }
        }
    }
}

enum ReaderError: Error {
    case unreadable(String)
    case unsupportedFormat(String)
    case permissionDenied(String)
}
