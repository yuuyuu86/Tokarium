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
    /// 重み付きトークンいくつで1コインか。
    static let tokensPerCoin = 500_000.0
    /// 以前のレート。レートを変える前に得たコインは、このレートのまま残す。
    static let legacyTokensPerCoin = 10_000.0
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
    /// 得たコイン。付与したときのレートで換算して足していく（レートを変えても過去の分は変わらない）。
    var creditedCoins: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try c.decodeIfPresent(TokenBreakdown.self, forKey: .tokens) ?? TokenBreakdown()
        records = try c.decodeIfPresent(Int.self, forKey: .records) ?? 0
        lastRecordAt = try c.decodeIfPresent(Date.self, forKey: .lastRecordAt)
        creditedWeighted = try c.decodeIfPresent(Double.self, forKey: .creditedWeighted) ?? 0
        uncreditedWeighted = try c.decodeIfPresent(Double.self, forKey: .uncreditedWeighted) ?? 0
        // レートを変える前のデータは、以前のレートで換算した分を引き継ぐ
        creditedCoins = try c.decodeIfPresent(Double.self, forKey: .creditedCoins)
            ?? creditedWeighted / CurrencyRule.legacyTokensPerCoin
    }
}

struct RecentUse: Codable, Equatable {
    var date: Date
    var tokens: Int64
}

/// Claude の5時間枠の推定（ccusage と同じ考え方: 最初の応答の時刻を1時間単位に切り下げて5時間）。
struct ClaudeWindowEstimate: Equatable {
    var start: Date
    var end: Date
    var tokens: Int64
    var messages: Int

    static let length: TimeInterval = 5 * 3600

    static func current(from recent: [String: RecentUse], now: Date = Date(), calendar: Calendar = .current) -> ClaudeWindowEstimate? {
        let events = recent.values.sorted { $0.date < $1.date }
        var block: ClaudeWindowEstimate?
        for e in events {
            if let b = block, e.date < b.end {
                block?.tokens += e.tokens
                block?.messages += 1
            } else {
                let start = calendar.dateInterval(of: .hour, for: e.date)?.start ?? e.date
                block = ClaudeWindowEstimate(start: start, end: start.addingTimeInterval(length), tokens: e.tokens, messages: 1)
            }
        }
        guard let b = block, now < b.end else { return nil }
        return b
    }
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
    /// 重複判定用のID → その記録の日時（古いものは定期的に整理する）。
    var seen: [String: Date] = [:]
    /// ここより古い記録は整理済みなので数えない（整理したIDで二重に数えないため）。
    var prunedBefore: Date?
    var lastPrunedAt: Date?
    /// Codex: セッションごとの最後の記録日時（整理に使う）。
    var codexSessionUpdated: [String: Date] = [:]
    var files: [String: FileState] = [:]
    /// Codex: セッションごとに最後に見た累計トークン（重み付き前の内訳）。
    var codexSessionTotals: [String: TokenBreakdown] = [:]
    var ollamaLastRowID: Int64 = 0
    var sources: [String: SourceTotals] = [:]
    var quotas: [String: QuotaInfo] = [:]
    /// 日ごと・取得元ごとの、コインに換算した重み付きトークン（日付はその Mac の時刻）。
    var daily: [String: [String: Double]] = [:]
    /// 日ごと・取得元ごとの、得たコイン（付与したときのレートで換算）。
    var dailyCoins: [String: [String: Double]] = [:]
    /// Claude の最近の応答（5時間枠の推定に使う。24時間より古いものは消す）。応答ID → 時刻とトークン数。
    var claudeRecent: [String: RecentUse] = [:]
    /// Claude の利用上限に達したと記録されたときの、リセット予定時刻。
    var claudeLimitResetAt: Date?

    init(startDate: Date) { self.startDate = startDate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decode(Date.self, forKey: .startDate)
        seen = try c.decodeIfPresent([String: Date].self, forKey: .seen) ?? [:]
        // 以前の形式（日時なし）は、読み込んだ時点の日時で引き継ぐ
        struct Legacy: Decodable { var seenKeys: Set<String>? }
        if seen.isEmpty, let old = try? Legacy(from: decoder).seenKeys {
            let now = Date()
            for k in old { seen[k] = now }
        }
        prunedBefore = try c.decodeIfPresent(Date.self, forKey: .prunedBefore)
        lastPrunedAt = try c.decodeIfPresent(Date.self, forKey: .lastPrunedAt)
        codexSessionUpdated = try c.decodeIfPresent([String: Date].self, forKey: .codexSessionUpdated) ?? [:]
        files = try c.decodeIfPresent([String: FileState].self, forKey: .files) ?? [:]
        codexSessionTotals = try c.decodeIfPresent([String: TokenBreakdown].self, forKey: .codexSessionTotals) ?? [:]
        ollamaLastRowID = try c.decodeIfPresent(Int64.self, forKey: .ollamaLastRowID) ?? 0
        sources = try c.decodeIfPresent([String: SourceTotals].self, forKey: .sources) ?? [:]
        quotas = try c.decodeIfPresent([String: QuotaInfo].self, forKey: .quotas) ?? [:]
        daily = try c.decodeIfPresent([String: [String: Double]].self, forKey: .daily) ?? [:]
        dailyCoins = try c.decodeIfPresent([String: [String: Double]].self, forKey: .dailyCoins)
            ?? daily.mapValues { $0.mapValues { $0 / CurrencyRule.legacyTokensPerCoin } }
        claudeRecent = try c.decodeIfPresent([String: RecentUse].self, forKey: .claudeRecent) ?? [:]
        claudeLimitResetAt = try c.decodeIfPresent(Date.self, forKey: .claudeLimitResetAt)
    }

    /// 記録を残す日数。
    static let retentionDays: Double = 60

    /// 古い重複判定用のIDや読み取り位置を整理する（1日1回まで）。
    mutating func pruneIfNeeded(now: Date = Date(), fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        if let last = lastPrunedAt, now.timeIntervalSince(last) < 86400 { return }
        lastPrunedAt = now
        let cutoff = now.addingTimeInterval(-Self.retentionDays * 86400)
        guard cutoff > startDate else { return }
        prunedBefore = max(prunedBefore ?? cutoff, cutoff)
        seen = seen.filter { $0.value >= cutoff }
        files = files.filter { fileExists($0.key) && $0.value.modified >= cutoff }
        let staleSessions = Set(codexSessionUpdated.filter { $0.value < cutoff }.keys)
        codexSessionUpdated = codexSessionUpdated.filter { !staleSessions.contains($0.key) }
        codexSessionTotals = codexSessionTotals.filter { !staleSessions.contains($0.key) }
        let cutoffDay = DayKey.key(now.addingTimeInterval(-400 * 86400))
        daily = daily.filter { $0.key >= cutoffDay }
        dailyCoins = dailyCoins.filter { $0.key >= cutoffDay }
    }

    /// その日にAIで得たコイン。
    func coins(on day: String) -> Double {
        (dailyCoins[day] ?? [:]).values.reduce(0, +)
    }

    /// 取得元ごとの、これまでに得たコイン。
    func coins(from sourceIDs: [String]) -> Int {
        Int(sourceIDs.reduce(0) { $0 + (sources[$1]?.creditedCoins ?? 0) })
    }

    var creditedWeighted: Double {
        sources.values.reduce(0) { $0 + $1.creditedWeighted }
    }

    var coinsEarned: Int { Int(sources.values.reduce(0) { $0 + $1.creditedCoins }) }
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
