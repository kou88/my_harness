import Foundation
import Observation

@MainActor
@Observable
final class AIChatState {
    var conversations: [AIConversationSummary] = []
    var models: [AIModelCatalogItem] = []
    var hosts: [AIHostSummary] = []
    var workspaces: [AIWorkspaceSummary] = []
    var detail: AIConversationDetail?
    var liveAssistantText = ""
    var composerText = ""
    var uploadedAttachments: [AIAttachment] = []
    var searchText = ""
    var errorMessage: String?
    var informationMessage: String?
    var isLoadingList = false
    var isLoadingDetail = false
    var isLoadingCatalog = false
    var isSending = false
    var isUploading = false
    var isRenaming = false

    private let apiClient: AIAPIClient?
    private let authSession: CognitoAuthSession?
    private let configurationErrorMessage: String?
    private var streamTask: Task<Void, Never>?
    private var detailGeneration = 0
    private var lastReceivedSeqByRun: [String: Int] = [:]
    private var liveTextByRun: [String: String] = [:]

    init(
        apiClient: AIAPIClient?,
        authSession: CognitoAuthSession?,
        configurationErrorMessage: String?
    ) {
        self.apiClient = apiClient
        self.authSession = authSession
        self.configurationErrorMessage = configurationErrorMessage
    }

    var isConfigured: Bool { apiClient != nil && authSession != nil }
    var isSignedIn: Bool { authSession?.isSignedIn == true }

