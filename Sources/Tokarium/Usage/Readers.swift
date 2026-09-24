import Foundation

/// AIアプリごとの読み取り機能。対応元はここに追加していく。
protocol UsageReader: Sendable {
    var info: SourceInfo { get }
    /// 記録が置かれる場所。どれかが存在すれば「検出」とみなす。
    func roots(_ ctx: ScanContext) -> [URL]
    func scan(_ ctx: ScanContext) throws
}

extension UsageReader {
    func isDetected(_ ctx: ScanContext) -> Bool { roots(ctx).contains { ctx.exists($0) } }
}

enum UsageReaders {
    static let all: [UsageReader] = [
        ClaudeCodeReader(),
        ClaudeDesktopCoworkReader(),
        CodexReader(),
        GeminiFamilyReader.gemini,
        GeminiFamilyReader.qwen,
        OpenCodeReader(),
        CopilotCLIReader(),
        OllamaReader(),
    ]
}

private func env(_ key: String) -> String? {
    guard let v = ProcessInfo.processInfo.environment[key], !v.isEmpty else { return nil }
    return v
}

// MARK: - Claude（Claude Code / Claude デスクトップの Code タブ）

/// Claude Code 形式の JSONL の1行を読む。Claude Code と Cowork で共通。
private func recordClaudeLine(_ line: Data, source: SourceInfo, ctx: ScanContext) {
    guard let obj = JSON.object(line),
          obj["type"] as? String == "assistant",
          let message = obj["message"] as? [String: Any],
          let usage = message["usage"] as? [String: Any] else { return }
    let tokens = TokenBreakdown(
        input: JSON.int(usage["input_tokens"]),
        output: JSON.int(usage["output_tokens"]),
        cacheWrite: JSON.int(usage["cache_creation_input_tokens"]),
        cacheRead: JSON.int(usage["cache_read_input_tokens"]))
    // 同じ応答はストリーミングや複数アプリで何度も記録されるため、
    // 応答IDとリクエストIDで重複を除く（Claude系の取得元で共通の名前空間）
    let messageID = message["id"] as? String
    let requestID = obj["requestId"] as? String
    let key: String?
    if let messageID {
        key = "claude:\(messageID):\(requestID ?? "")"
    } else if let uuid = obj["uuid"] as? String {
        key = "claude-uuid:\(uuid)"
    } else {
        key = nil
    }
    ctx.record(source: source, key: key, date: JSON.date(obj["timestamp"]), tokens: tokens)
}

struct ClaudeCodeReader: UsageReader {
    let info = SourceInfo(
        id: "claude-code", name: "Claude Code", kind: .measured,
        locations: ["~/.claude/projects", "~/.config/claude/projects"],
        reads: String(localized: "会話記録（JSONL）のうち、応答ごとのトークン数・時刻・応答IDのみ"))

    func roots(_ ctx: ScanContext) -> [URL] {
        var r: [URL] = []
        if let dirs = env("CLAUDE_CONFIG_DIR") {
            for d in dirs.split(separator: ",") {
                r.append(URL(fileURLWithPath: String(d).trimmingCharacters(in: .whitespaces)).appendingPathComponent("projects"))
            }
        }
        r.append(ctx.home.appendingPathComponent(".config/claude/projects"))
        r.append(ctx.home.appendingPathComponent(".claude/projects"))
        return r
    }

    func scan(_ ctx: ScanContext) throws {
        for root in roots(ctx) where ctx.exists(root) {
            for file in ctx.files(under: root, ext: "jsonl") {
                ctx.readNewLines(file, filter: .utf8("\"usage\"")) { recordClaudeLine($0, source: info, ctx: ctx) }
            }
        }
    }
}

struct ClaudeDesktopCoworkReader: UsageReader {
    let info = SourceInfo(
        id: "claude-desktop-cowork", name: String(localized: "Claude デスクトップ（Cowork）"), kind: .measured,
        locations: ["~/Library/Application Support/Claude/local-agent-mode-sessions"],
        reads: String(localized: "Cowork セッションの記録（JSONL）のうち、応答ごとのトークン数・時刻・応答IDのみ"))

