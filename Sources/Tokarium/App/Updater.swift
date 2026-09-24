import Foundation
import Observation
import Sparkle

/// 自動アップデート（Sparkle）。配布用の鍵とフィードが Info.plist に設定されているときだけ動く。
@MainActor
@Observable
final class Updater {
    private(set) var isAvailable = false
    private(set) var canCheckForUpdates = false
    /// 動かない理由（設定画面に出す）。
    private(set) var unavailableReason: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        guard Bundle.main.bundleIdentifier != nil else {
            unavailableReason = String(localized: "アプリとして起動していないため、アップデートを確認できません。")
            return
        }
        guard !key.isEmpty, !feed.isEmpty else {
            unavailableReason = String(localized: "この版はアップデートの配信先が設定されていません。")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
        } catch {
            unavailableReason = String(localized: "アップデートの準備に失敗しました: \(error.localizedDescription)")
            return
        }
        self.controller = controller
        isAvailable = true
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
