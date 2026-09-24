import AppKit
import CoreText
import SwiftUI

// MARK: - 色

/// 画面のまわりの色。水槽（深い海と砂）に合わせる。
enum PixelPalette {
    static let deep = Color(rgb: 0x0B1D36)        // パネルの地
    static let deeper = Color(rgb: 0x061224)      // 影・外枠
    static let sea = Color(rgb: 0x1D4F80)         // ボタン
    static let seaLight = Color(rgb: 0x2E6DA8)    // ボタン（上の光）
    static let sand = Color(rgb: 0xF2E3B3)        // 明るい枠・選択
    static let sandDark = Color(rgb: 0xC8A96A)
    static let text = Color(rgb: 0xF4F1E6)
    static let dim = Color(rgb: 0x9DB4CC)
    static let gold = Color(rgb: 0xFFD54F)
    static let danger = Color(rgb: 0xE53935)
    static let inset = Color(rgb: 0x13294A)       // パネルの中の区切り
}

// MARK: - フォント

enum PixelFont {
    static let name = "DotGothic16-Regular"

    /// 同梱のドット絵フォントを登録する。見つからなければ標準フォントのまま。
    static func register() {
        let candidates = [
            Bundle.main.url(forResource: "DotGothic16-Regular", withExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: "DotGothic16-Regular", withExtension: "ttf"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static var isAvailable: Bool { NSFont(name: name, size: 12) != nil }
}

extension Font {
    /// ドット絵フォント。文字の大きさの種類ごとに、にじみにくい大きさを使う。
    static func pixel(_ style: Font.TextStyle) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 32
        case .title: size = 28
        case .title2: size = 24
        case .title3: size = 20
        case .headline: size = 18
        case .body: size = 16
        case .callout: size = 15
        case .subheadline: size = 14
        case .footnote, .caption: size = 13
        case .caption2: size = 12
        @unknown default: size = 16
        }
        return pixel(size: size, relativeTo: style)
    }

    static func pixel(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        PixelFont.isAvailable ? .custom(PixelFont.name, size: size, relativeTo: style) : .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - 角が階段状の枠

/// 角を階段状に欠いた四角。ドット絵の窓枠に使う。
struct PixelFrameShape: InsettableShape {
    var step: CGFloat = 3
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let s = step
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.minY + s))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> PixelFrameShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// 外枠（暗）→ 明るい枠 → 地、の三重の窓。
struct PixelFrame: View {
    var fill: Color = PixelPalette.deep
    var border: Color = PixelPalette.sand
    var outline: Color = PixelPalette.deeper
    var step: CGFloat = 3

    var body: some View {
        ZStack {
            PixelFrameShape(step: step).fill(outline)
            PixelFrameShape(step: step, inset: step).fill(border)
            PixelFrameShape(step: step, inset: step * 2).fill(fill)
        }
    }
}

extension View {
    /// ドット絵の窓で囲む。
    func pixelPanel(fill: Color = PixelPalette.deep.opacity(0.96), border: Color = PixelPalette.sand, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(PixelFrame(fill: fill, border: border))
    }

    /// パネルの中の区切り（行や小さな箱）。
    func pixelInset(highlight: Bool = false) -> some View {
        self.background(PixelFrame(fill: highlight ? PixelPalette.danger.opacity(0.22) : PixelPalette.inset,
                                   border: highlight ? PixelPalette.danger.opacity(0.8) : PixelPalette.sea, outline: .clear, step: 2))
    }
}

// MARK: - ボタン

struct PixelButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.pixel(.callout))
            .foregroundStyle(prominent ? PixelPalette.deeper : PixelPalette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    PixelFrameShape(step: 2).fill(PixelPalette.deeper)
                    PixelFrameShape(step: 2, inset: 2).fill(prominent ? PixelPalette.sand : PixelPalette.seaLight)
                    PixelFrameShape(step: 2, inset: 4).fill(prominent ? (pressed ? PixelPalette.sandDark : PixelPalette.gold) : (pressed ? PixelPalette.deep : PixelPalette.sea))
                }
            )
            .offset(y: pressed ? 2 : 0)
            .background(PixelFrameShape(step: 2).fill(Color.black.opacity(pressed ? 0 : 0.45)).offset(y: 3))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PixelButtonStyle {
    static var pixel: PixelButtonStyle { PixelButtonStyle() }
    static var pixelProminent: PixelButtonStyle { PixelButtonStyle(prominent: true) }
}

/// ドット絵の枠の小さな札（水質・コインなど）。
struct PixelBadge<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) { content() }
            .font(.pixel(.callout))
            .foregroundStyle(PixelPalette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(PixelFrame(fill: PixelPalette.deep.opacity(0.85), border: PixelPalette.sand.opacity(0.9), step: 2))
    }
}

/// 見出しつきの区切り（設定などで使う）。
struct PixelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pixelInset()
        }
    }
}

struct PixelGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label.font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelInset()
    }
}

/// ドット絵の進み具合バー。
struct PixelBar: View {
    let value: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cells = max(1, Int(w / 6))
            let filled = Int((Double(cells) * min(1, max(0, value / 100))).rounded())
            HStack(spacing: 1) {
                ForEach(0..<cells, id: \.self) { i in
                    Rectangle().fill(i < filled ? color : PixelPalette.deeper)
                }
            }
            .padding(2)
            .background(Rectangle().fill(PixelPalette.sea))
        }
        .frame(height: 12)
    }
}

// MARK: - スイッチと選択肢

/// 右端に ON/OFF のドット絵スイッチを置くトグル。
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    Text("OFF").padding(.horizontal, 6).padding(.vertical, 2)
                        .background(configuration.isOn ? Color.clear : PixelPalette.dim.opacity(0.5))
                        .foregroundStyle(configuration.isOn ? PixelPalette.dim : PixelPalette.text)
                    Text("ON").padding(.horizontal, 8).padding(.vertical, 2)
                        .background(configuration.isOn ? PixelPalette.gold : Color.clear)
                        .foregroundStyle(configuration.isOn ? PixelPalette.deeper : PixelPalette.dim)
                }
                .font(.pixel(.caption))
                .padding(2)
                .background(PixelPalette.deeper)
                .overlay(Rectangle().strokeBorder(PixelPalette.sea, lineWidth: 2))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "ON" : "OFF")
    }
}

extension ToggleStyle where Self == PixelToggleStyle {
    static var pixel: PixelToggleStyle { PixelToggleStyle() }
}

/// 見出しとドット絵のボタンを並べた選択肢。
struct PixelChoice<T: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: T
    let options: [(value: T, label: String)]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    Button(option.label) { selection = option.value }
                        .buttonStyle(PixelButtonStyle(prominent: selection == option.value))
                        .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
        }
    }
}
