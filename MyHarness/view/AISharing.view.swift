import SwiftUI

struct AISharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    @State var draft: AISharing
    @State private var failure = ""
    @State private var showContext = false
    private var validationMessage: String { draft.validationMessage(models: state.models) }

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
                        if state.models.contains(where: { $0.id == draft.modelId }) {
                            Button { showContext = true } label: {
                                LabeledContent("コンテキスト", value: "\(draft.contextLength / 1024)K")
                            }.accessibilityIdentifier("AI.sharing.context")
                        }
                        Text("モデルとコンテキスト長は共有チャット共通です。推論量・出力上限は会話ごとに変更できます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("共有モード・モデルの変更は、待機中を含むすべての実行が完了してから保存できます。同じアカウントの端末すべてに適用します。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !validationMessage.isEmpty {
                        Text(validationMessage).foregroundStyle(.red).font(.callout)
                            .accessibilityIdentifier("AI.sharing.validation")
                    }
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
                        }.disabled(!validationMessage.isEmpty || state.savingSharing || draft == state.sharing)
                            .accessibilityIdentifier("AI.sharing.save")
                    }
                }
        }
        .onAppear { synchronizeModel() }
        .onChange(of: draft.modelId) { _, _ in synchronizeModel() }
        .onChange(of: state.models) { _, _ in synchronizeModel() }
        .sheet(isPresented: $showContext) {
            if let model = state.models.first(where: { $0.id == draft.modelId }) {
                AIChatContextView(state: state, model: model)
            }
        }
    }

    private func synchronizeModel() {
        failure = ""
        guard let model = state.models.first(where: { $0.id == draft.modelId }) else { return }
        draft.selectModel(model)
    }
}
