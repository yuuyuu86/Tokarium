import Foundation

/// 取得値の種類。利用枠の消費率をトークン数として扱わない。
enum MeasureKind: String, Codable {
    case measured   // 利用記録に記載されたトークン数
    case estimated  // 文字数などからの推定値
    case quota      // 利用枠の消費率（通貨にしない）

    var label: String {
        switch self {
        case .measured: return String(localized: "実測")
        case .estimated: return String(localized: "推定")
        case .quota: return String(localized: "利用枠")
        }
    }
}

/// 通貨換算（確定: 重み付き換算）。
enum CurrencyRule {
    static let tokensPerCoin = 10_000.0
    static let inputWeight = 1.0
    static let outputWeight = 1.0
    static let cacheWriteWeight = 0.25
    static let cacheReadWeight = 0.1
}

struct TokenBreakdown: Codable, Equatable {
    /// キャッシュを除く入力トークン。
    var input: Int64 = 0
    /// 出力トークン（推論トークンを含む）。
    var output: Int64 = 0
    var cacheWrite: Int64 = 0
    var cacheRead: Int64 = 0

    var total: Int64 { input + output + cacheWrite + cacheRead }

    var weighted: Double {
        Double(input) * CurrencyRule.inputWeight
            + Double(output) * CurrencyRule.outputWeight
            + Double(cacheWrite) * CurrencyRule.cacheWriteWeight
            + Double(cacheRead) * CurrencyRule.cacheReadWeight
    }

    var isEmpty: Bool { total == 0 }

    static func + (a: TokenBreakdown, b: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(input: a.input + b.input, output: a.output + b.output,
                       cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }
}

struct SourceTotals: Codable, Equatable {
    var tokens = TokenBreakdown()
    var records = 0
    var lastRecordAt: Date?
    /// 通貨に換算した重み付きトークン。
    var creditedWeighted: Double = 0
    /// 推定値で通貨に含めなかった重み付きトークン。
    var uncreditedWeighted: Double = 0
}

struct QuotaWindow: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Date?
}

struct QuotaInfo: Codable, Equatable {
    var primary: QuotaWindow?
    var secondary: QuotaWindow?
    var plan: String?
    var observedAt: Date
}

/// 追記型ファイルをどこまで読んだか。
struct FileState: Codable, Equatable {
    var offset: UInt64 = 0
    var size: UInt64 = 0
    var modified: Date = .distantPast
}

/// 通貨付与の帳簿。会話本文や認証情報は含めない。
/// 保存するのは件数・時刻・取得元・重複判定用ID・トークン数のみ。
struct UsageLedger: Codable {
    var startDate: Date
    var seenKeys: Set<String> = []
    var files: [String: FileState] = [:]
    /// Codex: セッションごとに最後に見た累計トークン（重み付き前の内訳）。
    var codexSessionTotals: [String: TokenBreakdown] = [:]
    var ollamaLastRowID: Int64 = 0
    var sources: [String: SourceTotals] = [:]
    var quotas: [String: QuotaInfo] = [:]

    var creditedWeighted: Double {
        sources.values.reduce(0) { $0 + $1.creditedWeighted }
    }

    var coinsEarned: Int { Int(creditedWeighted / CurrencyRule.tokensPerCoin) }
}

enum SourceStatus: Equatable {
    case disabled
    case notFound
    case ok
    case error(message: String, hint: String)

    var label: String {
        switch self {
        case .disabled: return String(localized: "無効")
        case .notFound: return String(localized: "見つかりません")
        case .ok: return String(localized: "読み取り中")
        case .error: return String(localized: "読み取りエラー")
        }
    }
}

struct SourceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: MeasureKind
    /// 読み取る場所（表示用）。
    let locations: [String]
    /// 読み取る内容の説明。
    let reads: String
    var experimental = false
}

/// Mac内の記録からは読み取れない対応元（理由を表示する）。
struct UnsupportedSource: Identifiable {
    let id: String
    let name: String
    let reason: String
}

enum UnsupportedSources {
    static let all: [UnsupportedSource] = [
        UnsupportedSource(id: "chatgpt-desktop", name: String(localized: "ChatGPT デスクトップ"),
                          reason: String(localized: "会話データが暗号化されて保存され、トークン数も記録されないため読み取れません。")),
        UnsupportedSource(id: "claude-desktop-chat", name: String(localized: "Claude デスクトップ（チャット）"),
                          reason: String(localized: "チャットのトークン数はMac内に残りません。Claude デスクトップの Cowork と Code は対応しています。")),
        UnsupportedSource(id: "cursor", name: "Cursor",
                          reason: String(localized: "トークン数がMac内に記録されないため読み取れません。")),
        UnsupportedSource(id: "web", name: String(localized: "ChatGPT／Claude のWeb版・他の端末"),
                          reason: String(localized: "このMacに記録が残らないため集計できません。")),
    ]
}

struct ScanSnapshot {
    var ledger: UsageLedger
    var statuses: [String: SourceStatus]
    var scannedAt: Date
}
