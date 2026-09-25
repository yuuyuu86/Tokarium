import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Tokarium

// 公開ページ（docs/）に使う画像を、アプリの描画からそのまま書き出す。
// scripts/make_site_assets.sh から TOKARIUM_SITE=docs/assets で動かす。

@MainActor
private func renderView<V: View>(_ view: V, store: GameStore, size: CGSize) -> NSBitmapImageRep? {
    let host = NSHostingView(rootView: view.environment(store).environment(Updater()).frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])?.write(to: url)
}

/// 見本の水槽（いろいろな魚と装飾）。
@MainActor
private func showcaseStore() throws -> GameStore {
    let store = GameStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tokarium-site-\(UUID().uuidString)"))
    store.completeOnboarding(enabled: [], mode: .window)
    store.settings.tutorialDone = true
    store.settings.timeOfDay = false
    store.state.initialCoins = 2180
    store.state.xp = 1400
    store.state.fragments = 9
    store.state.tank.level = 2
    store.state.tank.fish.removeAll()
    let now = Date()
    let fish: [(String, FishVariant, Double, Double)] = [
        ("neon", .wild, 0.2, 0.3), ("neon", .wild, 0.25, 0.34), ("neon", .blue, 0.3, 0.3), ("guppy", .gold, 0.6, 0.2),
        ("guppy", .sunset, 0.7, 0.26), ("angel", .wild, 0.45, 0.5), ("goldfish", .red, 0.8, 0.55), ("clown", .wild, 0.35, 0.7),
        ("cory", .wild, 0.55, 0.82), ("betta", .purple, 0.15, 0.55), ("m_claude2", .wild, 0.62, 0.45),
    ]
    for (id, v, x, y) in fish {
        var f = Fish(speciesID: id, name: Catalog.species(id).name, fullness: 90, purchasedAt: now, growth: 1, x: x, y: y)
        let gene = ColorGene(rawValue: v.rawValue) ?? .wild
        if v == .sunset { f.genotype = Genotype(a: .gold, b: .red) } else if v == .purple { f.genotype = Genotype(a: .blue, b: .red) }
        else { f.genotype = Genotype(a: gene, b: gene) }
        f.affection = 60
        store.state.addFish(f, at: now)
    }
    store.state.tank.fish[3].isFavorite = true
    store.state.tank.fish[4].isShiny = true
    store.state.tank.decorations = [
        Decoration(kindID: "tallgrass", x: 0.06), Decoration(kindID: "sword", x: 0.16, layer: 1), Decoration(kindID: "castle", x: 0.3),
        Decoration(kindID: "anemone", x: 0.42, layer: 1), Decoration(kindID: "coral", x: 0.52), Decoration(kindID: "chest", x: 0.62, layer: 1),
        Decoration(kindID: "ship", x: 0.78), Decoration(kindID: "fern", x: 0.9, layer: 1), Decoration(kindID: "airstone", x: 0.7, layer: 1),
        Decoration(kindID: "starfish", x: 0.24, layer: 1),
    ]
    store.evaluateProgress()
    store.toast = nil
    return store
}

@MainActor
@Test func exportSiteAssets() throws {
    guard let path = ProcessInfo.processInfo.environment["TOKARIUM_SITE"] else { return }
    let root = URL(fileURLWithPath: path)
    let fm = FileManager.default
    for sub in ["sprites/fish", "sprites/variants", "sprites/deco", "shots"] {
        try fm.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    let style = AquariumStyles.pixel

    // 魚（2コマ）
    var fishList: [[String: Any]] = []
    let species = Catalog.fish.filter { $0.isRegular } + Catalog.secretSpecies + Catalog.memorialSpecies + Catalog.memorialUpgrades
    for sp in species {
        var dots = CGSize.zero
        for frame in 0..<2 {
            guard let art = style.fishImage(sp.id, frame: frame, dead: false) else { continue }
            dots = art.dots
            try writePNG(art.image, to: root.appendingPathComponent("sprites/fish/\(sp.id)-\(frame).png"))
        }
        fishList.append(["id": sp.id, "name": sp.name, "w": Int(dots.width), "h": Int(dots.height), "zone": sp.zone.rawValue,
                         "speed": sp.speed, "regular": sp.isRegular, "price": sp.price])
    }

    // 品種の見本
    let variantSpecies = ["guppy", "neon", "goldfish", "betta"]
    for sp in variantSpecies {
        for v in FishVariant.allCases {
            guard let art = style.fishImage(sp, frame: 0, dead: false, shiny: false, variant: v) else { continue }
            try writePNG(art.image, to: root.appendingPathComponent("sprites/variants/\(sp)-\(v.rawValue).png"))
        }
    }

    // 装飾
    var decoList: [[String: Any]] = []
    for kind in Catalog.decorations {
        guard let art = style.decorationImage(kind.id) else { continue }
        try writePNG(art.image, to: root.appendingPathComponent("sprites/deco/\(kind.id).png"))
        decoList.append(["id": kind.id, "name": kind.name, "w": Int(art.dots.width), "h": Int(art.dots.height)])
    }

    let manifest: [String: Any] = [
        "fish": fishList, "decorations": decoList,
        "variants": FishVariant.allCases.map { ["id": $0.rawValue, "name": $0.label, "combo": $0.isCombination] },
        "variantSpecies": variantSpecies,
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent("sprites/manifest.json"))

    // 画面の写真
    let store = try showcaseStore()
    let shots: [(String, AnyView, CGSize)] = [
        ("tank", AnyView(MainView()), CGSize(width: 1180, height: 740)),
        ("missions", AnyView(QuestScreen().padding(20).background(PixelPalette.deep)), CGSize(width: 900, height: 620)),
        ("variants", AnyView(DexScreen(tab: .variants).padding(20).background(PixelPalette.deep)), CGSize(width: 900, height: 620)),
        ("care", AnyView(CareScreen().padding(8).background(PixelPalette.deep)), CGSize(width: 900, height: 620)),
        ("shop", AnyView(ShopScreen().padding(20).background(PixelPalette.deep)), CGSize(width: 900, height: 620)),
    ]
    for (name, view, size) in shots {
        // 泳ぎを少し進めてから撮る
        for i in 0..<30 { store.engine.step(to: Date().addingTimeInterval(Double(i) * 0.05), fish: store.state.tank.fish, decorations: store.state.tank.decorations) }
        let rep = try #require(renderView(view, store: store, size: size))
        try rep.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent("shots/\(name).png"))
    }
}
