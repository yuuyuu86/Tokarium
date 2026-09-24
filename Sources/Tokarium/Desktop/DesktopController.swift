import AppKit
import SwiftUI

/// デスクトップ表示。Macの壁紙設定は変えず、壁紙の上・アイコンの下に背景用ウィンドウを置く。
@MainActor
final class DesktopController {
    private let store: GameStore
    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?

    init(store: GameStore) {
        self.store = store
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func update() {
        tearDown()
        guard store.settings.onboarded, store.settings.displayMode == .desktop else { return }
        let screens = store.settings.desktopScreens == .all ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens[0]].compactMap { $0 }
        for screen in screens {
            windows.append(makeWindow(for: screen))
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        // 壁紙のすぐ上（デスクトップアイコンより下）
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        // アイコンの操作を妨げないようにマウスを通す
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AquariumView(store: store).ignoresSafeArea())
        window.setFrame(screen.frame, display: true)
        window.orderBack(nil)
        return window
    }

    private func tearDown() {
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
    }
}
