import ScreenSaver
import SwiftUI

// Tokarium のスクリーンセーバー。アプリが書き出した水槽の中身を読み、同じ描画で泳がせる。

/// アプリが書き出す水槽の中身（SaverExporter と同じ形）。
struct SaverScene: Codable {
    var tank: Tank
    var timeOfDay: Bool
    var seasons: Bool
    var updatedAt: Date
}

enum SaverData {
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// 読む場所の候補（サンドボックスの中の場所と、本当のホーム）。
    static var candidates: [URL] {
        let sandboxed = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokarium/saver-scene.json")
        let real = realHome.appendingPathComponent("Library/Application Support/Tokarium/saver-scene.json")
        return [sandboxed, real]
    }

    static func load() -> SaverScene {
        for url in candidates {
            if let data = try? Data(contentsOf: url), let scene = try? JSONDecoder().decode(SaverScene.self, from: data) { return scene }
        }
        return demo
    }

    /// 水槽が読めないときの見本の水槽。
    static var demo: SaverScene {
        var tank = Tank()
        let fish: [(String, Double)] = [("neon", 0.3), ("neon", 0.35), ("neon", 0.4), ("clown", 0.6), ("goldfish", 0.5), ("angel", 0.7), ("cory", 0.2)]
        for (id, x) in fish {
            tank.fish.append(Fish(speciesID: id, name: id, fullness: 90, growth: 1, x: x, y: .random(in: 0.2...0.7)))
        }
        for (id, x) in [("grass", 0.12), ("castle", 0.72), ("rock", 0.4), ("tallgrass", 0.9), ("anemone", 0.55), ("airstone", 0.3)] {
            tank.decorations.append(Decoration(kindID: id, x: x))
        }
        return SaverScene(tank: tank, timeOfDay: true, seasons: true, updatedAt: Date())
    }
}

struct SaverAquarium: View {
    let scene: SaverScene
    let engine: SwimEngine
    let style = AquariumStyles.pixel

    var body: some View {
        ZStack {
            Canvas { ctx, size in style.drawBackground(&ctx, size: size, tank: scene.tank) }
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { ctx, size in
                    let ambient = scene.timeOfDay ? Ambient.at(timeline.date) : .day
                    engine.aspect = size.height > 0 ? size.width / size.height : 1.6
                    engine.speedFactor = ambient.speed
                    engine.season = scene.seasons ? .forSeason(timeline.date) : nil
                    engine.step(to: timeline.date, fish: scene.tank.fish, decorations: scene.tank.decorations)
                    style.drawLive(&ctx, size: size, tank: scene.tank, engine: engine, selected: nil, ambient: ambient)
                }
            }
        }
        .background(Color.black)
    }
}

@objc(TokariumSaverView)
final class TokariumSaverView: ScreenSaverView {
    private let engine = SwimEngine()
    private var hosting: NSHostingView<SaverAquarium>?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30
        let host = NSHostingView(rootView: SaverAquarium(scene: SaverData.load(), engine: engine))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
        // 起動のたびに最新の水槽を読む
        hosting?.rootView = SaverAquarium(scene: SaverData.load(), engine: engine)
    }

    override var hasConfigureSheet: Bool { false }
}
