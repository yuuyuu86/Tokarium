import SwiftUI

/// 日ごとにAIで得たコイン（取得元ごとに色分けした積み上げ棒）。
struct UsageChart: View {
    @Environment(GameStore.self) private var store
    @State private var days = 7

    private struct Group: Identifiable {
        let id: String
        let label: String
        let color: Color
        let sources: [String]
    }

    private let groups: [Group] = [
        Group(id: "claude", label: "Claude", color: Color(rgb: 0xE08A60), sources: ["claude-code", "claude-desktop-cowork"]),
        Group(id: "codex", label: "Codex", color: Color(rgb: 0x5FD068), sources: ["codex"]),
        Group(id: "gemini", label: "Gemini / Qwen", color: Color(rgb: 0x7C8CF8), sources: ["gemini-cli", "qwen-code"]),
        Group(id: "other", label: "OpenCode / Copilot / Ollama", color: Color(rgb: 0xF0C040), sources: ["opencode", "copilot-cli", "ollama"]),
    ]

    private var dayKeys: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map { DayKey.key($0) }
    }

    private func coins(_ day: String, _ g: Group) -> Double {
        let d = store.ledger.daily[day] ?? [:]
        return g.sources.reduce(0) { $0 + (d[$1] ?? 0) } / CurrencyRule.tokensPerCoin
    }

    var body: some View {
        let keys = dayKeys
        let totals = keys.map { k in groups.reduce(0) { $0 + coins(k, $1) } }
        let maxTotal = max(1, totals.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("7日") { days = 7 }.buttonStyle(PixelButtonStyle(prominent: days == 7))
                Button("30日") { days = 30 }.buttonStyle(PixelButtonStyle(prominent: days == 30))
                Spacer()
                Text("期間の合計 \(Int(totals.reduce(0, +))) コイン・今日 \(Int(totals.last ?? 0)) コイン")
                    .font(.pixel(.callout)).foregroundStyle(PixelPalette.sand)
            }
            HStack(alignment: .bottom, spacing: days == 7 ? 10 : 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                    VStack(spacing: 4) {
                        if days == 7 {
                            Text("\(Int(totals[i]))").font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                        }
                        VStack(spacing: 0) {
                            ForEach(groups.reversed()) { g in
                                let v = coins(key, g)
                                if v > 0 { Rectangle().fill(g.color).frame(height: max(2, 110 * v / maxTotal)) }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 2, alignment: .bottom)
                        .background(alignment: .bottom) { Rectangle().fill(PixelPalette.deeper).frame(height: 2) }
                        .help("\(key): \(Int(totals[i])) コイン")
                        if days == 7 || i % 5 == 4 || i == keys.count - 1 {
                            Text(label(key)).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim).lineLimit(1).fixedSize()
                        } else {
                            Text(" ").font(.pixel(.caption2))
                        }
                    }
                }
            }
            .frame(height: 150, alignment: .bottom)
            HStack(spacing: 14) {
                ForEach(groups) { g in
                    HStack(spacing: 4) {
                        Rectangle().fill(g.color).frame(width: 10, height: 10)
                        Text(g.label).font(.pixel(.caption2)).foregroundStyle(PixelPalette.dim)
                    }
                }
            }
            Text("1日に \(TreasureRule.dailyCoins) コイン以上得ると、水槽に宝箱が流れてきます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        }
    }

    private func label(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        return d.formatted(.dateTime.month(.defaultDigits).day())
    }
}