    func roots(_ ctx: ScanContext) -> [URL] {
        [ctx.home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")]
    }

    func scan(_ ctx: ScanContext) throws {
        for root in roots(ctx) where ctx.exists(root) {
            // 各セッション内の .claude/projects 以下が Claude Code と同じ形式
            for file in ctx.files(under: root, ext: "jsonl") where file.path.contains("/.claude/projects/") {
                ctx.readNewLines(file, filter: .utf8("\"usage\"")) { recordClaudeLine($0, source: info, ctx: ctx) }
            }
        }
    }
}

// MARK: - Codex（CLI・デスクトップ共通）

struct CodexReader: UsageReader {
    let info = SourceInfo(
        id: "codex", name: String(localized: "Codex（CLI・デスクトップ）"), kind: .measured,
        locations: ["~/.codex/sessions", "~/.codex/archived_sessions"],
        reads: String(localized: "セッション記録（JSONL）のうち、トークン数・時刻・セッションID・利用枠の消費率のみ"))

    private func codexHome(_ ctx: ScanContext) -> URL {
        env("CODEX_HOME").map { URL(fileURLWithPath: $0) } ?? ctx.home.appendingPathComponent(".codex")
    }

    func roots(_ ctx: ScanContext) -> [URL] {
        let h = codexHome(ctx)
        return [h.appendingPathComponent("sessions"), h.appendingPathComponent("archived_sessions")]
    }

    func scan(_ ctx: ScanContext) throws {
        for root in roots(ctx) where ctx.exists(root) {
            for file in ctx.files(under: root, ext: "jsonl") {
                let sessionID = Self.sessionID(file)
                ctx.readNewLines(file, filter: .utf8("token_count")) { line in
                    handle(line, sessionID: sessionID, ctx: ctx)
                }
            }
        }
    }

    /// ファイル名末尾のUUIDをセッションIDにする（archived_sessions へ移動しても同じ）。
    static func sessionID(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.count >= 36 ? String(name.suffix(36)) : name
    }

    private static func breakdown(_ u: [String: Any]) -> TokenBreakdown {
        let input = JSON.int(u["input_tokens"])
        let cached = JSON.int(u["cached_input_tokens"])
        let cacheWrite = JSON.int(u["cache_write_input_tokens"])
        // input_tokens はキャッシュ分を含む
        return TokenBreakdown(input: max(0, input - cached - cacheWrite),
                              output: JSON.int(u["output_tokens"]),
                              cacheWrite: cacheWrite, cacheRead: cached)
    }

    private func handle(_ line: Data, sessionID: String, ctx: ScanContext) {
        guard let obj = JSON.object(line),
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count" else { return }
        let date = JSON.date(obj["timestamp"])

        if let limits = payload["rate_limits"] as? [String: Any], let date {
            updateQuota(limits, date: date, ctx: ctx)
        }

        guard let info = payload["info"] as? [String: Any],
              let totalDict = info["total_token_usage"] as? [String: Any] else { return }
        let total = Self.breakdown(totalDict)
        let baseline = ctx.ledger.codexSessionTotals[sessionID] ?? TokenBreakdown()
        ctx.ledger.codexSessionTotals[sessionID] = TokenBreakdown(
            input: max(total.input, baseline.input), output: max(total.output, baseline.output),
            cacheWrite: max(total.cacheWrite, baseline.cacheWrite), cacheRead: max(total.cacheRead, baseline.cacheRead))
        // 累計の増えた分だけを計上する。同じ記録を読み直しても増えない。
        guard total.total > baseline.total else { return }
        let delta = TokenBreakdown(input: max(0, total.input - baseline.input),
                                   output: max(0, total.output - baseline.output),
                                   cacheWrite: max(0, total.cacheWrite - baseline.cacheWrite),
                                   cacheRead: max(0, total.cacheRead - baseline.cacheRead))
        ctx.record(source: self.info, key: nil, date: date, tokens: delta)
    }

    private func updateQuota(_ limits: [String: Any], date: Date, ctx: ScanContext) {
        if let old = ctx.ledger.quotas[info.id], old.observedAt > date { return }
        func window(_ v: Any?) -> QuotaWindow? {
            guard let d = v as? [String: Any], let p = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return QuotaWindow(usedPercent: p, windowMinutes: (d["window_minutes"] as? NSNumber)?.intValue, resetsAt: reset)
        }
        ctx.ledger.quotas[info.id] = QuotaInfo(primary: window(limits["primary"]), secondary: window(limits["secondary"]),
                                               plan: limits["plan_type"] as? String, observedAt: date)
    }
}

// MARK: - Gemini CLI / Qwen Code（同じ記録形式）

struct GeminiFamilyReader: UsageReader {
    let info: SourceInfo
    let dirName: String

