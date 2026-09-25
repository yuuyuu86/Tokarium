import SwiftUI
import WidgetKit

// Tokarium のウィジェット。アプリが書き出した水槽の画像と状態を表示する。
// サンドボックスの中から、~/Library/Application Support/Tokarium/widget を読み取り専用で読む。

struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var coins: Int
    var food: Int
    var fishCount: Int
    var maxFish: Int
    var water: String
    var waterValue: Double
    var danger: [String]
    var sick: Int
}

struct TankEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let image: CGImage?
}

private enum SharedData {
    /// サンドボックスの外の本当のホームフォルダ。
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var folder: URL { realHome.appendingPathComponent("Library/Application Support/Tokarium/widget") }

    static func load() -> TankEntry {
        let snap = (try? Data(contentsOf: folder.appendingPathComponent("snapshot.json")))
            .flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        var image: CGImage?
        if let data = try? Data(contentsOf: folder.appendingPathComponent("tank.png")),
           let src = CGImageSourceCreateWithData(data as CFData, nil) {
            image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        return TankEntry(date: Date(), snapshot: snap, image: image)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TankEntry { TankEntry(date: Date(), snapshot: nil, image: nil) }

    func getSnapshot(in context: Context, completion: @escaping (TankEntry) -> Void) {
        completion(SharedData.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TankEntry>) -> Void) {
        completion(Timeline(entries: [SharedData.load()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private let deep = Color(red: 0.04, green: 0.11, blue: 0.21)
private let sand = Color(red: 0.95, green: 0.89, blue: 0.70)
private let gold = Color(red: 1.0, green: 0.84, blue: 0.31)
private let danger = Color(red: 0.9, green: 0.22, blue: 0.21)

/// ウィジェットは別の小さなプログラムなので、表示言語だけここで切りかえる。
private let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? true

private func pixelFont(_ size: CGFloat) -> Font {
    NSFont(name: "DotGothic16-Regular", size: size) != nil ? .custom("DotGothic16-Regular", size: size) : .system(size: size, weight: .semibold, design: .rounded)
}

struct TankWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TankEntry

    var body: some View {
        if let snap = entry.snapshot {
            content(snap)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "fish.fill").font(.title)
                Text(isJapanese ? "Tokarium を開くと水槽が表示されます" : "Open Tokarium to show your tank").font(pixelFont(12)).multilineTextAlignment(.center)
            }
            .foregroundStyle(sand)
        }
    }

    @ViewBuilder
    private func content(_ snap: WidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            ZStack(alignment: .bottom) {
                tankImage
                HStack {
                    Label("\(snap.coins)", systemImage: "circle.hexagongrid.circle.fill").foregroundStyle(gold)
                    Spacer()
                    if !snap.danger.isEmpty {
                        Label("\(snap.danger.count)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(danger)
                    }
                }
                .font(pixelFont(12))
                .padding(6)
                .background(deep.opacity(0.85))
            }
        default:
            HStack(spacing: 10) {
                tankImage.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 5) {
                    row("circle.hexagongrid.circle.fill", "\(snap.coins)", gold)
                    row("drop.fill", snap.water, snap.waterValue < 45 ? danger : sand)
                    row("fish.fill", "\(snap.fishCount)/\(snap.maxFish)", sand)
                    row("leaf.fill", "\(snap.food)", snap.food <= 3 ? danger : sand)
                    if !snap.danger.isEmpty {
                        row("exclamationmark.triangle.fill", snap.danger.joined(separator: ", "), danger)
                    } else if snap.sick > 0 {
                        row("cross.case.fill", "\(snap.sick)", Color(red: 0.78, green: 0.49, blue: 1))
                    }
                    Spacer(minLength: 0)
                    Text(snap.updatedAt, style: .relative).font(pixelFont(10)).foregroundStyle(sand.opacity(0.6))
                }
                .frame(width: 120, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var tankImage: some View {
        if let img = entry.image {
            Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(red: 0.31, green: 0.71, blue: 0.9), Color(red: 0.05, green: 0.25, blue: 0.45)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func row(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).frame(width: 14)
            Text(text).lineLimit(1)
        }
        .font(pixelFont(12))
        .foregroundStyle(color)
    }
}

struct TokariumTankWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokariumTank", provider: Provider()) { entry in
            TankWidgetView(entry: entry)
                .containerBackground(deep, for: .widget)
        }
        .configurationDisplayName("Tokarium")
        .description(isJapanese ? "水槽の小窓と、コイン・水質・危険な魚を表示します。" : "A small window into your tank, with coins, water, and fish in danger.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct TokariumWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokariumTankWidget()
    }
}
