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

// MARK: - 設定

private struct SaverSettings: View {
    @Environment(GameStore.self) private var store
    @State private var error: String?
    @State private var installed = SaverExporter.isInstalled

    var body: some View {
        HStack {
            Button {
                do {
                    try SaverExporter.install(store: store)
                    installed = true
                    store.toast = String(localized: "スクリーンセーバーを入れました。設定で「Tokarium」を選んでください")
                } catch {
                    self.error = String(localized: "スクリーンセーバーを入れられませんでした: \(error.localizedDescription)")
                }
            } label: { Label(installed ? "スクリーンセーバーを入れ直す" : "スクリーンセーバーを入れる", systemImage: "sparkles.tv") }
            if installed { Text("入っています").font(.pixel(.caption)).foregroundStyle(Color(rgb: 0x5FD068)) }
        }
        Text("Mac のスクリーンセーバーとして、あなたの水槽が泳ぎます。水槽の中身は数分おきに新しくなります。")
            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        if let error { Text(error).font(.pixel(.caption)).foregroundStyle(PixelPalette.danger) }
    }
}

private struct ReminderSettings: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Toggle("決まった時刻に「そろそろ餌の時間です」と知らせる", isOn: $store.settings.remindersEnabled)
        if store.settings.remindersEnabled {
            ForEach(Array(store.settings.reminderTimes.enumerated()), id: \.offset) { i, minutes in
                HStack(spacing: 8) {
                    Text(String(format: "%02d:%02d", minutes / 60, minutes % 60)).font(.pixel(.title3)).monospacedDigit()
                    Button("−30分") { change(i, by: -30) }
                    Button("+30分") { change(i, by: 30) }
                    Spacer()
                    Button { store.settings.reminderTimes.remove(at: i) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("この時刻を削除")
                }
            }
            if store.settings.reminderTimes.count < 6 {
                Button { store.settings.reminderTimes.append(12 * 60) } label: { Label("時刻を追加", systemImage: "plus") }
            }
            if !store.settings.notificationsEnabled {
                Text("通知がオフになっています。「起動」の通知をオンにしてください。").font(.pixel(.caption)).foregroundStyle(PixelPalette.danger)
            }
        }
    }

    private func change(_ i: Int, by delta: Int) {
        var t = store.settings.reminderTimes[i] + delta
        t = (t % 1440 + 1440) % 1440
        store.settings.reminderTimes[i] = t
    }
}

private struct BackupSettings: View {
    @Environment(GameStore.self) private var store
    @State private var confirmImport: URL?
    @State private var error: String?

    var body: some View {
        @Bindable var store = store
        HStack {
            Button { exportBackup() } label: { Label("バックアップを書き出す…", systemImage: "square.and.arrow.up") }
            Button { chooseImport() } label: { Label("バックアップから復元…", systemImage: "square.and.arrow.down") }
        }
        Text("Mac を買いかえたときなどに、水槽・図鑑・実績・コインの記録をまとめて移せます。").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        Toggle("iCloud Drive で水槽を同期する", isOn: $store.settings.iCloudSync)
            .disabled(GameStore.iCloudFolder == nil)
        Text(GameStore.iCloudFolder == nil
             ? "iCloud Drive が見つかりません。システム設定で iCloud Drive をオンにすると使えます。"
             : "同じ Apple アカウントの Mac で同じ水槽を育てられます。コインは Mac ごとのAI利用を合計します。2台で同時に操作すると、ほぼ同時の操作は片方だけが残ることがあります。")
            .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        .alert("バックアップから復元しますか？", isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } })) {
            Button("復元する", role: .destructive) {
                if let url = confirmImport {
                    do { try store.importBackup(from: url) } catch { self.error = error.localizedDescription }
                }
                confirmImport = nil
            }
            Button("キャンセル", role: .cancel) { confirmImport = nil }
        } message: {
            Text("いまの水槽は、バックアップの内容に置きかわります。")
        }
        .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "Tokarium-backup-\(f.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportBackup(to: url) } catch { self.error = error.localizedDescription }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        confirmImport = url
    }
}

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
                Toggle("省電力（窓が隠れているときは止め、バッテリーや低電力モードでは控えめに）", isOn: $store.settings.autoPowerSaving)
                if store.settings.autoPowerSaving {
                    Text("\(store.power.statusText)・いまは \(store.effectiveFPS) fps").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
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
            PixelSection("水槽の演出") {
                Toggle("時間帯で明るさを変える（夜は魚もゆっくり）", isOn: $store.settings.timeOfDay)
                Toggle("季節の浮遊物（春は花びら・秋は葉・冬はマリンスノー）", isOn: $store.settings.seasons)
            }
            PixelSection("スクリーンセーバー") {
                SaverSettings()
            }
            PixelSection("お世話のリマインド") {
                ReminderSettings()
            }
            PixelSection("バックアップと同期") {
                BackupSettings()
            }
            PixelSection("言語") {
                LanguagePicker()
            }
            PixelSection("アップデートとサポート") {
                UpdateSettings()
                Button("チュートリアルをもう一度見る") {
                    store.settings.tutorialDone = false
                    store.toast = String(localized: "水槽の画面に戻ると、案内が始まります")
                }
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