    static let gemini = GeminiFamilyReader(
        info: SourceInfo(id: "gemini-cli", name: "Gemini CLI", kind: .measured,
                         locations: ["~/.gemini/tmp/*/chats"],
                         reads: String(localized: "セッション記録（JSON）のうち、応答ごとのトークン数・時刻・IDのみ")),
        dirName: ".gemini")
    static let qwen = GeminiFamilyReader(
        info: SourceInfo(id: "qwen-code", name: "Qwen Code", kind: .measured,
                         locations: ["~/.qwen/tmp/*/chats"],
                         reads: String(localized: "セッション記録（JSON）のうち、応答ごとのトークン数・時刻・IDのみ")),
        dirName: ".qwen")

    func roots(_ ctx: ScanContext) -> [URL] { [ctx.home.appendingPathComponent("\(dirName)/tmp")] }

    func scan(_ ctx: ScanContext) throws {
        for root in roots(ctx) where ctx.exists(root) {
            for file in ctx.files(under: root, ext: "json") where file.deletingLastPathComponent().lastPathComponent == "chats" {
                guard ctx.fileChanged(file), let data = try? Data(contentsOf: file), let obj = JSON.object(data) else { continue }
                let sessionID = obj["sessionId"] as? String ?? file.lastPathComponent
                for case let m as [String: Any] in obj["messages"] as? [Any] ?? [] {
                    guard let t = m["tokens"] as? [String: Any] else { continue }
                    let cached = JSON.int(t["cached"])
                    let tokens = TokenBreakdown(
                        input: max(0, JSON.int(t["input"]) - cached) + JSON.int(t["tool"]),
                        output: JSON.int(t["output"]) + JSON.int(t["thoughts"]),
                        cacheWrite: 0, cacheRead: cached)
                    let id = m["id"] as? String ?? "\(m["timestamp"] ?? "")"
                    ctx.record(source: info, key: "\(info.id):\(sessionID):\(id)", date: JSON.date(m["timestamp"]), tokens: tokens)
                }
            }
        }
    }
}

// MARK: - OpenCode

struct OpenCodeReader: UsageReader {
    let info = SourceInfo(
        id: "opencode", name: "OpenCode", kind: .measured,
        locations: ["~/.local/share/opencode"],
        reads: String(localized: "メッセージ記録のうち、トークン数・時刻・メッセージIDのみ"))

    func roots(_ ctx: ScanContext) -> [URL] {
        let base = env("XDG_DATA_HOME").map { URL(fileURLWithPath: $0) } ?? ctx.home.appendingPathComponent(".local/share")
        return [base.appendingPathComponent("opencode")]
    }

    private func handleMessage(_ m: [String: Any], fallbackID: String?, ctx: ScanContext) {
        guard m["role"] as? String == "assistant", let t = m["tokens"] as? [String: Any] else { return }
        let time = m["time"] as? [String: Any]
        // 応答が完了してから計上する（途中のトークン数で確定させない）
        guard time?["completed"] != nil else { return }
        let cache = t["cache"] as? [String: Any]
        let tokens = TokenBreakdown(input: JSON.int(t["input"]),
                                    output: JSON.int(t["output"]) + JSON.int(t["reasoning"]),
                                    cacheWrite: JSON.int(cache?["write"]), cacheRead: JSON.int(cache?["read"]))
        guard let id = (m["id"] as? String) ?? fallbackID else { return }
        ctx.record(source: info, key: "opencode:\(id)", date: JSON.date(time?["created"]), tokens: tokens)
    }

    func scan(_ ctx: ScanContext) throws {
        guard let root = roots(ctx).first, ctx.exists(root) else { return }
        // 旧形式: storage/message/<session>/<message>.json
        let storage = root.appendingPathComponent("storage/message")
        if ctx.exists(storage) {
            for file in ctx.files(under: storage, ext: "json") {
                guard ctx.fileChanged(file), let data = try? Data(contentsOf: file), let m = JSON.object(data) else { continue }
                handleMessage(m, fallbackID: file.deletingPathExtension().lastPathComponent, ctx: ctx)
            }
        }
        // 新形式: opencode.db
        let dbURL = root.appendingPathComponent("opencode.db")
        let dbChanged = ctx.fileChanged(dbURL)
        let walChanged = ctx.fileChanged(root.appendingPathComponent("opencode.db-wal"))
        if ctx.exists(dbURL), dbChanged || walChanged {
            let db = try SQLiteReader(path: dbURL.path)
            try db.query("SELECT id, data FROM message") { row in
                if let text = row[1].text, let m = JSON.object(Data(text.utf8)) {
                    handleMessage(m, fallbackID: row[0].text, ctx: ctx)
                }
                return true
            }
        }
    }
}

// MARK: - GitHub Copilot CLI（試験対応）

struct CopilotCLIReader: UsageReader {
    let info = SourceInfo(
        id: "copilot-cli", name: "GitHub Copilot CLI", kind: .measured,
        locations: ["~/.copilot/session-state"],
        reads: String(localized: "セッションのイベント記録（JSONL）のうち、トークン数・時刻・イベントIDのみ"),
        experimental: true)

