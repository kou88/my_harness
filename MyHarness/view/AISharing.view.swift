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
                    Text("同じモデルを共有し、選択した件数のチャットを同時に実行します。OFFでは会話ごとにモデルを選び、順番に実行します。")
                }
                if draft.enabled {
                    Section("共通設定") {
                        Picker("モデル", selection: $draft.modelId) {
                            Text("モデルを選択").tag("")
                            ForEach(state.models) { item in Text(item.name + (item.online ? "" : "（オフライン）")).tag(item.id) }
                        }.pickerStyle(.navigationLink).accessibilityIdentifier("AI.sharing.model")
                        Picker("同時実行数", selection: $draft.maxConcurrentRuns) {
                            ForEach(1...30, id: \.self) { count in Text("\(count)件").tag(count) }
                        }.pickerStyle(.navigationLink).accessibilityIdentifier("AI.sharing.concurrency")
                        if draft.maxConcurrentRuns > 5 {
                            Label("6件以上は負荷が高く、メモリ不足・速度低下・実行失敗の可能性があります。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange).accessibilityIdentifier("AI.sharing.loadWarning")
                        }
                        Picker("1会話のコンテキスト", selection: $draft.contextLength) {
                            ForEach([8192, 16384, 32768, 65536, 131072, 262144], id: \.self) { context in
                                Text("\(context / 1024)K").tag(context)
                            }
                        }.accessibilityIdentifier("AI.sharing.context")
                        Text("合計256Kまで。30件は8K、16件は16K、8件は32K、4件は64K、2件は128Kが上限です。上限を超えたチャットは順番待ちになります。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !draft.capacityIsValid {
                            Text("合計256Kを超えています。同時実行数かコンテキスト長を変更してください。")
                                .font(.caption).foregroundStyle(.red).accessibilityIdentifier("AI.sharing.capacityError")
                        }
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
