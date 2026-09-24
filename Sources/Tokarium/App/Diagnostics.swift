import AppKit
import Foundation

/// アプリのログ。`~/Library/Logs/Tokarium/tokarium.log` に書く。会話本文などは書かない。
enum AppLog {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tokarium", isDirectory: true)
    static var file: URL { directory.appendingPathComponent("tokarium.log") }
    private static let queue = DispatchQueue(label: "tokarium.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(Diagnostics.redact(message))\n"
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 1MB を超えたら古いものを残して新しく始める
            if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber, size.intValue > 1_000_000 {
                let old = directory.appendingPathComponent("tokarium.old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: file, to: old)
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? line.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    static func tail(lines: Int = 60) -> String {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}

/// 不具合の報告に使う情報を集める。送信はしない（ユーザーが内容を見てから送る）。
enum Diagnostics {
    private static let runningMarker = GameStore.defaultDirectory.appendingPathComponent(".running")
    private static let exceptionFile = AppLog.directory.appendingPathComponent("last-exception.txt")
    private static let lastCheckKey = "diagnostics.lastCrashCheck"

    struct CrashInfo {
        var date: Date
        var summary: String
    }

    /// 起動時に呼ぶ。前回が異常終了だったら、その情報を返す。
    static func startSession() -> CrashInfo? {
        let fm = FileManager.default
        let uncleanExit = fm.fileExists(atPath: runningMarker.path)
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? Date()
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        try? fm.createDirectory(at: runningMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: runningMarker.path, contents: Data())

        NSSetUncaughtExceptionHandler { exception in
            let text = "\(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.prefix(20).joined(separator: "\n")
            try? FileManager.default.createDirectory(at: AppLog.directory, withIntermediateDirectories: true)
            try? text.write(to: AppLog.directory.appendingPathComponent("last-exception.txt"), atomically: true, encoding: .utf8)
        }

        var summaries: [String] = []
        var latest: Date?
        for report in crashReports(since: lastCheck) {
            summaries.append(report.summary)
            latest = max(latest ?? report.date, report.date)
        }
        if let text = try? String(contentsOf: exceptionFile, encoding: .utf8) {
            summaries.append(text)
            try? fm.removeItem(at: exceptionFile)
        }
        guard uncleanExit || !summaries.isEmpty else { return nil }
        if summaries.isEmpty { summaries.append(String(localized: "（クラッシュレポートは見つかりませんでした。強制終了や電源断の可能性があります）")) }
        AppLog.error("前回のセッションが正常に終了しませんでした")
        return CrashInfo(date: latest ?? lastCheck, summary: summaries.joined(separator: "\n\n---\n\n"))
    }

    static func endSession() {
        try? FileManager.default.removeItem(at: runningMarker)
    }

    /// macOS が書いたクラッシュレポート（.ips）から要点を取り出す。
    static func crashReports(since: Date) -> [CrashInfo] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix("Tokarium") && $0.pathExtension == "ips" }.compactMap { url in
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date > since,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return CrashInfo(date: date, summary: summarizeIPS(text))
        }
        .sorted { $0.date > $1.date }
        .prefix(3).map { $0 }
    }

    static func summarizeIPS(_ text: String) -> String {
        // 1行目がヘッダ、残りが本体の JSON
        guard let newline = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any] else {
            return String(text.prefix(1500))
        }
        var lines: [String] = []
        if let ex = body["exception"] as? [String: Any] {
            lines.append("Exception: \(ex["type"] ?? "") \(ex["signal"] ?? "") \(ex["subtype"] ?? "")")
        }
        if let term = body["termination"] as? [String: Any], let indicator = term["indicator"] {
            lines.append("Termination: \(indicator)")
        }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "?" } ?? []
        if let threads = body["threads"] as? [[String: Any]], let crashed = threads.first(where: { $0["triggered"] as? Bool == true }),
           let frames = crashed["frames"] as? [[String: Any]] {
            for (i, f) in frames.prefix(15).enumerated() {
                let image = (f["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0] : nil } ?? "?"
                lines.append("\(i) \(image) \(f["symbol"] as? String ?? "") +\(f["symbolLocation"] ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// ホームのパスやユーザー名を伏せる。
    static func redact(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return text.replacingOccurrences(of: home, with: "~").replacingOccurrences(of: NSUserName(), with: "<user>")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    static var systemSummary: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "unknown"
        #if arch(arm64)
        arch = "Apple Silicon"
        #elseif arch(x86_64)
        arch = "Intel"
        #endif
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) / \(arch) / \(Locale.preferredLanguages.first ?? "")"
    }

    @MainActor
    static func report(store: GameStore, crash: CrashInfo?, includeLog: Bool) -> String {
        var s = """
        Tokarium \(appVersion)
        \(systemSummary)
        Style: \(store.settings.styleID) / Display: \(store.settings.displayMode.rawValue) (\(store.settings.desktopScreens.rawValue)) / FPS: \(store.settings.fps)
        Tank: level \(store.state.tank.level), fish \(store.livingFish.count) alive / \(store.state.tank.fish.count) total, decorations \(store.state.tank.decorations.count)
        Sources: \(UsageReaders.all.map { r in "\(r.info.id)=\(statusCode(store.sourceStatuses[r.info.id], enabled: store.settings.enabledSources.contains(r.info.id)))" }.joined(separator: ", "))
        """
        if let crash {
            s += "\n\n## Crash (\(crash.date.formatted(.iso8601)))\n\(redact(crash.summary))"
        }
        if includeLog {
            let log = AppLog.tail()
            if !log.isEmpty { s += "\n\n## Log\n\(log)" }
        }
        return s
    }

    private static func statusCode(_ s: SourceStatus?, enabled: Bool) -> String {
        guard enabled else { return "off" }
        switch s {
        case .ok: return "ok"
        case .notFound: return "notfound"
        case .error(let m, _): return "error(\(redact(m)))"
        case .disabled: return "off"
        case nil: return "pending"
        }
    }

    // MARK: 送り先（Info.plist で変更できる）

    static var feedbackURL: URL? {
        (Bundle.main.infoDictionary?["TKFeedbackURL"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/yuuyuu86/Tokarium/issues/new")
    }

    static var feedbackEmail: String? {
        guard let e = Bundle.main.infoDictionary?["TKFeedbackEmail"] as? String, !e.isEmpty else { return nil }
        return e
    }

    static func openIssue(title: String, body: String) {
        guard var comps = feedbackURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return }
        // URL が長すぎると開けないので本文を詰める
        comps.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: String(body.prefix(6000)))]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }

    static func openMail(subject: String, body: String) {
        guard let to = feedbackEmail else { return }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = to
        comps.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}
