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
                            CoinLabel(coins: store.coins).font(.largeTitle)
                            Spacer()
                            Button {
                                store.scanNow()
                            } label: {
                                Label(store.isScanning ? "読み取り中…" : "今すぐ読み取る", systemImage: "arrow.clockwise")
                            }
                            .disabled(store.isScanning)
                        }
                        Text("AIで得たコイン: \(store.ledger.coinsEarned)　／　はじめのコイン: \(store.state.initialCoins)　／　使ったコイン: \(store.state.coinsSpent)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(store.state.createdAt.shortText) 以降の利用記録だけをコインにしています。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let last = store.lastScanAt {
                            Text("最終更新: \(last.relativeText)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("換算: 入力・出力 1、キャッシュ書き込み 0.25、キャッシュ読み込み 0.1 の重みで合計し、\(Int(CurrencyRule.tokensPerCoin)) トークンで 1 コイン。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(6)
                } label: {
                    Label("通貨残高", systemImage: "circle.hexagongrid")
                }

                Text("対応元").font(.headline)
                ForEach(UsageReaders.all, id: \.info.id) { reader in
                    SourceRow(info: reader.info)
                }

                if let quota = store.ledger.quotas["codex"] {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                KindBadge(kind: .quota)
                                Text("Codex の利用枠（\(quota.plan ?? "-")）").font(.subheadline.weight(.semibold))
                            }
                            if let p = quota.primary { quotaLine(String(localized: "主な枠"), p) }
                            if let s = quota.secondary { quotaLine(String(localized: "追加の枠"), s) }
                            Text("利用枠の消費率です。トークン数ではないため、コインには換算しません。\(quota.observedAt.relativeText)時点。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("このMacでは読み取れないもの").font(.headline)
                ForEach(UnsupportedSources.all) { u in
                    HStack(alignment: .top) {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name)
                            Text(u.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("「対応」とは、このMacに残った利用記録を集計できることです。AIサービスのアカウント全体の利用量を示すものではありません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func quotaLine(_ title: String, _ w: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Group {
                    if let reset = w.resetsAt {
                        Text("\(Int(w.usedPercent))% 使用・\(reset.shortText) にリセット")
                    } else {
                        Text("\(Int(w.usedPercent))% 使用")
                    }
                }
                .font(.caption).monospacedDigit()
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
                Text(info.name).font(.subheadline.weight(.semibold))
                if info.experimental { Text("試験対応").font(.caption2).foregroundStyle(.orange) }
                Spacer()
                statusLabel(status)
                Toggle("", isOn: Binding(get: { store.settings.enabledSources.contains(info.id) },
                                         set: { store.setSource(info.id, enabled: $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .accessibilityLabel("\(info.name)を読み取る")
            }
            if let t = totals, t.records > 0 {
                Text("入力 \(t.tokens.input.grouped)・出力 \(t.tokens.output.grouped)・キャッシュ書込 \(t.tokens.cacheWrite.grouped)・キャッシュ読込 \(t.tokens.cacheRead.grouped) トークン（\(t.records) 件）")
                    .font(.caption).monospacedDigit()
                HStack {
                    Text("コイン換算: \(String(format: "%.1f", t.creditedWeighted / CurrencyRule.tokensPerCoin))")
                    if t.uncreditedWeighted > 0 {
                        Text("・推定値のため換算していない分: \(String(format: "%.1f", t.uncreditedWeighted / CurrencyRule.tokensPerCoin))")
                    }
                    if let last = t.lastRecordAt { Text("・最新の記録: \(last.relativeText)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if status == .ok {
                Text("付与開始後の利用記録はまだありません。").font(.caption).foregroundStyle(.secondary)
            } else if status == .notFound {
                Text("記録が見つかりません（\(info.locations.joined(separator: "、"))）。アプリを使うと記録が作られます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if case .error(let message, let hint) = status {
                VStack(alignment: .leading, spacing: 2) {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(hint).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusLabel(_ s: SourceStatus) -> some View {
        switch s {
        case .ok: Label(s.label, systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
        case .error: Label(s.label, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
        case .notFound: Label(s.label, systemImage: "questionmark.circle").foregroundStyle(.secondary).font(.caption)
        case .disabled: Label(s.label, systemImage: "pause.circle").foregroundStyle(.secondary).font(.caption)
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
            Text(reason).font(.caption).foregroundStyle(.secondary)
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
        Picker("表示言語", selection: $selection) {
            Text("システムに合わせる").tag("system")
            Text(verbatim: "日本語").tag("ja")
            Text(verbatim: "English").tag("en")
        }
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
                Text("再起動すると切り替わります。").font(.caption).foregroundStyle(.secondary)
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

private struct StyleCard: View {
    let style: AquariumStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    LinearGradient(colors: [Color(rgb: 0x4FB6E6), Color(rgb: 0x165D93)], startPoint: .top, endPoint: .bottom)
                    if let art = style.fishImage("clown", dotPixels: 4, frame: 1, dead: false) {
                        let image = Image(decorative: art.image, scale: 1)
                        (style.isPixel ? image.interpolation(.none) : image.interpolation(.high))
                            .resizable().aspectRatio(contentMode: .fit).padding(10)
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(style.name).font(.callout.weight(selected ? .bold : .regular))
                Text(style.blurb).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(height: 30, alignment: .top)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsScreen: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("表示") {
                Picker("表示方法", selection: $store.settings.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.settings.displayMode == .desktop {
                    Picker("表示するディスプレイ", selection: $store.settings.desktopScreens) {
                        ForEach(DesktopScreens.allCases) { Text($0.label).tag($0) }
                    }
                    Text("デスクトップ表示は、Macの壁紙を変えずに壁紙の上へ水槽を重ねます。デスクトップのアイコンはそのまま使えます。お世話はこのウィンドウかメニューバーから行います。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("アニメーション", selection: $store.settings.fps) {
                    Text("なめらか（60fps）").tag(60)
                    Text("標準（30fps）").tag(30)
                    Text("省電力（15fps）").tag(15)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("画風")
                    HStack(spacing: 10) {
                        ForEach(AquariumStyles.all) { style in
                            StyleCard(style: style, selected: store.settings.styleID == style.id) {
                                store.settings.styleID = style.id
                            }
                        }
                    }
                    Text("画風を変えても、魚や装飾、配置はそのままです。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("起動") {
                Toggle("ログイン時に Tokarium を開く", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                Toggle("魚が危険なときに通知する", isOn: $store.settings.notificationsEnabled)
            }
            Section("AI利用記録") {
                ForEach(UsageReaders.all, id: \.info.id) { r in
                    Toggle(isOn: Binding(get: { store.settings.enabledSources.contains(r.info.id) },
                                         set: { store.setSource(r.info.id, enabled: $0) })) {
                        VStack(alignment: .leading) {
                            Text(r.info.name)
                            Text(r.info.locations.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("推定値もコインに含める", isOn: $store.settings.includeEstimated)
                Text("推定値（Ollama など）は実際のトークン数ではありません。オンにすると、オンにした後に読み取った推定値からコインに換算します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("言語") {
                LanguagePicker()
            }
            Section("アップデートとサポート") {
                UpdateSettings()
                Button("不具合を報告…") { store.bugReport = BugReportRequest() }
                Button("ログをFinderで表示") { NSWorkspace.shared.activateFileViewerSelecting([AppLog.file]) }
                Text("不具合の報告は、内容を確認してからブラウザやメールで送ります。自動では送信しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("データ") {
                LabeledContent("コイン付与の開始", value: store.state.createdAt.shortText)
                Text("保存するのは水槽・魚・装飾・コイン、利用記録の件数・時刻・取得元・重複判定用のID・トークン数だけです。AIとの会話本文・APIキー・Cookieは保存しません。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存フォルダを開く") {
                    let url = GameStore.defaultDirectory
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
    }
}
