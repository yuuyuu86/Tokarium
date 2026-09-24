import AppKit
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

                Text("対応元").font(.pixel(.headline))
                ForEach(UsageReaders.all, id: \.info.id) { reader in
                    SourceRow(info: reader.info)
                }

                if let quota = store.ledger.quotas["codex"] {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                KindBadge(kind: .quota)
                                Text("Codex の利用枠（\(quota.plan ?? "-")）").font(.pixel(.subheadline))
                            }
                            if let p = quota.primary { quotaLine(String(localized: "主な枠"), p) }
                            if let s = quota.secondary { quotaLine(String(localized: "追加の枠"), s) }
                            Text("利用枠の消費率です。トークン数ではないため、コインには換算しません。\(quota.observedAt.relativeText)時点。")
                                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    private func quotaLine(_ title: String, _ w: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.pixel(.caption))
                Spacer()
                Group {
                    if let reset = w.resetsAt {
                        Text("\(Int(w.usedPercent))% 使用・\(reset.shortText) にリセット")
                    } else {
                        Text("\(Int(w.usedPercent))% 使用")
                    }
                }
                .font(.pixel(.caption)).monospacedDigit()
            }
            ProgressView(value: min(100, w.usedPercent), total: 100).tint(.teal)
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

// MARK: - 設定

private struct UpdateSettings: View {
    @Environment(Updater.self) private var updater
    @State private var auto = false

    var body: some View {
        if updater.isAvailable {
            Toggle("アップデートを自動で確認する", isOn: Binding(get: { auto }, set: { auto = $0; updater.automaticallyChecks = $0 }))
                .onAppear { auto = updater.automaticallyChecks }
            Button("今すぐアップデートを確認…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
        } else if let reason = updater.unavailableReason {
            Text(reason).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        }
        LabeledContent("バージョン", value: Diagnostics.appVersion)
    }
}

/// 表示言語。変更はアプリの再起動後に反映される。
private struct LanguagePicker: View {
    @State private var selection: String = Self.current
    @State private var changed = false

    /// アプリ単位で上書きしている言語（なければ "system"）。
    private static var current: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        guard let lang = (domain["AppleLanguages"] as? [String])?.first else { return "system" }
        return lang.hasPrefix("en") ? "en" : lang.hasPrefix("ja") ? "ja" : "system"
    }

    var body: some View {
        PixelChoice(title: "表示言語", selection: $selection,
                    options: [("system", String(localized: "システムに合わせる")), ("ja", "日本語"), ("en", "English")])
        .onChange(of: selection) { _, new in
            if new == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([new], forKey: "AppleLanguages")
            }
            changed = true
        }
        if changed {
            HStack {
                Text("再起動すると切り替わります。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                Button("今すぐ再起動") { Relauncher.relaunch() }
            }
        }
    }
}

enum Relauncher {
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct SettingsScreen: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            PixelSection("表示") {
                PixelChoice(title: "表示方法", selection: $store.settings.displayMode,
                            options: DisplayMode.allCases.map { ($0, $0.label) })
                if store.settings.displayMode == .desktop {
                    PixelChoice(title: "表示するディスプレイ", selection: $store.settings.desktopScreens,
                                options: DesktopScreens.allCases.map { ($0, $0.label) })
                    Text("デスクトップ表示は、Macの壁紙を変えずに壁紙の上へ水槽を重ねます。デスクトップのアイコンはそのまま使えます。お世話はこのウィンドウかメニューバーから行います。")
                        .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
                PixelChoice(title: "アニメーション", selection: $store.settings.fps,
                            options: [(60, String(localized: "なめらか（60fps）")), (30, String(localized: "標準（30fps）")), (15, String(localized: "省電力（15fps）"))])
            }
            PixelSection("起動") {
                Toggle("ログイン時に Tokarium を開く", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                Toggle("魚が危険なときに通知する", isOn: $store.settings.notificationsEnabled)
            }
            PixelSection("AI利用記録") {
                ForEach(UsageReaders.all, id: \.info.id) { r in
                    Toggle(isOn: Binding(get: { store.settings.enabledSources.contains(r.info.id) },
                                         set: { store.setSource(r.info.id, enabled: $0) })) {
                        VStack(alignment: .leading) {
                            Text(r.info.name)
                            Text(r.info.locations.joined(separator: "、")).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                    }
                }
                Toggle("推定値もコインに含める", isOn: $store.settings.includeEstimated)
                Text("推定値（Ollama など）は実際のトークン数ではありません。オンにすると、オンにした後に読み取った推定値からコインに換算します。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            PixelSection("言語") {
                LanguagePicker()
            }
            PixelSection("アップデートとサポート") {
                UpdateSettings()
                Button("不具合を報告…") { store.bugReport = BugReportRequest() }
                Button("ログをFinderで表示") { NSWorkspace.shared.activateFileViewerSelecting([AppLog.file]) }
                Text("不具合の報告は、内容を確認してからブラウザやメールで送ります。自動では送信しません。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            PixelSection("データ") {
                LabeledContent("コイン付与の開始", value: store.state.createdAt.shortText)
                Text("保存するのは水槽・魚・装飾・コイン、利用記録の件数・時刻・取得元・重複判定用のID・トークン数だけです。AIとの会話本文・APIキー・Cookieは保存しません。")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                Button("保存フォルダを開く") {
                    let url = GameStore.defaultDirectory
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(4)
        }
        .toggleStyle(.pixel)
        .buttonStyle(.pixel)
    }
}
