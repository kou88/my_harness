import SwiftUI

struct AIConversationListView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var state: AIChatState
    @State private var showSettings = false

    var body: some View {
        List {
            if !state.isSignedIn {
                ContentUnavailableView("AIチャット", systemImage: "bubble.left.and.text.bubble.right", description: Text("ログインしてUbuntuのAgentに依頼できます。"))
                Button("ログイン") { Task { await state.signIn() } }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("何をしますか？").font(.title2.bold())
                        AIModelMenu(state: state, showSettings: $showSettings)
                        AIComposer(state: state, conversationId: nil) { id in
                            router.aiPath = [.aiConversation(id: id)]
                        }
                    }.padding(.vertical, 8)
                }
                Section("会話") {
                    if state.isLoading && state.conversations.isEmpty { ProgressView("読み込み中") }
                    else if state.filteredConversations.isEmpty { Text("会話はまだありません").foregroundStyle(.secondary) }
                    ForEach(state.filteredConversations) { conversation in
                        NavigationLink(value: AppRoute.aiConversation(id: conversation.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title).lineLimit(2)
                                Text(String(conversation.updatedAt.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("削除", role: .destructive) { Task { _ = await state.delete(conversation.id) } }
                        }
                    }
                }
            }
            if !state.errorMessage.isEmpty { Section { Text(state.errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI")
        .searchable(text: $state.searchText, prompt: "会話を検索")
        .task { await state.loadList() }
        .onAppear { state.closeConversation(); state.detail = nil }
        .refreshable { await state.loadList() }
        .sheet(isPresented: $showSettings) {
            if let model = state.selectedModel, let settings = state.settings {
                AISettingsView(model: model, draft: settings) { state.saveSettings($0) }
            }
        }
    }
}

struct AIModelMenu: View {
    @Bindable var state: AIChatState
    @Binding var showSettings: Bool
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if state.models.isEmpty { Text("利用可能なモデルがありません") }
                ForEach(state.models) { model in
                    Button { state.choose(model) } label: {
                        Label(model.name + (model.online ? "" : " · オフライン"), systemImage: model.id == state.selectedModel?.id ? "checkmark" : "cpu")
                    }.disabled(!model.online)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                    Text(state.selectedModel?.name ?? "モデルを選択").lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2)
                }.font(.subheadline)
            }.accessibilityIdentifier("AI.modelMenu")
            .disabled(state.activeRun != nil || state.hasPendingSubmission)
            Spacer(minLength: 0)
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("モデル設定").accessibilityIdentifier("AI.settings")
                .disabled(state.selectedModel == nil || state.activeRun != nil || state.hasPendingSubmission)
        }
    }
}

struct AIComposer: View {
    @Bindable var state: AIChatState
    let conversationId: String?
    let onSent: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let settings = state.settings {
                Text("推論 \(settings.reasoningEffort) · コンテキスト \(settings.contextLength / 1024)K · 出力 \(settings.maxOutputTokens.formatted())")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("調べる、コードを書く、ファイルを扱う", text: $state.composerText, axis: .vertical)
                    .lineLimit(2...7).textFieldStyle(.plain).accessibilityIdentifier("AI.prompt")
                    .disabled(state.hasPendingSubmission)
                if let run = state.activeRun {
                    Button { Task { await state.cancel() } } label: {
                        Image(systemName: "stop.fill").frame(width: 34, height: 34)
                    }.disabled(run.cancelRequested).accessibilityLabel("実行を停止")
                } else {
                    Button {
                        Task { if let id = await state.send(conversationId: conversationId) { onSent(id) } }
                    } label: {
                        if state.isSending { ProgressView().frame(width: 34, height: 34) }
                        else { Image(systemName: state.hasPendingSubmission ? "arrow.clockwise" : "arrow.up").font(.headline).frame(width: 34, height: 34) }
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                    .disabled(!state.canSend).accessibilityLabel(state.hasPendingSubmission ? "同じ依頼を再送" : "送信")
                    .accessibilityIdentifier("AI.send")
                }
            }
            if state.hasPendingSubmission { Text("送信結果が未確認です。再送しても同じ依頼を重複実行しません。").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.22)))
    }
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
