import SwiftUI

@MainActor
struct WeeklyExportView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("今週分")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WeeklyExportView(text: """
        my harness
        2026/07/06 - 2026/07/10

        月 2026/07/06
        - [x] 明日の服を出す
        - [x] 睡眠メモ
          - log: 23:30に寝る準備まで完了
        """)
    }
}

