import SwiftUI

/// 初回起動: ルールの説明 → 読み取り範囲の許可 → 表示方法の選択。
struct OnboardingView: View {
    @Environment(GameStore.self) private var store
    @State private var step = 0
    @State private var enabled: Set<String> = []
    @State private var mode: DisplayMode = .window

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0: welcome
            case 1: sources
            default: display
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("戻る") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("次へ") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("はじめる") { store.completeOnboarding(enabled: enabled, mode: mode) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 600, height: 620)
        .onAppear { enabled = store.detectedSources.filter { id in UsageReaders.all.first { $0.info.id == id }?.info.kind == .measured } }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FishIcon(speciesID: "neon").frame(width: 60, height: 30)
                Text("Tokarium へようこそ").font(.pixel(.largeTitle))
            }
            AquariumView(store: store)
                .frame(height: 170)
                .overlay(Rectangle().strokeBorder(PixelPalette.sand, lineWidth: 3))
            VStack(alignment: .leading, spacing: 8) {
                bullet("circle.hexagongrid", String(localized: "AIを使うと、このMacに残る利用記録からコインが貯まります。コインで魚や装飾を買えます。"))
                bullet("clock", String(localized: "コインになるのは、いまから後の利用だけです。これまでの利用は含みません。"))
                bullet("leaf", String(localized: "餌やりと水換えを忘れると魚は弱り、さらに放っておくと死んでしまいます。餌は1日1〜2回が目安です。"))
                bullet("heart", String(localized: "よくお世話すると魚は成長し、元気な成魚が2匹以上いると稚魚が生まれることも。汚れた水が続くと病気になります。魚には寿命もあります。"))
                bullet("moon.zzz", String(localized: "Macを閉じている間も時間は進みますが、反映するのは最大48時間分で、それだけで死ぬことはありません。"))
                bullet("gift", String(localized: "最初にネオンテトラ1匹と \(Catalog.initialCoins) コインをプレゼントします。"))
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("読み取る利用記録を選んでください").font(.pixel(.title2))
            Text("読み取り専用で、トークン数・時刻・重複判定用のIDだけを使います。会話の本文や認証情報は保存しません。")
                .font(.pixel(.callout)).foregroundStyle(PixelPalette.dim)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(UsageReaders.all, id: \.info.id) { r in
                        let detected = store.detectedSources.contains(r.info.id)
                        Toggle(isOn: Binding(get: { enabled.contains(r.info.id) },
                                             set: { if $0 { enabled.insert(r.info.id) } else { enabled.remove(r.info.id) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(r.info.name).fontWeight(.semibold)
                                    KindBadge(kind: r.info.kind)
                                    Text(detected ? "見つかりました" : "未検出").font(.pixel(.caption))
                                        .foregroundStyle(detected ? .green : .secondary)
                                }
                                Text("場所: \(r.info.locations.joined(separator: "、"))").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                                Text("内容: \(r.info.reads)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Text("ChatGPT デスクトップや Claude デスクトップのチャットは、トークン数がMac内に残らないため読み取れません。あとから設定で変更できます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        }
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("水槽の表示方法").font(.pixel(.title2))
            HStack(spacing: 8) {
                ForEach(DisplayMode.allCases) { m in
                    Button(m.label) { mode = m }.buttonStyle(PixelButtonStyle(prominent: mode == m))
                }
            }
            Text(mode == .desktop
                 ? "デスクトップの壁紙の上に水槽が泳ぎます。Macの壁紙設定は変更しません。アイコンはそのまま使えます。お世話はウィンドウかメニューバーのアイコンから。"
                 : "サイズを変えられる普通のウィンドウで水槽を表示します。")
                .foregroundStyle(PixelPalette.dim)
            Text("あとから設定でいつでも切り替えられます。魚や装飾はそのまま引き継がれます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
