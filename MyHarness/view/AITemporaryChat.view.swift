import SwiftUI

struct AITemporaryChatView: View {
    @Environment(\.dismiss) private var dismiss
    let state: AIChatState
    let onSaved: (String) -> Void

    @State private var id = UUID().uuidString.lowercased()
    @State private var turns: [AITemporaryTurn] = []
    @State private var draft = ""
    @State private var modelId: String
    @State private var task: Task<Void, Never>?
    @State private var saving = false
    @State private var saveAttempted = false
    @State private var confirmDiscard = false
    @State private var error = ""
    @FocusState private var focused: Bool

    init(state: AIChatState, onSaved: @escaping (String) -> Void) {
        self.state = state
        self.onSaved = onSaved
        _modelId = State(initialValue: state.selectedModel?.id ?? "")
    }
    private var model: AIModel? {
        let selected = state.sharedMode ? state.sharing?.modelId : modelId
        return state.models.first { $0.id == selected }
    }
    private var settings: AISettings? {
        guard let model else { return nil }
        var value = state.selectedModel?.id == model.id ? state.settings ?? model.initialSettings : model.initialSettings
        if let sharing = state.sharing, sharing.enabled { value.contextLength = sharing.contextLength }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if turns.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle)
                        Text("閉じると会話を破棄します。残したいときは「履歴に保存」を選んでください。")
                            .font(.callout).multilineTextAlignment(.center)
                    }.foregroundStyle(.secondary).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                ForEach(turns) { turn in AITemporaryTurnView(turn: turn).id(turn.id) }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: turns.count) { if let last = turns.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if task != nil && !saving {
                    HStack { ProgressView(); Text("回答を待っています") }.font(.caption).padding(6)
                }
                let notice = !error.isEmpty ? error : state.models.isEmpty ? state.errorMessage : ""
                if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Menu {
                            ForEach(state.models) { item in
                                Button(item.name + (item.online ? "" : "（オフライン）")) { modelId = item.id }
                                    .disabled(!item.online)
                            }
                        } label: {
                            Label(model?.name ?? "モデルを選択", systemImage: state.sharedMode ? "lock.fill" : "cpu")
                                .lineLimit(1)
                        }.disabled(task != nil || state.sharedMode || saveAttempted)
                        Spacer()
                        Text("テキストのみ").foregroundStyle(.secondary)
                    }.font(.caption)
                    if let model, !model.online { Text("実行PCがオフラインです").font(.caption).foregroundStyle(.secondary) }
                    HStack(alignment: .bottom) {
                        TextField("一時メッセージ", text: $draft, axis: .vertical)
                            .lineLimit(1...6).focused($focused).disabled(task != nil || saveAttempted)
                            .accessibilityIdentifier("AI.temporary.prompt")
                        if task != nil && !saving {
                            Button { task?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                                .accessibilityLabel("回答を停止")
                        } else {
                            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                                .disabled(task != nil || saveAttempted || model?.online != true || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityLabel("送信").accessibilityIdentifier("AI.temporary.send")
                        }
                    }
                }.padding(14).background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 18)).padding(10)
            }
            .navigationTitle("一時チャット").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { if turns.isEmpty && draft.isEmpty { dismiss() } else { confirmDiscard = true } }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if saving { ProgressView() } else { Text("履歴に保存") }
                    }.disabled(task != nil || turns.isEmpty)
                        .accessibilityIdentifier("AI.temporary.save")
                }
            }
            .confirmationDialog("一時チャットを破棄しますか？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("破棄して閉じる", role: .destructive) { dismiss() }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(task != nil || !turns.isEmpty || !draft.isEmpty)
        .onDisappear { task?.cancel() }
        .task { await state.loadList() }
    }

    private func send() {
        guard task == nil, !saveAttempted, let model, let settings else { return }
        focused = false
        error = ""
        task = Task {
            defer { task = nil }
            do {
                let turn = try await state.temporaryReply(model: model, settings: settings, turns: turns, text: draft)
                try Task.checkCancellation()
                turns.append(turn)
                draft = ""
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        guard task == nil, !turns.isEmpty else { return }
        saving = true
        saveAttempted = true
        error = ""
        task = Task {
            defer { task = nil; saving = false }
            do {
                let saved = try await state.saveTemporaryChat(id: id, turns: turns, model: model, settings: settings, draft: draft)
                onSaved(saved)
            } catch { if !Task.isCancelled { self.error = "保存を確認できません。「履歴に保存」で再試行できます。\\n" + error.localizedDescription } }
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
