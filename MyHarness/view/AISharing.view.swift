import SwiftUI

struct AISharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    @State var draft: AISharing
    @State private var failure = ""
    private var model: AIModel? { state.models.first { $0.id == draft.modelId } }
    private var valid: Bool { draft.capacityIsValid && (!draft.enabled || (model?.online == true && model!.contextLengths.contains(draft.contextLength))) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("共有モード", isOn: $draft.enabled).accessibilityIdentifier("AI.sharing.enabled")
                } footer: {
                    Text("ONではチャットのモデル・コンテキストを共通化します。GPUの同時推論数は「GPUの実行枠」で管理し、OFFでも空き枠を利用します。")
                }
                if draft.enabled {
                    Section("共通設定") {
                        Picker("モデル", selection: $draft.modelId) {
                            Text("モデルを選択").tag("")
                            ForEach(state.models) { item in Text(item.name + (item.online ? "" : "（オフライン）")).tag(item.id) }
                        }.pickerStyle(.navigationLink).accessibilityIdentifier("AI.sharing.model")
                        Text("コンテキストは「GPUの実行枠」で変更できます。現在 \(draft.contextLength / 1024)K。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("モデルとコンテキスト長はチャット内では固定。推論量・出力上限は会話ごとに変更できます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("変更は待機中を含むすべての実行が完了してから保存できます。同じアカウントの端末すべてに適用します。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !failure.isEmpty { Text(failure).foregroundStyle(.red).font(.callout) }
                }
            }.disabled(state.savingSharing)
                .navigationTitle("共有モード").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            Task {
                                if await state.saveSharing(draft) { dismiss() }
                                else { failure = state.errorMessage }
                            }
                        }.disabled(!valid || state.savingSharing || draft == state.sharing)
                    }
                }
        }
    }
}
