import SwiftUI

struct AISharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var state: AIChatState
    @State var draft: AISharing
    @State private var failure = ""
    @State private var showContext = false
    @State private var showPower = false
    @State private var statusLoaded = false
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
                            ForEach(state.models) { item in Text(item.name + (item.online ? "" : "（Agent未接続）")).tag(item.id) }
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
                connectionSection
                Section {
                    Text("共有モード・モデルの変更は、待機中を含むすべての実行が完了してから保存できます。同じアカウントの端末すべてに適用します。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !state.sharingStatusError.isEmpty {
                        Text(state.sharingStatusError).foregroundStyle(.red).font(.callout)
                    }
                    if !validationMessage.isEmpty && state.sharingStatusError.isEmpty {
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
                        }.disabled(!statusLoaded || !state.sharingStatusError.isEmpty || !validationMessage.isEmpty || state.savingSharing || draft == state.sharing)
                            .accessibilityIdentifier("AI.sharing.save")
                    }
                }
        }
        .onAppear { synchronizeModel() }
        .onChange(of: draft.modelId) { _, _ in
            if let model = state.models.first(where: { $0.id == draft.modelId }) { draft.selectModel(model) }
            failure = ""
        }
        .onChange(of: state.models) { _, _ in synchronizeModel() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await state.refreshSharingStatus()
                statusLoaded = true
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .refreshable { await state.refreshSharingStatus(); statusLoaded = true }
        .sheet(isPresented: $showPower) {
            if let model = state.models.first(where: { $0.id == draft.modelId }) {
                AIPowerView(state: state, selectedHostId: model.hostId)
            }
        }
        .sheet(isPresented: $showContext) {
            if let model = state.models.first(where: { $0.id == draft.modelId }) {
                AIChatContextView(state: state, model: model)
            }
        }
    }

    @ViewBuilder private var connectionSection: some View {
                if let model = state.models.first(where: { $0.id == draft.modelId }) {
                    let connection = state.sharingConnection(for: model)
                    Section("接続状態") {
                        LabeledContent("PC", value: connection.pc)
                        LabeledContent("OS Agent", value: connection.agent)
                        LabeledContent("AI", value: connection.ai)
                        if !connection.message.isEmpty {
                            Text(connection.message).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("PC管理") { showPower = true }
                    }
                }
    }

    private func synchronizeModel() {
        failure = ""
        guard let model = state.models.first(where: { $0.id == draft.modelId }) else { return }
        draft.contextLength = model.initialSettings.contextLength
    }
}
