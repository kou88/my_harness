import Foundation
import Observation

@MainActor @Observable
final class AIChatState {
    var conversations: [AIConversation] = []
    var models: [AIModel] = []
    var detail: AIConversationDetail?
    var eventsByRun: [String: [AIEvent]] = [:]
    var selectedModel: AIModel?
    var settings: AISettings?
    var composerText = ""
    var searchText = ""
    var errorMessage = ""
    var connectionMessage = ""
    var isSending = false
    var isLoading = false

    private let api: AIAPIClient?
    private let authSession: CognitoAuthSession?
    private let configurationErrorMessage: String?
    private var streamTask: Task<Void, Never>?
    private var generation = 0
    private struct Pending {
        let conversationId: String
        let title: String
        let isNew: Bool
        let submission: AIAPIClient.Submission
    }
    private var pending: Pending?
    var hasPendingSubmission: Bool { pending != nil }
    var isSignedIn: Bool { authSession?.isSignedIn == true }
    var activeRun: AIRun? { detail?.runs.last(where: { $0.isActive }) }
    var filteredConversations: [AIConversation] {
        searchText.isEmpty ? conversations : conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    var canSend: Bool {
        if pending != nil { return !isSending }
        guard let model = selectedModel, let settings else { return false }
        return model.online && model.accepts(settings) && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && activeRun == nil
    }

    init(apiClient: AIAPIClient?, authSession: CognitoAuthSession?, configurationErrorMessage: String?) {
        self.api = apiClient; self.authSession = authSession; self.configurationErrorMessage = configurationErrorMessage
    }
    func signIn() async {
        do { try await authSession?.signIn(); await loadList() }
        catch { errorMessage = error.localizedDescription }
    }
    func choose(_ model: AIModel) {
        selectedModel = model
        if let data = UserDefaults.standard.data(forKey: "agent-chat-settings-" + model.id) {
            if let saved = try? JSONDecoder().decode(AISettings.self, from: data), model.accepts(saved) {
                settings = saved
            } else {
                settings = model.initialSettings
                errorMessage = "保存済みの設定が現在のモデルに対応していません。初期設定を表示しています。設定画面で確認してください。"
            }
        } else { settings = model.initialSettings }
        UserDefaults.standard.set(model.id, forKey: "agent-chat-selected-model")
    }
    func saveSettings(_ value: AISettings) {
        guard let model = selectedModel, model.accepts(value) else { errorMessage = "このモデルでは指定した設定を使用できません。"; return }
        settings = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "agent-chat-settings-" + model.id) }
    }
    func loadList() async {
        guard let api else { errorMessage = configurationErrorMessage ?? "AI接続の設定がありません。"; return }
        guard isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let list = api.conversations()
            async let catalog = api.models()
            conversations = try await list; models = try await catalog
            errorMessage = ""
            if let id = selectedModel?.id ?? UserDefaults.standard.string(forKey: "agent-chat-selected-model"),
               let model = models.first(where: { $0.id == id }) { choose(model) }
            else { selectedModel = nil; settings = nil }
        } catch { errorMessage = error.localizedDescription }
    }
    func newChat() { closeConversation(); detail = nil; composerText = "" }
    func openConversation(id: String) async {
        guard let api else { return }
        generation += 1; let token = generation
        streamTask?.cancel(); isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let loaded = try await api.conversation(id)
            guard token == generation else { return }
            detail = loaded; errorMessage = ""
            if let last = loaded.runs.last, let model = models.first(where: { $0.id == last.modelId }) { choose(model) }
            if let run = loaded.runs.last { await loadTrace(run.id, generation: token) }
            if let active = detail?.runs.last(where: { $0.isActive }), token == generation { observe(active.id, generation: token) }
        } catch { if token == generation { errorMessage = error.localizedDescription } }
    }
    func closeConversation() { generation += 1; streamTask?.cancel(); streamTask = nil; connectionMessage = "" }
    func restoreAfterForeground() async {
        await loadList()
        if let detail { await openConversation(id: detail.id) }
    }

    func send(conversationId: String?) async -> String? {
        guard let api, canSend else { return nil }
        if pending == nil {
            guard let selectedModel, let settings else { return nil }
            let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
            pending = Pending(conversationId: conversationId ?? UUID().uuidString.lowercased(), title: String(text.prefix(80)), isNew: conversationId == nil,
                submission: AIAPIClient.Submission(id: UUID().uuidString.lowercased(), modelId: selectedModel.id, inputText: text, settings: settings))
        }
        guard let pending else { return nil }
        isSending = true; errorMessage = ""
        defer { isSending = false }
        do {
            if pending.isNew { _ = try await api.create(id: pending.conversationId, title: pending.title) }
            _ = try await api.send(conversation: pending.conversationId, submission: pending.submission)
            self.pending = nil; composerText = ""
            await openConversation(id: pending.conversationId)
            return pending.conversationId
        } catch let error as AIAPIClient.APIError {
            if case .response(let status, _) = error, (400..<500).contains(status) { self.pending = nil }
            errorMessage = error.localizedDescription
        } catch { errorMessage = "送信結果を確認できません。同じ実行IDで再送できます。\n" + error.localizedDescription }
        return nil
    }
    func cancel() async {
        guard let api, let run = activeRun else { return }
        do { replaceRun(try await api.cancel(run.id)) }
        catch { errorMessage = error.localizedDescription }
    }
    func delete(_ id: String) async -> Bool {
        guard let api else { return false }
        do { try await api.delete(id); closeConversation(); detail = nil; await loadList(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func rename(_ title: String) async {
        guard let api, let detail else { return }
        do { self.detail = try await api.rename(detail.id, title: title) }
        catch { errorMessage = error.localizedDescription }
    }
    func trace(_ runId: String) -> AITrace { AITrace(events: eventsByRun[runId] ?? []) }
    func loadTrace(_ runId: String) async { await loadTrace(runId, generation: generation) }
    private func loadTrace(_ runId: String, generation token: Int) async {
        guard let api else { return }
        do {
            var cursor = eventsByRun[runId]?.last?.seq ?? 0
            while !Task.isCancelled && token == generation {
                let page = try await api.events(runId, after: cursor)
                guard token == generation else { return }
                replaceRun(page.run)
                for event in page.events { appendTrace(runId, event) }
                guard let last = page.events.last else { break }
                cursor = last.seq
                if cursor >= page.run.lastSeq { break }
            }
        } catch { if token == generation { errorMessage = error.localizedDescription } }
    }
    private func replaceRun(_ run: AIRun) {
        guard let index = detail?.runs.firstIndex(where: { $0.id == run.id }) else { return }
        // An older HTTP snapshot must never roll back a newer streamed cursor.
        if let current = detail?.runs[index], current.lastSeq > run.lastSeq { return }
        detail?.runs[index] = run
    }
    private func appendTrace(_ runId: String, _ event: AIEvent) {
        if let last = eventsByRun[runId]?.last, last.seq >= event.seq { return }
        eventsByRun[runId, default: []].append(event)
    }
    private func observe(_ runId: String, generation token: Int) {
        guard let api else { return }
        streamTask?.cancel()
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && token == self.generation {
                do {
                    let cursor = self.eventsByRun[runId]?.last?.seq ?? 0
                    for try await event in api.stream(runId, after: cursor) {
                        guard token == self.generation, !Task.isCancelled else { return }
                        self.connectionMessage = ""
                        if let index = self.detail?.runs.firstIndex(where: { $0.id == runId }) {
                            try self.detail?.runs[index].apply(event)
                        }
                        self.appendTrace(runId, event)
                    }
                    let run = try await api.run(runId)
                    guard token == self.generation else { return }
                    self.replaceRun(run)
                    if !run.isActive {
                        await self.loadTrace(runId, generation: token)
                        self.connectionMessage = ""
                        return
                    }
                } catch {
                    if Task.isCancelled || token != self.generation { return }
                    self.connectionMessage = "接続を再確立中（PCでの実行は継続）"
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
