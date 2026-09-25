import AppKit
import SwiftUI

/// このアプリについて（版・著作権・同梱しているソフトウェアのライセンス）。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shown: String?

    struct Notice: Identifiable {
        let id: String
        let name: String
        let detail: String
        let file: String
    }

    static let notices: [Notice] = [
        Notice(id: "tokarium", name: "Tokarium", detail: "MIT License · © 2026 yuuyuu86", file: "Tokarium"),
        Notice(id: "sparkle", name: "Sparkle", detail: String(localized: "自動アップデート · MIT License"), file: "Sparkle"),
        Notice(id: "dotgothic16", name: "DotGothic16", detail: String(localized: "ドット絵フォント · SIL Open Font License 1.1 · © The DotGothic16 Project Authors"),
               file: "DotGothic16-OFL"),
    ]

    static func licenseText(_ file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt", subdirectory: "Licenses")
                ?? Bundle.main.url(forResource: file, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "ライセンスの文面が見つかりません。")
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().interpolation(.none).frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tokarium").font(.pixel(.title))
                    Text("バージョン \(Diagnostics.appVersion)").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                    Text("© 2026 yuuyuu86 · MIT License").font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                }
            }
            HStack {
                Button("GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/yuuyuu86/Tokarium")!) }
                Button("プライバシーについて") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/yuuyuu86/Tokarium/blob/main/PRIVACY.md")!)
                }
            }
            Text("謝辞・ライセンス").font(.pixel(.headline)).foregroundStyle(PixelPalette.sand)
            ForEach(Self.notices) { n in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.name).font(.pixel(.callout))
                            Text(n.detail).font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
                        }
                        Spacer()
                        Button(shown == n.id ? "閉じる" : "全文を見る") { shown = shown == n.id ? nil : n.id }
                    }
                    if shown == n.id {
                        ScrollView {
                            Text(Self.licenseText(n.file))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 180)
                        .padding(8)
                        .background(PixelPalette.deeper)
                    }
                }
                .padding(10)
                .pixelInset()
            }
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
