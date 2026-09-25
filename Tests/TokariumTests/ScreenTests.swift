import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Tokarium

// 画面を実際に描いて、落ちないこと・空っぽにならないことを確かめる。
// あわせて、画面のボタンが呼ぶ操作を、遊ぶ人の流れどおりに確かめる。

@MainActor
private func render<V: View>(_ view: V, store: GameStore, size: CGSize = CGSize(width: 1100, height: 720)) -> NSBitmapImageRep? {
    let host = NSHostingView(rootView: view.environment(store).environment(Updater()).frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

/// 画像が一色だけでないか（何かが描かれているか）。
private func hasContent(_ rep: NSBitmapImageRep) -> Bool {
    guard rep.pixelsWide > 0, rep.pixelsHigh > 0, let first = rep.colorAt(x: 0, y: 0) else { return false }
    for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 20)) {
        for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 20)) where rep.colorAt(x: x, y: y) != first {
            return true
        }
    }
    return false
}

@MainActor
private func playedStore() throws -> GameStore {
    let store = GameStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tokarium-ui-\(UUID().uuidString)"))
    store.completeOnboarding(enabled: [], mode: .window)
    store.settings.tutorialDone = true
    _ = store.buyFish(Catalog.species("guppy"))
    store.feed()
    return store
}

@MainActor
@Test func everyScreenRenders() throws {
    let store = try playedStore()
    let screens: [(String, AnyView)] = [
        ("main", AnyView(MainView())),
        ("care", AnyView(CareScreen())),
        ("shop", AnyView(ShopScreen())),
        ("dex", AnyView(DexScreen())),
        ("usage", AnyView(UsageScreen())),
        ("settings-general", AnyView(SettingsScreen(tab: .general))),
        ("settings-tank", AnyView(SettingsScreen(tab: .tank))),
        ("settings-usage", AnyView(SettingsScreen(tab: .usage))),
        ("settings-data", AnyView(SettingsScreen(tab: .data))),
        ("settings-support", AnyView(SettingsScreen(tab: .support))),
        ("onboarding", AnyView(OnboardingView())),
        ("about", AnyView(AboutView())),
        ("bugreport", AnyView(BugReportView(crash: nil))),
    ]
    for (name, view) in screens {
        let rep = render(view.background(PixelPalette.deep), store: store)
        #expect(rep != nil, "\(name) を描けない")
        if let rep { #expect(hasContent(rep), "\(name) が空っぽ") }
    }
}

@MainActor
@Test func screensRenderInEnglishAndNarrowWindows() throws {
    let store = try playedStore()
    for size in [CGSize(width: 820, height: 560), CGSize(width: 1600, height: 1000)] {
        let rep = render(MainView().environment(\.locale, Locale(identifier: "en")), store: store, size: size)
        #expect(rep.map(hasContent) == true)
    }
}

@MainActor
@Test func playerJourney() throws {
    let store = try playedStore()
    let startCoins = store.coins

    // 魚を買う → 図鑑に載る
    #expect(store.state.dex["guppy"] != nil)
    #expect(store.coins == startCoins)

    // 餌やり・水換え → 記録と実績
    #expect(store.state.stats.feedings == 1)
    #expect(store.state.achievements["first_feed"] != nil)
    store.changeWater()
    #expect(store.state.tank.waterQuality == 100)

    // 装飾を買う → 置き場所を選ぶ → 置く
    #expect(store.buyDecoration(Catalog.decoration("shell")) == nil)
    let placing = try #require(store.placingDecoration)
    store.moveDecoration(placing, x: 0.25)
    store.finishPlacing()
    #expect(store.state.tank.decorations.first { $0.id == placing }?.isPlaced == true)

    // 魚をクリックしたメニューの操作
    let guppy = try #require(store.state.tank.fish.first { $0.speciesID == "guppy" })
    store.toggleFavorite(guppy.id)
    #expect(store.favoriteFish?.id == guppy.id)
    store.rename(guppy.id, to: "ぐっちゃん")
    #expect(store.state.tank.fish.first { $0.id == guppy.id }?.name == "ぐっちゃん")
    store.feed(fish: guppy.id)
    #expect(store.state.stats.feedings == 2)

    // ここまででコインを使い切っているので、薬は買えない
    #expect(store.coins < Catalog.medicinePrice)
    #expect(store.buyMedicine() == .notEnoughCoins)
    // 薬がなければ、病気でなくても何も起きない
    store.giveMedicine(guppy.id)
    #expect(store.state.medicine == 0)

    // ランクが足りないものは、まだ買えない
    #expect(store.buyTankUpgrade() == .rankTooLow(KeeperRank.required(tankLevel: 1)))
    #expect(store.buyFish(Catalog.species("arowana")) == .rankTooLow(KeeperRank.required(Catalog.species("arowana"))))
    // 餌やり・水換え・装飾の配置・図鑑で経験値がたまり、お題も進む
    #expect(store.state.xp > 0)
    #expect(store.state.quests.progress.values.reduce(0, +) > 0 || Quests.current().allSatisfy { ![.feed, .feedOne, .waterChange, .placeDecoration].contains($0.template.kind) })

    // 画面からの操作の受け渡し
    store.command = .show(.shop)
    #expect(store.command == .show(.shop))
}

@MainActor
@Test func autoBackupKeepsGenerationsAndRecoversBrokenData() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tokarium-backup-\(UUID().uuidString)")
    let store = GameStore(directory: dir)
    store.feed()
    let now = Date()
    for day in 0..<10 { store.autoBackupIfNeeded(now: now.addingTimeInterval(Double(day) * 86400 + 1), force: true) }
    #expect(store.autoBackups.count == AutoBackup.keep)

    // 1日たっていなければ作らない
    let count = store.autoBackups.count
    store.autoBackupIfNeeded(now: now.addingTimeInterval(9 * 86400 + 10))
    #expect(store.autoBackups.count == count)

    // 水槽のデータが壊れたら、別名で残してバックアップから戻す
    try Data("{ broken".utf8).write(to: dir.appendingPathComponent("game.json"))
    let recovered = GameStore(directory: dir)
    #expect(recovered.state.stats.feedings == 1)
    #expect(recovered.resumeMessage != nil)
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.contains { $0.hasPrefix("game.broken-") })
}
