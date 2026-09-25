import AppKit
import Foundation
import IOKit.ps
import Observation
import SwiftUI

/// 電源の状態を見て、アニメーションの速さを決める。
@MainActor
@Observable
final class PowerMonitor {
    private(set) var onBattery = false
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermal = ProcessInfo.processInfo.thermalState

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    func refresh() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = ProcessInfo.processInfo.thermalState
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            onBattery = type == kIOPSBatteryPowerValue
        } else {
            onBattery = false
        }
    }

    /// 省電力を考えた1秒あたりのコマ数。
    func fps(base: Int, auto: Bool) -> Int {
        guard auto else { return base }
        if thermal == .serious || thermal == .critical { return min(base, 10) }
        if lowPowerMode || onBattery { return min(base, 15) }
        return base
    }

    var statusText: String {
        if thermal == .serious || thermal == .critical { return String(localized: "Mac が熱くなっているので、動きを控えめにしています") }
        if lowPowerMode { return String(localized: "低電力モードなので、動きを控えめにしています") }
        if onBattery { return String(localized: "バッテリーで動いているので、動きを控えめにしています") }
        return String(localized: "電源につながっています（設定どおりの速さ）")
    }
}

/// 表示している窓が画面から完全に隠れているかを調べる。
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = ObservingView()
        view.onChange = { visible in
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ObservingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                guard let self, let w = self.window else { return }
                self.onChange?(w.occlusionState.contains(.visible))
            }
            onChange?(window.occlusionState.contains(.visible))
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
