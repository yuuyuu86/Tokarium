import SwiftUI

/// AIごとの利用枠。読み取れる範囲で表示する（Codex は記録の数値、Claude は推定）。
struct QuotaPanel: View {
    @Environment(GameStore.self) private var store
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            codex
            claude
            if !compact {
                Text("Gemini CLI・OpenCode・Copilot CLI・Ollama は、利用枠の情報がMac内に残らないため表示できません。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
        }
    }

    @ViewBuilder
    private var codex: some View {
        if let q = store.ledger.quotas["codex"], q.primary != nil || q.secondary != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Codex").font(.pixel(.callout))
                    KindBadge(kind: .quota)
                    if let plan = q.plan { Text(plan).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim) }
                }
                if let p = q.primary { window(p) }
                if let s = q.secondary { window(s) }
                if !compact {
                    Text("記録された時点（\(q.observedAt.relativeText)）の数値です。コインには換算しません。")
                        .font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                }
            }
        } else if !compact {
            Text("Codex: まだ利用枠の記録がありません（Codex を使うと表示されます）。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        }
    }

    private func window(_ w: QuotaWindow) -> some View {
        let remaining = max(0, 100 - w.usedPercent)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(windowName(w.windowMinutes)).font(.pixel(.caption))
                Spacer()
                Text("残り \(Int(remaining.rounded()))%").font(.pixel(.caption)).monospacedDigit()
                if let reset = w.resetsAt, reset > Date() {
                    Text("・\(reset.relativeText)にリセット").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
            }
            PixelBar(value: remaining, color: remaining < 15 ? PixelPalette.danger : remaining < 40 ? Color(rgb: 0xFFA030) : Color(rgb: 0x4FD8C8))
        }
    }

    private func windowName(_ minutes: Int?) -> String {
        guard let m = minutes else { return String(localized: "利用枠") }
        if m >= 10080 { return String(localized: "1週間の枠") }
        if m >= 1440 { return String(localized: "\(m / 1440)日の枠") }
        return String(localized: "\(m / 60)時間の枠")
    }

    @ViewBuilder
    private var claude: some View {
        let est = ClaudeWindowEstimate.current(from: store.ledger.claudeRecent)
        let limitReset = store.ledger.claudeLimitResetAt.flatMap { $0 > Date() ? $0 : nil }
        if est != nil || limitReset != nil || !compact {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Claude").font(.pixel(.callout))
                    KindBadge(kind: .estimated)
                }
                if let reset = limitReset {
                    Label("利用上限に達しています。\(reset.formatted(date: .omitted, time: .shortened))ごろにリセット", systemImage: "hourglass")
                        .font(.pixel(.caption)).foregroundStyle(PixelPalette.danger)
                }
                if let e = est {
                    let elapsed = Date().timeIntervalSince(e.start) / ClaudeWindowEstimate.length * 100
                    HStack {
                        Text("5時間枠 \(e.start.formatted(date: .omitted, time: .shortened))〜\(e.end.formatted(date: .omitted, time: .shortened))")
                            .font(.pixel(.caption))
                        Spacer()
                        Text("残り \(Self.remainingText(e.end))").font(.pixel(.caption)).monospacedDigit()
                    }
                    PixelBar(value: 100 - elapsed, color: Color(rgb: 0xE08A60))
                    Text("この枠で \(Int64(e.tokens).grouped) トークン・\(e.messages) 回の応答").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                } else if !compact {
                    Text("いまは5時間枠の外です（Claude を使うと新しい枠が始まります）。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                if !compact {
                    Text("Mac内の記録から推定した5時間枠です。プランの上限や残りの割合は記録にないため表示できません。")
                        .font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                }
            }
        }
    }

    static func remainingText(_ end: Date) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.hour, .minute]
        return f.string(from: max(0, end.timeIntervalSinceNow)) ?? ""
    }
}
