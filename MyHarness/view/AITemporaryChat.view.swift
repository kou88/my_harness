import SwiftUI

struct AITemporaryChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: AIChatState
    let parent: AIChatState
    let onSaved: (String) -> Void
    @State private var models = false
    @State private var settings = false
    @State private var closing = false
    @State private var confirming = false

    init(state: AIChatState, onSaved: @escaping (String) -> Void) {
        parent = state
        _state = State(initialValue: state.temporaryState())
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let detail = state.detail {
                    AIMessageList(detail: detail, state: state)
                } else {
                    VStack(spacing: 18) {
                        Text("閉じると削除します。接続が切れた場合は、最終接続から15分で削除対象になります。")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        AIHarnessSetup(state: state)
                        if state.harness == .opencode {
                            Text("GitHubに作成したPR・ブランチは残ります。").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !state.connectionMessage.isEmpty { Text(state.connectionMessage).font(.caption).foregroundStyle(.secondary) }
                if !state.errorMessage.isEmpty { Text(state.errorMessage).font(.caption).foregroundStyle(.red) }
                AIChatComposer(state: state, conversationId: state.detail?.id, onModels: { models = true },
                               onSettings: { settings = true }, onSent: { _ in }).padding(8)
            }
            .disabled(closing)
            .navigationTitle("一時チャット").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        if state.detail == nil && !state.hasPendingSubmission && state.composerText.isEmpty && state.composerAttachments.isEmpty { dismiss() }
                        else { confirming = true }
                    }.disabled(closing || state.isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("履歴に保存") { finish(save: true) }
                        .disabled(closing || state.isSending || state.hasPendingSubmission || !state.temporaryCreated)
                        .accessibilityIdentifier("AI.temporary.save")
                }
            }
            .confirmationDialog("一時チャットを破棄しますか？", isPresented: $confirming, titleVisibility: .visible) {
                Button("破棄して閉じる", role: .destructive) { finish(save: false) }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(isPresented: $models) { AIModelPicker(state: state, onClose: { models = false }) }
            .sheet(isPresented: $settings) {
                if let model = state.selectedModel, let draft = state.settings {
                    AISettingsView(state: state, model: model, draft: draft, sharedMode: state.sharedMode) { state.saveSettings($0) }
                }
            }
        }
        .interactiveDismissDisabled()
        .task { await state.loadList() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await state.renewTemporarySession()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { state.stopTemporaryObservation() }
    }

    private func finish(save: Bool) {
        guard !closing else { return }
        closing = true
        Task {
            defer { closing = false }
            do {
                if save {
                    let saved = try await state.keepTemporarySession()
                    parent.adoptSavedSession(from: state, detail: saved)
                    onSaved(saved.id)
                }
                else { try await state.discardTemporarySession(); dismiss() }
            } catch { state.errorMessage = error.localizedDescription }
        }
    }
}

struct AITemporaryTurnView: View {
    let turn: AITemporaryTurn
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 32)
                AIChatMessageText(text: turn.inputText, kind: .message, copyID: turn.id + ".input")
                    .padding(12).background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 18))
            }
            Text(turn.model).font(.caption.bold()).foregroundStyle(.secondary)
            AIChatMessageText(text: turn.outputText, kind: .markdown, copyID: turn.id + ".output")
            Button { UIPasteboard.general.string = turn.outputText } label: { Image(systemName: "doc.on.doc") }
                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("回答をコピー")
        }
    }
}
