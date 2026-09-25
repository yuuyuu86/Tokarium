import SwiftUI

/// 案内で指す場所の目印。
struct TutorialAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 初回の案内で指し示す場所として登録する。
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

struct TutorialStep {
    let anchor: String?
    let title: String
    let body: String

    static let all: [TutorialStep] = [
        TutorialStep(anchor: nil, title: String(localized: "Tokarium へようこそ！"),
                     body: String(localized: "魚にカーソルを重ねるとようすが、クリックすると餌やりなどのメニューが出ます。水をクリックすると魚が寄ってきます。")),
        TutorialStep(anchor: "coins", title: String(localized: "コイン"),
                     body: String(localized: "AIを使うと、このMacの利用記録からコインが貯まります。1万トークン（重み付き）で1コインです。")),
        TutorialStep(anchor: "feed", title: String(localized: "餌やり"),
                     body: String(localized: "1日1〜2回が目安です。餌はお店で買えます（はじめに20回分あります）。")),
        TutorialStep(anchor: "water", title: String(localized: "水換え"),
                     body: String(localized: "水は少しずつ汚れます。数日に1回換えないと、魚が病気になりやすくなります。")),
        TutorialStep(anchor: "shop", title: String(localized: "お店"),
                     body: String(localized: "コインで魚・装飾・餌・設備を買えます。装飾は買ったあと、水槽で置き場所を選びます。")),
        TutorialStep(anchor: "dex", title: String(localized: "図鑑と実績"),
                     body: String(localized: "迎えた魚が記録されます。実績を達成すると、限定の装飾がもらえます。")),
        TutorialStep(anchor: "usage", title: String(localized: "AI利用量"),
                     body: String(localized: "どのAIでどれだけコインを得たかや、利用枠の目安を確かめられます。")),
        TutorialStep(anchor: "settings", title: String(localized: "設定"),
                     body: String(localized: "デスクトップ表示・リマインド・スクリーンセーバーはここから。魚たちをよろしくお願いします！")),
    ]
}

/// 目印を明るく残して、ほかを暗くし、吹き出しで説明する。
struct TutorialOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    @Binding var step: Int
    let onFinish: () -> Void

    var body: some View {
        GeometryReader { geo in
            let s = TutorialStep.all[step]
            let target = s.anchor.flatMap { anchors[$0] }.map { geo[$0].insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                // 目印のところだけ穴をあけた暗幕
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let target { p.addRect(target) }
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}

                if let target {
                    Rectangle().strokeBorder(PixelPalette.gold, lineWidth: 3)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                        .allowsHitTesting(false)
                }

                bubble(s)
                    .frame(width: 380)
                    .position(bubblePosition(target: target, size: geo.size))
            }
        }
        .ignoresSafeArea()
    }

    private func bubblePosition(target: CGRect?, size: CGSize) -> CGPoint {
        let w: CGFloat = 380, h: CGFloat = 180
        guard let t = target else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let x = min(max(t.midX, w / 2 + 16), size.width - w / 2 - 16)
        // 下半分の目印なら上に、上半分なら下に出す
        let y = t.midY > size.height / 2 ? t.minY - h / 2 - 16 : t.maxY + h / 2 + 16
        return CGPoint(x: x, y: min(max(y, h / 2 + 16), size.height - h / 2 - 16))
    }

    private func bubble(_ s: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.title).font(.pixel(.title3)).foregroundStyle(PixelPalette.sand)
                Spacer()
                Text("\(step + 1)/\(TutorialStep.all.count)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            }
            Text(s.body).font(.pixel(.callout)).fixedSize(horizontal: false, vertical: true)
            HStack {
                if step < TutorialStep.all.count - 1 {
                    Button("スキップ") { onFinish() }
                }
                Spacer()
                if step > 0 { Button("戻る") { step -= 1 } }
                if step < TutorialStep.all.count - 1 {
                    Button("次へ") { step += 1 }.buttonStyle(.pixelProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("はじめる") { onFinish() }.buttonStyle(.pixelProminent).keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.pixel)
        }
        .foregroundStyle(PixelPalette.text)
        .pixelPanel(padding: 16)
    }
}
