import AppKit
import SwiftUI

@main
struct TokariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Tokarium", id: "main") {
            MainView()
                .environment(delegate.store)
                .environment(delegate.updater)
        }
        .defaultSize(width: 980, height: 660)
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
            MenuBarContent().environment(delegate.store).environment(delegate.updater)
        } label: {
            Image(systemName: delegate.store.dangerFish.isEmpty ? "fish" : "exclamationmark.triangle.fill")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = GameStore()
    let updater = Updater()
    private var desktop: DesktopController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("起動 \(Diagnostics.appVersion) \(Diagnostics.systemSummary)")
        if let crash = Diagnostics.startSession() {
            store.bugReport = BugReportRequest(crash: crash)
        }
        let desktop = DesktopController(store: store)
        self.desktop = desktop
        store.onDisplaySettingsChanged = { [weak desktop] in desktop?.update() }
        store.start()
        desktop.update()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // デスクトップ表示中はウィンドウを閉じても水槽を出し続ける
        store.settings.displayMode == .window && store.settings.onboarded
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.simulate()
        store.save()
        Diagnostics.endSession()
    }
}

private struct MenuBarContent: View {
    @Environment(GameStore.self) private var store
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("コイン: \(store.coins)")
        Text("水質: \(WaterCondition(store.state.tank.waterQuality).label)")
        if store.dangerFish.isEmpty {
            Text("魚: \(store.livingFish.count) 匹・みんな無事")
        } else {
            Text("危険な魚: \(store.dangerFish.map(\.name).joined(separator: "、"))")
        }
        Divider()
        Button("餌をあげる") { store.feed() }
        Button("水換え") { store.changeWater() }
        Divider()
        Button("Tokarium を開く") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(store.settings.displayMode == .desktop ? "ウィンドウ表示に切り替え" : "デスクトップ表示に切り替え") {
            store.settings.displayMode = store.settings.displayMode == .desktop ? .window : .desktop
        }
        Button("AI利用記録を今すぐ読み取る") { store.scanNow() }
        Divider()
        Button("アップデートを確認…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
        Button("不具合を報告…") {
            store.bugReport = BugReportRequest()
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Tokarium を終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
