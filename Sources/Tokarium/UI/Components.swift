import SwiftUI

struct SpriteImage: View {
    let sprite: PixelSprite?
    let key: String
    var dead = false

    var body: some View {
        if let sprite, let img = SpriteLibrary.image(for: sprite, key: key, dead: dead) {
            Image(decorative: img, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// 魚のアイコン。
struct FishIcon: View {
    @Environment(GameStore.self) private var store
    let speciesID: String
    var dead = false
    var shiny = false
    var body: some View {
        let style = store.style
        if let art = style.fishImage(speciesID, frame: 0, dead: dead, shiny: shiny) {
            Image(decorative: art.image, scale: 1).interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(x: 1, y: dead ? -1 : 1)
        }
    }
}

/// 装飾のアイコン。
struct DecorationIcon: View {
    @Environment(GameStore.self) private var store
    let kindID: String
    var body: some View {
        let style = store.style
        if let art = style.decorationImage(kindID) {
            Image(decorative: art.image, scale: 1).interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct CoinLabel: View {
    let coins: Int
    var body: some View {
        Label {
            Text("\(coins)").monospacedDigit().foregroundStyle(PixelPalette.gold)
        } icon: {
            Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(PixelPalette.gold)
        }
        .accessibilityLabel("コイン \(coins)")
    }
}

/// 数値と言葉を並べて示すバー（色だけに頼らない）。
struct StatBar: View {
    let title: String
    let value: Double
    let word: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                Spacer()
                Text("\(word)（\(Int(value.rounded()))）").font(.pixel(.caption)).monospacedDigit()
            }
            PixelBar(value: value, color: value < 25 ? PixelPalette.danger : value < 50 ? Color(rgb: 0xFFA030) : Color(rgb: 0x5FD068))
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConditionBadge: View {
    let condition: FishCondition
    var body: some View {
        Label(condition.label, systemImage: condition.symbol)
            .font(.pixel(.caption))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(PixelFrame(fill: color.opacity(0.22), border: color, outline: .clear, step: 2))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch condition {
        case .healthy: return Color(rgb: 0x5FD068)
        case .hungry: return Color(rgb: 0xFFA030)
        case .sick: return Color(rgb: 0xC77DFF)
        case .weak: return Color(rgb: 0xFFA030)
        case .critical: return PixelPalette.danger
        case .dead: return PixelPalette.dim
        }
    }
}

struct KindBadge: View {
    let kind: MeasureKind
    var body: some View {
        Text(kind.label)
            .font(.pixel(.caption2))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(PixelFrame(fill: color.opacity(0.22), border: color, outline: .clear, step: 1))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch kind {
        case .measured: return Color(rgb: 0x6FC8FF)
        case .estimated: return Color(rgb: 0xC77DFF)
        case .quota: return Color(rgb: 0x4FD8C8)
        }
    }
}

extension Int64 {
    var grouped: String { NumberFormatter.localizedString(from: NSNumber(value: self), number: .decimal) }
}

extension Date {
    var relativeText: String {
        let f = RelativeDateTimeFormatter()
        f.locale = .autoupdatingCurrent
        return f.localizedString(for: self, relativeTo: Date())
    }

    var shortText: String {
        formatted(.dateTime.month().day().hour().minute())
    }
}
