import AppKit
import SwiftUI

@main
struct TokariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        PixelFont.register()
    }

    var body: some Scene {
        Window("Tokarium", id: "main") {
            MainView()
                .environment(delegate.store)
                .environment(delegate.updater)
        }
        .defaultSize(width: 1080, height: 700)
        // 標準のタイトルバーを消し、水槽を窓いっぱいに出す
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { delegate.updater.checkForUpdates() }
                    .disabled(!delegate.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .help) {
                Button("不具合を報告…") { delegate.store.bugReport = BugReportRequest() }
                Button("ログをFinderで表示") { NSWorkspace.shared.activateFileViewerSelecting([AppLog.file]) }
            }
        }

        MenuBarExtra {
            MenuBarPanel().environment(delegate.store).environment(delegate.updater)
        } label: {
            Image(systemName: delegate.store.dangerFish.isEmpty ? "fish" : "exclamationmark.triangle.fill")
        }
        // メニューバーから小さな水槽をのぞく
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = GameStore()
    let updater = Updater()
    private var desktop: DesktopController?
    private var termSource: DispatchSourceSignal?
    private var widgetTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("起動 \(Diagnostics.appVersion) \(Diagnostics.systemSummary)")
        if let crash = Diagnostics.startSession() {
            store.bugReport = BugReportRequest(crash: crash)
        }
        // kill などで終了を頼まれたときも、保存してから普通に終わる（異常終了と区別する）
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        termSource = term
        let desktop = DesktopController(store: store)
        self.desktop = desktop
        store.onDisplaySettingsChanged = { [weak desktop] in desktop?.update() }
        store.start()
        desktop.update()
        // ウィジェット用の水槽の画像と状態（数分おき、危険な魚が変わったときはすぐ）
        WidgetExporter.update(store: store, force: true)
        widgetTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                WidgetExporter.update(store: self.store)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // デスクトップ表示中はウィンドウを閉じても水槽を出し続ける
        store.settings.displayMode == .window && store.settings.onboarded
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.simulate()
        store.save()
        WidgetExporter.update(store: store, force: true)
        Diagnostics.endSession()
    }
}

/// メニューバーの小窓: 小さな水槽とステータス、よく使う操作。
private struct MenuBarPanel: View {
    @Environment(GameStore.self) private var store
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AquariumView(store: store)
                .frame(width: 340, height: 190)
                .clipped()
                .overlay(Rectangle().strokeBorder(PixelPalette.sand, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    PixelBadge {
                        Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(PixelPalette.gold)
                        Text("\(store.coins)").monospacedDigit().foregroundStyle(PixelPalette.gold)
                    }
                    .scaleEffect(0.85)
                    .padding(4)
                }

            HStack(spacing: 12) {
                Label(WaterCondition(store.state.tank.waterQuality).label, systemImage: "drop.fill")
                Label("\(store.livingFish.count)/\(store.state.tank.size.maxFish)", systemImage: "fish.fill")
                Label("\(store.state.food)", systemImage: "leaf.fill")
                    .foregroundStyle(store.state.food <= Catalog.lowFood ? PixelPalette.danger : PixelPalette.text)
            }
            .font(.pixel(.caption))
            .lineLimit(1)

            if store.dangerFish.isEmpty {
                Text("魚: \(store.livingFish.count) 匹・みんな無事").font(.pixel(.caption)).foregroundStyle(Color(rgb: 0x5FD068))
            } else {
                Label("危険な魚: \(store.dangerFish.map(\.name).joined(separator: "、"))", systemImage: "exclamationmark.triangle.fill")
                    .font(.pixel(.caption)).foregroundStyle(PixelPalette.danger)
            }
            if let f = store.favoriteFish {
                HStack(spacing: 6) {
                    FishIcon(speciesID: f.speciesID, dead: !f.isAlive, shiny: f.isShiny).frame(width: 26, height: 18)
                    Text("♥ \(f.name)・\(f.condition.label)").font(.pixel(.caption))
                }
            }

            QuotaPanel(compact: true)

            HStack(spacing: 6) {
                Button { store.feed() } label: { Label("餌（\(store.state.food)）", systemImage: "leaf.fill") }
                    .disabled(!store.canFeed)
                Button { store.changeWater() } label: { Label("水換え", systemImage: "drop.triangle.fill") }
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Label("開く", systemImage: "macwindow") }
            }

            Divider().overlay(PixelPalette.sea)

            HStack(spacing: 6) {
                Button(store.settings.displayMode == .desktop ? "ウィンドウ表示へ" : "デスクトップ表示へ") {
                    store.settings.displayMode = store.settings.displayMode == .desktop ? .window : .desktop
                }
                Button { store.scanNow() } label: { Image(systemName: "arrow.clockwise") }
                    .help("AI利用記録を今すぐ読み取る").accessibilityLabel("AI利用記録を今すぐ読み取る")
                Spacer()
                Menu {
                    Button("アップデートを確認…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    Button("不具合を報告…") {
                        store.bugReport = BugReportRequest()
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Divider()
                    Button("Tokarium を終了") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("その他")
            }
        }
        .buttonStyle(.pixel)
        .font(.pixel(.body))
        .foregroundStyle(PixelPalette.text)
        .padding(14)
        .frame(width: 368)
        .background(PixelPalette.deep)
        .preferredColorScheme(.dark)
    }
}
