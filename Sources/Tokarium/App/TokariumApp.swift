import AppKit
import SwiftUI

@main
struct TokariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Tokarium", id: "main") {
            MainView()
                .environment(delegate.store)
        }
        .defaultSize(width: 980, height: 660)

        MenuBarExtra {
            MenuBarContent().environment(delegate.store)
        } label: {
            Image(systemName: delegate.store.dangerFish.isEmpty ? "fish" : "exclamationmark.triangle.fill")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = GameStore()
    private var desktop: DesktopController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }
}

private struct MenuBarContent: View {
    @Environment(GameStore.self) private var store
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
        Button("Tokarium を終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
