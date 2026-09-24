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

struct FishIcon: View {
    let speciesID: String
    var dead = false
    var body: some View {
        SpriteImage(sprite: SpriteLibrary.fish[speciesID], key: "fish-\(speciesID)", dead: dead)
    }
}

struct DecorationIcon: View {
    let kindID: String
    var body: some View {
        SpriteImage(sprite: SpriteLibrary.decorations[kindID], key: "deco-\(kindID)")
    }
}

struct CoinLabel: View {
    let coins: Int
    var body: some View {
        Label {
            Text("\(coins)").monospacedDigit().fontWeight(.semibold)
        } icon: {
            Image(systemName: "circle.hexagongrid.circle.fill").foregroundStyle(.yellow)
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
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(word)（\(Int(value.rounded()))）").font(.caption).monospacedDigit()
            }
            ProgressView(value: value, total: 100)
                .tint(value < 25 ? .red : value < 50 ? .orange : .green)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConditionBadge: View {
    let condition: FishCondition
    var body: some View {
        Label(condition.label, systemImage: condition.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch condition {
        case .healthy: return .green
        case .hungry: return .orange
        case .sick: return .purple
        case .weak: return .orange
        case .critical: return .red
        case .dead: return .secondary
        }
    }
}

struct KindBadge: View {
    let kind: MeasureKind
    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch kind {
        case .measured: return .blue
        case .estimated: return .purple
        case .quota: return .teal
        }
    }
}

extension Int64 {
    var grouped: String { NumberFormatter.localizedString(from: NSNumber(value: self), number: .decimal) }
}

extension Date {
    var relativeText: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f.localizedString(for: self, relativeTo: Date())
    }

    var shortText: String {
        formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ja_JP")))
    }
}
