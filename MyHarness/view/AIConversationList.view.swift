import SwiftUI

struct AIConversationListView: View {
    @Bindable var state: AIChatState
    var body: some View { AIChatScreen(state: state, conversationId: nil) }
}

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AIModel
    @State var draft: AISettings
    let onSave: (AISettings) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(model.name).font(.subheadline); Text(model.hostName).foregroundStyle(.secondary) }
                Section("推論設定") {
                    Picker("Reasoning effort", selection: $draft.reasoningEffort) {
                        ForEach(model.reasoningEfforts, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("コンテキスト", selection: $draft.contextLength) {
                        ForEach(model.contextLengths, id: \.self) { Text("\($0 / 1024)K（\($0.formatted()) tokens）").tag($0) }
                    }
                    HStack {
                        Text("出力上限")
                        TextField("tokens", value: $draft.maxOutputTokens, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("出力上限トークン数")
                    }
                    Text("256〜\(model.maxOutputTokens.formatted()) tokens").font(.caption).foregroundStyle(.secondary)
                    Text("出力上限には思考用トークンも含みます。設定はモデルごとに保存します。").font(.caption).foregroundStyle(.secondary)
                    if !model.accepts(draft) { Text("指定した出力上限がモデルの範囲外、または推論量に対して不足しています。").foregroundStyle(.red) }
                }
            }
            .navigationTitle("モデル設定").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(draft); dismiss() }.disabled(!model.accepts(draft)) }
            }
        }.presentationDetents([.medium, .large])
    }
}
