import AppKit
import UniformTypeIdentifiers
import SwiftUI

// MARK: - AI利用量

struct UsageScreen: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            CoinLabel(coins: store.coins).font(.pixel(.largeTitle))
                            Spacer()
                            Button {
                                store.scanNow()
                            } label: {
                                Label(store.isScanning ? "読み取り中…" : "今すぐ読み取る", systemImage: "arrow.clockwise")
                            }
                            .disabled(store.isScanning)
                        }
                        Text("AIで得たコイン: \(store.ledger.coinsEarned)　／　はじめのコイン: \(store.state.initialCoins)　／　使ったコイン: \(store.state.coinsSpent)")
                            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        Text("\(store.state.createdAt.shortText) 以降の利用記録だけをコインにしています。")
                            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        if let last = store.lastScanAt {
                            Text("最終更新: \(last.relativeText)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                        Text("換算: 入力・出力 1、キャッシュ書き込み 0.25、キャッシュ読み込み 0.1 の重みで合計し、\(Int(CurrencyRule.tokensPerCoin)) トークンで 1 コイン。")
                            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    }
                    .padding(6)
                } label: {
                    Label("通貨残高", systemImage: "circle.hexagongrid")
                }

                GroupBox {
                    QuotaPanel()
                } label: {
                    Label("AIごとの利用枠", systemImage: "gauge.with.dots.needle.33percent")
                }

                GroupBox {
                    UsageChart()
                } label: {
                    Label("日ごとのAI利用", systemImage: "chart.bar")
                }

                Text("対応元").font(.pixel(.headline))
                ForEach(UsageReaders.all, id: \.info.id) { reader in
                    SourceRow(info: reader.info)
                }

                Text("このMacでは読み取れないもの").font(.pixel(.headline))
                ForEach(UnsupportedSources.all) { u in
                    HStack(alignment: .top) {
                        Image(systemName: "minus.circle").foregroundStyle(PixelPalette.dim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name)
                            Text(u.reason).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                    }
                }
                Text("「対応」とは、このMacに残った利用記録を集計できることです。AIサービスのアカウント全体の利用量を示すものではありません。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            .padding(20)
        }
    }

}

private struct SourceRow: View {
    @Environment(GameStore.self) private var store
    let info: SourceInfo

    var body: some View {
        let totals = store.ledger.sources[info.id]
        let status = store.sourceStatuses[info.id] ?? (store.settings.enabledSources.contains(info.id) ? .ok : .disabled)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                KindBadge(kind: info.kind)
                Text(info.name).font(.pixel(.subheadline))
                if info.experimental { Text("試験対応").font(.pixel(.caption2)).foregroundStyle(.orange) }
                Spacer()
                statusLabel(status)
                Toggle("", isOn: Binding(get: { store.settings.enabledSources.contains(info.id) },
                                         set: { store.setSource(info.id, enabled: $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .accessibilityLabel("\(info.name)を読み取る")
            }
            if let t = totals, t.records > 0 {
                Text("入力 \(t.tokens.input.grouped)・出力 \(t.tokens.output.grouped)・キャッシュ書込 \(t.tokens.cacheWrite.grouped)・キャッシュ読込 \(t.tokens.cacheRead.grouped) トークン（\(t.records) 件）")
                    .font(.pixel(.caption)).monospacedDigit()
                HStack {
                    Text("コイン換算: \(String(format: "%.1f", t.creditedWeighted / CurrencyRule.tokensPerCoin))")
                    if t.uncreditedWeighted > 0 {
                        Text("・推定値のため換算していない分: \(String(format: "%.1f", t.uncreditedWeighted / CurrencyRule.tokensPerCoin))")
                    }
                    if let last = t.lastRecordAt { Text("・最新の記録: \(last.relativeText)") }
                }
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            } else if status == .ok {
                Text("付与開始後の利用記録はまだありません。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            } else if status == .notFound {
                Text("記録が見つかりません（\(info.locations.joined(separator: "、"))）。アプリを使うと記録が作られます。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            if case .error(let message, let hint) = status {
                VStack(alignment: .leading, spacing: 2) {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(hint).foregroundStyle(PixelPalette.dim)
                }
                .font(.pixel(.caption))
            }
        }
        .padding(10)
        .pixelInset()
    }

    @ViewBuilder
    private func statusLabel(_ s: SourceStatus) -> some View {
        switch s {
        case .ok: Label(s.label, systemImage: "checkmark.circle").foregroundStyle(.green).font(.pixel(.caption))
        case .error: Label(s.label, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.pixel(.caption))
        case .notFound: Label(s.label, systemImage: "questionmark.circle").foregroundStyle(PixelPalette.dim).font(.pixel(.caption))
        case .disabled: Label(s.label, systemImage: "pause.circle").foregroundStyle(PixelPalette.dim).font(.pixel(.caption))
        }
    }
}
