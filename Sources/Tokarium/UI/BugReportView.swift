import AppKit
import SwiftUI

/// 不具合の報告。内容を確かめてから、ユーザー自身がブラウザやメールで送る。
struct BugReportView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let crash: Diagnostics.CrashInfo?
    @State private var details = ""
    @State private var includeLog = true
    @State private var copied = false

    private var diagnostics: String { Diagnostics.report(store: store, crash: crash, includeLog: includeLog) }

    private var reportBody: String {
        let what = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ## \(String(localized: "起きたこと"))
        \(what.isEmpty ? String(localized: "（未記入）") : what)

        ## \(String(localized: "診断情報"))
        ```
        \(diagnostics)
        ```
        """
    }

    private var title: String {
        crash != nil ? String(localized: "[クラッシュ] Tokarium が予期せず終了した") : String(localized: "[不具合] ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if crash != nil {
                Label("前回、Tokarium が予期せず終了しました", systemImage: "exclamationmark.triangle.fill")
                    .font(.pixel(.title2)).foregroundStyle(.orange)
                Text("ご迷惑をおかけしました。よければ報告を送って、改善に協力してください。水槽のデータはそのまま残っています。")
                    .foregroundStyle(PixelPalette.dim)
            } else {
                Text("不具合を報告").font(.pixel(.title2))
            }
            Text("何をしていたときに起きましたか？").font(.pixel(.headline))
            TextEditor(text: $details)
                .font(.pixel(.body))
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            Toggle("最近のログを添える", isOn: $includeLog)
            DisclosureGroup("送る内容を確認する") {
                ScrollView {
                    Text(diagnostics)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
            }
            Text("送るのはアプリの版、macOSの版、設定、水槽の数、エラーの内容だけです。AIとの会話本文やファイルの中身は含みません。送る前にブラウザやメールで内容を確認・編集できます。")
                .font(.pixel(.caption)).foregroundStyle(PixelPalette.dim)
            HStack {
                Button(copied ? "コピーしました" : "内容をコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reportBody, forType: .string)
                    copied = true
                }
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                if Diagnostics.feedbackEmail != nil {
                    Button("メールで報告…") {
                        Diagnostics.openMail(subject: title, body: reportBody)
                        dismiss()
                    }
                }
                Button("GitHub で報告…") {
                    Diagnostics.openIssue(title: title, body: reportBody)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