    var filteredConversations: [AIConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.lastMessagePreview.localizedCaseInsensitiveContains(query)
                || $0.model.localizedCaseInsensitiveContains(query)
        }
    }

    var activeRun: AIRun? { detail?.run }
    var activeApprovals: [AIApproval] {
        detail?.approvals.filter { $0.status == "pending" } ?? []
    }

    func loadList() async {
        guard let apiClient else {
            errorMessage = configurationErrorMessage ?? "AI APIが設定されていません。"
            return
        }
        guard isSignedIn else {
            errorMessage = "「次にやる」または設定画面からログインしてください。"
            return
        }
        isLoadingList = true
        defer { isLoadingList = false }
        do {
            async let conversations = apiClient.fetchConversations()
            async let models = apiClient.fetchModels()
            async let hosts = apiClient.fetchHosts()
            self.conversations = try await conversations.sorted { $0.updatedAt > $1.updatedAt }
            self.models = try await models.filter(\.isAvailable)
            self.hosts = try await hosts
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCatalog() async {
        guard let apiClient else {
            errorMessage = configurationErrorMessage ?? "AI APIが設定されていません。"
            return
        }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            async let models = apiClient.fetchModels()
            async let hosts = apiClient.fetchHosts()
            self.models = try await models.filter(\.isAvailable)
            self.hosts = try await hosts
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadWorkspaces(hostId: String) async {
        guard let apiClient else { return }
        do {
            workspaces = try await apiClient.fetchWorkspaces(hostId: hostId).filter(\.isAvailable)
        } catch {
            workspaces = []
            errorMessage = error.localizedDescription
        }
    }

    func createConversation(_ draft: AINewConversationDraft) async -> String? {
        guard let apiClient else { return nil }
        do {
            let created = try await apiClient.createConversation(
                AIAPIClient.CreateConversationRequest(
                    title: draft.title,
                    runtimeId: draft.runtimeId,
                    hostId: draft.hostId,
                    provider: draft.provider,
                    model: draft.model,
                    mode: draft.mode,
                    workspaceId: draft.workspaceId,
                    reasoningEffort: draft.reasoningEffort,
                    temporary: draft.isTemporary
                )
            )
            conversations.insert(created, at: 0)
            errorMessage = nil
            return created.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func openConversation(id: String) async {
        guard let apiClient else { return }
        detailGeneration += 1
        let generation = detailGeneration
        streamTask?.cancel()
        isLoadingDetail = true
        do {
            let value = try await apiClient.fetchConversation(id: id)
            guard generation == detailGeneration else { return }
            detail = value
            if let run = value.run, !run.status.isTerminal {
                liveAssistantText = liveTextByRun[run.id] ?? ""
            } else {
                liveAssistantText = ""
            }
            errorMessage = nil
            isLoadingDetail = false
            if let run = value.run, !run.status.isTerminal {
                startStreaming(
                    runId: run.id,
                    afterSeq: max(value.events.map(\.seq).max() ?? 0, lastReceivedSeqByRun[run.id] ?? 0)
                )
            }
        } catch {
            guard generation == detailGeneration else { return }
            isLoadingDetail = false
            errorMessage = error.localizedDescription
        }
    }

    func closeConversation() {
        detailGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        detail = nil
        liveAssistantText = ""
        uploadedAttachments = []
        composerText = ""
    }

    func send(
        branchFromMessageId: String = "",
        regenerateMessageId: String = ""
    ) async {
        guard let apiClient, let conversation = detail?.conversation else { return }
        let input = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty || !uploadedAttachments.isEmpty || !regenerateMessageId.isEmpty else { return }
        isSending = true
        let attachmentIds = uploadedAttachments.map(\.id)
        do {
            let accepted = try await apiClient.createTurn(
                conversationId: conversation.id,
                input: input,
                attachmentIds: attachmentIds,
                branchFromMessageId: branchFromMessageId,
                regenerateMessageId: regenerateMessageId
            )
            composerText = ""
            uploadedAttachments = []
            liveAssistantText = ""
            try await refreshDetailForAcceptedRun(accepted)
            startStreaming(runId: accepted.runId, afterSeq: detail?.events.map(\.seq).max() ?? 0)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func regenerate(messageId: String) async {
        composerText = ""
        await send(regenerateMessageId: messageId)
    }

    func editAndBranch(messageId: String, text: String) async {
        composerText = text
        await send(branchFromMessageId: messageId)
    }

    func stop() async {
        guard let apiClient, let run = activeRun, !run.status.isTerminal else { return }
        do {
            _ = try await apiClient.cancelRun(id: run.id)
            streamTask?.cancel()
            await openConversation(id: run.conversationId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decideApproval(id: String, decision: String) async {
        guard let apiClient, let conversationId = detail?.conversation.id else { return }
        do {
            _ = try await apiClient.decideApproval(id: id, decision: decision)
            await openConversation(id: conversationId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameConversation(title: String) async {
        guard let apiClient, let conversation = detail?.conversation else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRenaming = true
        defer { isRenaming = false }
        do {
            _ = try await apiClient.updateConversation(
                id: conversation.id,
                input: AIAPIClient.ConversationPatchRequest(
                    title: trimmed,
                    runtimeId: conversation.runtimeId,
                    hostId: conversation.hostId,
                    provider: conversation.provider,
                    model: conversation.model,
                    workspaceId: conversation.workspaceId,
                    mode: conversation.mode,
                    reasoningEffort: conversation.reasoningEffort
                )
            )
            await openConversation(id: conversation.id)
            await loadList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateModel(model: AIModelCatalogItem, effort: AIReasoningEffort) async {
        guard let apiClient, let conversation = detail?.conversation else { return }
        guard model.hostId == conversation.hostId else {
            errorMessage = "別ホストへの切り替えは新しい会話で行ってください。"
            return
        }
        do {
            _ = try await apiClient.updateConversation(
                id: conversation.id,
                input: AIAPIClient.ConversationPatchRequest(
                    title: conversation.title,
                    runtimeId: model.runtimeId,
                    hostId: model.hostId,
                    provider: model.provider,
                    model: model.model,
                    workspaceId: conversation.workspaceId,
                    mode: conversation.mode,
                    reasoningEffort: effort
                )
            )
            await openConversation(id: conversation.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteConversation(id: String) async -> Bool {
        guard let apiClient else { return false }
        do {
            try await apiClient.deleteConversation(id: id)
            conversations.removeAll { $0.id == id }
            if detail?.conversation.id == id { closeConversation() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func upload(data: Data, fileName: String, mimeType: String) async {
        guard let apiClient, let conversationId = detail?.conversation.id else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            uploadedAttachments.append(
                try await apiClient.uploadAttachment(
                    conversationId: conversationId,
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeUploadedAttachment(id: String) async {
        guard let apiClient else { return }
        do {
            try await apiClient.deleteAttachment(id: id)
            uploadedAttachments.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreAfterForeground() async {
        guard let conversationId = detail?.conversation.id else {
            await loadList()
            return
        }
        await openConversation(id: conversationId)
    }

    private func refreshDetailForAcceptedRun(_ accepted: AITurnAccepted) async throws {
        guard let apiClient else { return }
        detail = try await apiClient.fetchConversation(id: accepted.conversationId)
    }

    private func startStreaming(runId: String, afterSeq: Int) {
        guard let apiClient else { return }
        streamTask?.cancel()
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastSeq = afterSeq
            do {
                for try await event in apiClient.streamEvents(runId: runId, afterSeq: lastSeq) {
                    guard !Task.isCancelled else { return }
                    if event.seq <= lastSeq { continue }
                    lastSeq = event.seq
                    lastReceivedSeqByRun[runId] = lastSeq
                    apply(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "接続が切れました。状態を再取得します。"
            }
            guard !Task.isCancelled, let conversationId = detail?.conversation.id else { return }
            try? await Task.sleep(for: .milliseconds(500))
            await openConversation(id: conversationId)
        }
    }

    private func apply(_ event: AIEvent) {
        guard let detail else { return }
        if !detail.events.contains(where: { $0.seq == event.seq }) {
            let events = (detail.events + [event]).sorted { $0.seq < $1.seq }
            self.detail = AIConversationDetail(
                conversation: detail.conversation,
                messages: detail.messages,
                run: detail.run,
                events: events,
                approvals: detail.approvals
            )
        }

        switch event.type {
        case .messageStarted:
            liveTextByRun[event.runId] = ""
            liveAssistantText = ""
        case .messageDelta:
            let updated = (liveTextByRun[event.runId] ?? "") + event.displayText
            liveTextByRun[event.runId] = updated
            liveAssistantText = updated
        case .messageCompleted, .runStatusChanged, .approvalRequired, .approvalResolved,
             .runCompleted, .runFailed, .runCancelled:
            if event.type == .messageCompleted || event.type == .runCompleted || event.type == .runFailed || event.type == .runCancelled {
                liveTextByRun.removeValue(forKey: event.runId)
            }
            let conversationId = detail.conversation.id
            Task { await openConversation(id: conversationId) }
        default:
            break
        }
    }
}

private extension AIAPIClient {
    func createTurn(
        conversationId: String,
        input: String,
        attachmentIds: [String],
        branchFromMessageId: String,
        regenerateMessageId: String
    ) async throws -> AITurnAccepted {
        try await createTurn(
            conversationId: conversationId,
            input: CreateTurnRequest(
                input: input,
                attachmentIds: attachmentIds,
                branchFromMessageId: branchFromMessageId,
                regenerateMessageId: regenerateMessageId
            )
        )
    }
}
