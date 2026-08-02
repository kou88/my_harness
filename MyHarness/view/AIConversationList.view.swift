import SwiftUI

struct AIConversationListView: View {
    @Environment(AppRouter.self) private var router
    let state: AIChatState
    @State private var isCreatingConversation = false
    @State private var conversationToDelete: AIConversationSummary?

    var body: some View {
        Group {
            if !state.isConfigured || !state.isSignedIn {
                ContentUnavailableView(
                    "AIを利用できません",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(state.errorMessage ?? "ログインとAPI設定を確認してください。")
                )
            } else if state.isLoadingList && state.conversations.isEmpty {
                ProgressView("会話を読み込み中")
            } else if state.filteredConversations.isEmpty {
                ContentUnavailableView {
                    Label("会話はまだありません", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("OpenAI CodexまたはOpenRouterのモデルで始められます。")
                } actions: {
                    Button("新しい会話") { isCreatingConversation = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(state.filteredConversations) { conversation in
                        Button {
                            router.push(.aiConversation(id: conversation.id))
                        } label: {
                            AIConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("削除", role: .destructive) {
                                conversationToDelete = conversation
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await state.loadList() }
            }
        }
        .navigationTitle("AI")
        .searchable(text: Bindable(state).searchText, prompt: "会話を検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新しい会話")
                .disabled(!state.isConfigured || !state.isSignedIn)
            }
        }
        .task { await state.loadList() }
        .sheet(isPresented: $isCreatingConversation) {
            AINewConversationView(state: state) { id in
                isCreatingConversation = false
                router.push(.aiConversation(id: id))
            }
        }
        .confirmationDialog(
            "この会話を削除しますか？",
            isPresented: Binding(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                guard let conversation = conversationToDelete else { return }
                Task {
                    _ = await state.deleteConversation(id: conversation.id)
                    conversationToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) { conversationToDelete = nil }
        } message: {
            Text("会話履歴、実行イベント、承認履歴を削除します。")
        }
        .alert(
            "AI",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "エラーが発生しました。")
        }
    }
}

private struct AIConversationRow: View {
    let conversation: AIConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if conversation.latestRunStatus.isActive || conversation.latestRunStatus == .failed {
                    AIStatusLabel(status: conversation.latestRunStatus)
                }
            }

            if !conversation.lastMessagePreview.isEmpty {
                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Label(conversation.provider.label, systemImage: providerIcon)
                Text("·")
                Text(conversation.model)
                    .lineLimit(1)
                Text("·")
                Label(conversation.mode.label, systemImage: conversation.mode.systemImage)
                Spacer(minLength: 4)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var providerIcon: String {
        conversation.provider == .openai ? "sparkles" : "arrow.triangle.branch"
    }
}

struct AIStatusLabel: View {
    let status: AIConversationStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .running || status == .queued {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: icon)
            }
            Text(status.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
    }

    private var icon: String {
        switch status {
        case .awaitingApproval: return "exclamationmark.shield"
        case .failed: return "exclamationmark.circle"
        case .cancelled: return "stop.circle"
        case .completed: return "checkmark.circle"
        case .idle, .queued, .running: return "circle"
        }
    }

    private var color: Color {
        switch status {
        case .awaitingApproval: return .orange
        case .failed: return .red
        case .cancelled: return .secondary
        case .completed: return .green
        case .idle, .queued, .running: return .blue
        }
    }
}

private struct AINewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    let state: AIChatState
    let onCreated: (String) -> Void

    @State private var title = ""
    @State private var selectedHostId = ""
    @State private var selectedModelId = ""
    @State private var selectedMode: AIConversationMode?
    @State private var selectedEffort: AIReasoningEffort?
    @State private var selectedWorkspaceId = ""
    @State private var isTemporary = false
    @State private var isCreating = false

    private var selectedModel: AIModelCatalogItem? {
        state.models.first { $0.id == selectedModelId && $0.hostId == selectedHostId }
    }

    private var selectedWorkspace: AIWorkspaceSummary? {
        state.workspaces.first { $0.id == selectedWorkspaceId }
    }

    private var availableModels: [AIModelCatalogItem] {
        state.models.filter { $0.hostId == selectedHostId && $0.isAvailable }
    }

    private var availableEfforts: [AIReasoningEffort] {
        selectedModel?.reasoningEfforts ?? []
    }

    private var canCreate: Bool {
        guard let mode = selectedMode,
              selectedEffort != nil,
              selectedModel != nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return mode == .consultation ? !consultationWorkspaceId.isEmpty : selectedWorkspace != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("会話タイトル", text: $title)
                    Picker("実行ホスト", selection: $selectedHostId) {
                        Text("選択してください").tag("")
                        ForEach(state.hosts.filter(\.isOnline)) { host in
                            Text(host.name).tag(host.id)
                        }
                    }
                    .onChange(of: selectedHostId) { _, value in
                        selectedModelId = ""
                        selectedEffort = nil
                        selectedWorkspaceId = ""
                        guard !value.isEmpty else { return }
                        Task { await state.loadWorkspaces(hostId: value) }
                    }
                    Picker("モデル", selection: $selectedModelId) {
                        Text("選択してください").tag("")
                        ForEach(availableModels) { model in
                            Text("\(model.displayName) · \(model.provider.label)").tag(model.id)
                        }
                    }
                    .onChange(of: selectedModelId) { _, _ in selectedEffort = nil }
                }

                Section("利用モード") {
                    Picker("モード", selection: $selectedMode) {
                        Text("選択してください").tag(AIConversationMode?.none)
                        ForEach(AIConversationMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(AIConversationMode?.some(mode))
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedMode == .work {
                        Picker("Workspace", selection: $selectedWorkspaceId) {
                            Text("選択してください").tag("")
                            ForEach(state.workspaces.filter {
                                $0.hostId == selectedHostId && $0.runtimeId == selectedModel?.runtimeId
                            }) { workspace in
                                Text(workspace.name).tag(workspace.id)
                            }
                        }
                    } else if selectedMode == .consultation {
                        Label("隔離ディレクトリ・読み取り専用・MCP無効", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("推論レベル", selection: $selectedEffort) {
                        Text("選択してください").tag(AIReasoningEffort?.none)
                        ForEach(availableEfforts, id: \.self) { effort in
                            Text(effort.label).tag(AIReasoningEffort?.some(effort))
                        }
                    }
                }

                Section {
                    Toggle("一時チャット", isOn: $isTemporary)
                        .disabled(true)
                    Text("ホスト実行の履歴を保存しない一時チャットは、安全な実行経路が整うまで利用できません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新しい会話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        create()
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
            .task { await state.loadCatalog() }
            .overlay {
                if state.isLoadingCatalog || isCreating {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func create() {
        guard let model = selectedModel,
              let mode = selectedMode,
              let effort = selectedEffort else { return }
        let workspaceId: String
        switch mode {
        case .work:
            guard let selectedWorkspace else { return }
            workspaceId = selectedWorkspace.workspaceId
        case .consultation:
            guard !consultationWorkspaceId.isEmpty else { return }
            workspaceId = consultationWorkspaceId
        }
        isCreating = true
        Task {
            let id = await state.createConversation(
                AINewConversationDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    runtimeId: model.runtimeId,
                    hostId: selectedHostId,
                    provider: model.provider,
                    model: model.model,
                    mode: mode,
                    workspaceId: workspaceId,
                    reasoningEffort: effort,
                    isTemporary: isTemporary
                )
            )
            isCreating = false
            if let id { onCreated(id) }
        }
    }

    private var consultationWorkspaceId: String {
        state.workspaces.first {
            $0.hostId == selectedHostId
                && $0.runtimeId == selectedModel?.runtimeId
                && $0.modes.contains(.consultation)
        }?.workspaceId ?? ""
    }
}