    func roots(_ ctx: ScanContext) -> [URL] { [ctx.home.appendingPathComponent(".copilot/session-state")] }

    /// イベント内のどこかにあるトークン数の組を探す（バージョンで形式が変わるため）。
    private static func findUsage(_ v: Any, depth: Int = 0) -> TokenBreakdown? {
        guard depth < 6 else { return nil }
        if let d = v as? [String: Any] {
            let inKeys = ["inputTokens", "input_tokens", "prompt_tokens", "promptTokens"]
            let outKeys = ["outputTokens", "output_tokens", "completion_tokens", "completionTokens"]
            if let ik = inKeys.first(where: { d[$0] != nil }), let ok = outKeys.first(where: { d[$0] != nil }) {
                let cr = JSON.int(d["cacheReadTokens"] ?? d["cache_read_tokens"] ?? d["cached_tokens"] ?? d["cache_read_input_tokens"])
                let cw = JSON.int(d["cacheWriteTokens"] ?? d["cache_write_tokens"] ?? d["cache_creation_input_tokens"])
                return TokenBreakdown(input: max(0, JSON.int(d[ik]) - (ik == "prompt_tokens" ? cr : 0)),
                                      output: JSON.int(d[ok]), cacheWrite: cw, cacheRead: cr)
            }
            for (_, child) in d { if let u = findUsage(child, depth: depth + 1) { return u } }
        } else if let a = v as? [Any] {
            for child in a { if let u = findUsage(child, depth: depth + 1) { return u } }
        }
        return nil
    }

    func scan(_ ctx: ScanContext) throws {
        for root in roots(ctx) where ctx.exists(root) {
            for file in ctx.files(under: root, ext: "jsonl") {
                ctx.readNewLines(file, filter: .utf8("okens")) { line in
                    guard let obj = JSON.object(line), let usage = Self.findUsage(obj) else { return }
                    let id = obj["id"] as? String
                    let date = JSON.date(obj["timestamp"]) ?? JSON.date((obj["data"] as? [String: Any])?["timestamp"])
                    ctx.record(source: info, key: id.map { "copilot:\($0)" }, date: date, tokens: usage)
                }
            }
        }
    }
}

// MARK: - Ollama（推定）

struct OllamaReader: UsageReader {
    let info = SourceInfo(
        id: "ollama", name: String(localized: "Ollama（アプリ）"), kind: .estimated,
        locations: ["~/Library/Application Support/Ollama/db.sqlite"],
        reads: String(localized: "チャット履歴の文字数・時刻・行番号のみ（本文は保存しません）。4文字＝1トークンとして推定"))

    func roots(_ ctx: ScanContext) -> [URL] {
        [ctx.home.appendingPathComponent("Library/Application Support/Ollama/db.sqlite")]
    }

    func scan(_ ctx: ScanContext) throws {
        guard let url = roots(ctx).first, ctx.exists(url) else { return }
        let db = try SQLiteReader(path: url.path)
        var last = ctx.ledger.ollamaLastRowID
        let sql = """
        SELECT id, role, length(content) + length(thinking),
               (julianday(created_at) - 2440587.5) * 86400.0,
               (julianday('now') - julianday(updated_at)) * 86400.0
        FROM messages WHERE id > ? ORDER BY id
        """
        try db.query(sql, [last]) { row in
            // 書き込み中の応答は次回に回す
            if let age = row[4].double, age < 30 { return false }
            let id = row[0].int
            let chars = row[2].int
            let est = chars / 4
            let tokens = row[1].text == "assistant" ? TokenBreakdown(output: est) : TokenBreakdown(input: est)
            let date = row[3].double.map { Date(timeIntervalSince1970: $0) }
            ctx.record(source: info, key: nil, date: date, tokens: tokens)
            last = id
            return true
        }
        ctx.ledger.ollamaLastRowID = last
    }
}
