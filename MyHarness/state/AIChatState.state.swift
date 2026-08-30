import Foundation
import Observation

@MainActor @Observable
final class AIChatState {
    // Navigation changes only the visible session. Each conversation owns its
    // draft, submission and stream so delayed responses cannot switch the UI.
    @MainActor @Observable fileprivate final class Session {
        var detail: AIConversationDetail?
        var model: AIModel?
        var settings: AISettings?
        var draft = ""
        var error = ""
        var connection = ""
        var sending = false
        var loading = false
        var loadGeneration = 0
        var pending: Pending?
        var activeRun: AIRun? { detail?.runs.last(where: { $0.isActive }) }
    }
    fileprivate struct Pending {
        let conversationId: String
        let title: String
        let isNew: Bool
        let submission: AIAPIClient.Submission
    }
    var conversations: [AIConversation] = []
    var models: [AIModel] = []
    var eventsByRun: [String: [AIEvent]] = [:]
    var searchText = ""
    private var sessions: [String: Session] = [:]
    private var newSession: Session
    private var visible: Session
    private var listLoading = false
    private var listGeneration = 0
    private var streams: [String: Task<Void, Never>] = [:]
    private let api: AIAPIClient?
    private let authSession: CognitoAuthSession?
    private let configurationErrorMessage: String?
    private(set) var isSignedIn: Bool

    var detail: AIConversationDetail? { visible.detail }
    var selectedModel: AIModel? { visible.model }
    var settings: AISettings? { visible.settings }
    var composerText: String { get { visible.draft } set { visible.draft = newValue } }
    var errorMessage: String { get { visible.error } set { visible.error = newValue } }
    var connectionMessage: String { visible.connection }
    var isSending: Bool { visible.sending }
    var isLoading: Bool { listLoading || visible.loading }
    var hasPendingSubmission: Bool { visible.pending != nil }
    var activeRun: AIRun? { visible.activeRun }
    var filteredConversations: [AIConversation] {
        searchText.isEmpty ? conversations : conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    var canSend: Bool {
        if visible.pending != nil { return !isSending }
        guard let model = selectedModel, let settings else { return false }
        return model.online && model.accepts(settings) && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !visible.loading && activeRun == nil
    }

    init(apiClient: AIAPIClient?, authSession: CognitoAuthSession?, configurationErrorMessage: String?) {
        api = apiClient; self.authSession = authSession; self.configurationErrorMessage = configurationErrorMessage
        isSignedIn = authSession?.isSignedIn == true
        let initial = Session(); newSession = initial; visible = initial
    }
    func signIn() async {
        do { try await authSession?.signIn(); await loadList() }
        catch { errorMessage = error.localizedDescription }
    }
    func choose(_ model: AIModel) {
        configure(visible, model: model)
        UserDefaults.standard.set(model.id, forKey: "agent-chat-selected-model")
    }
    private func configure(_ session: Session, model: AIModel) {
        session.model = model
        if let data = UserDefaults.standard.data(forKey: "agent-chat-settings-" + model.id) {
            if let saved = try? JSONDecoder().decode(AISettings.self, from: data), model.accepts(saved) {
                session.settings = saved
            } else {
                session.settings = model.initialSettings
                session.error = "保存済みの設定が現在のモデルに対応していません。初期設定を表示しています。設定画面で確認してください。"
            }
        } else { session.settings = model.initialSettings }
    }
    private func configureNew(_ session: Session) {
        if let id = UserDefaults.standard.string(forKey: "agent-chat-selected-model"), let model = models.first(where: { $0.id == id }) {
            configure(session, model: model)
        }
    }
    func saveSettings(_ value: AISettings) {
        guard let model = selectedModel, model.accepts(value) else { errorMessage = "このモデルでは指定した設定を使用できません。"; return }
        visible.settings = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "agent-chat-settings-" + model.id) }
    }
    func loadList() async {
        isSignedIn = authSession?.isSignedIn == true
        guard let api else { errorMessage = configurationErrorMessage ?? "AI接続の設定がありません。"; return }
        guard isSignedIn else { return }
        listGeneration += 1; let token = listGeneration
        listLoading = true
        defer { if token == listGeneration { listLoading = false } }
        do {
            async let list = api.conversations()
            async let catalog = api.models()
            let loaded = try await (list, catalog)
            guard token == listGeneration else { return }
            conversations = loaded.0; models = loaded.1
            for session in Array(sessions.values) + [newSession] {
                if let model = session.model {
                    session.model = models.first(where: { $0.id == model.id })
                    if session.model == nil { session.error = "選択中のモデルが一覧にありません。モデルを選び直してください。" }
                }
            }
            if visible.model == nil && visible.settings == nil { configureNew(visible) }
        } catch { if token == listGeneration && !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func newChat() {
        if visible !== newSession { visible = newSession }
        if visible.model == nil && visible.settings == nil { configureNew(visible) }
    }
    func openConversation(id: String) async {
        let session: Session
        if let existing = sessions[id] { session = existing }
        else { session = Session(); sessions[id] = session }
        visible = session
        await refresh(id: id, session: session)
    }
    private func refresh(id: String, session: Session) async {
        guard let api else { return }
        session.loadGeneration += 1; let token = session.loadGeneration
        session.loading = true
        defer { if token == session.loadGeneration { session.loading = false } }
        do {
            var loaded = try await api.conversation(id)
            guard token == session.loadGeneration, !Task.isCancelled else { return }
            for index in loaded.runs.indices {
                if let newer = session.detail?.runs.first(where: { $0.id == loaded.runs[index].id }), newer.lastSeq > loaded.runs[index].lastSeq {
                    loaded.runs[index] = newer
                }
            }
            for run in session.detail?.runs ?? [] where !loaded.runs.contains(where: { $0.id == run.id }) {
                loaded.runs.append(run)
            }
            session.detail = loaded; session.error = ""
            if session.model == nil && session.settings == nil {
                if let last = loaded.runs.last {
                    session.model = models.first(where: { $0.id == last.modelId }); session.settings = last.settings
                    if session.model == nil { session.error = "この会話のモデルが一覧にありません。モデルを選び直してください。" }
                } else { configureNew(session) }
            }
            if let run = loaded.runs.last { await loadTrace(run.id, session: session) }
            if let active = session.activeRun { observe(active.id, session: session) }
        } catch { if token == session.loadGeneration && !Task.isCancelled { session.error = error.localizedDescription } }
    }
    func restoreAfterForeground() async {
        await loadList()
        let targets = sessions.filter { $0.value.activeRun != nil || $0.value === visible }
        for (id, session) in targets { await refresh(id: id, session: session) }
    }

    func send(conversationId: String?) async -> String? {
        guard let api, canSend else { return nil }
        let session = visible
        if session.pending == nil {
            guard let selectedModel, let settings else { return nil }
            let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = conversationId ?? UUID().uuidString.lowercased()
            session.pending = Pending(conversationId: id, title: String(text.prefix(80)), isNew: conversationId == nil,
                submission: AIAPIClient.Submission(id: UUID().uuidString.lowercased(), modelId: selectedModel.id, inputText: text, settings: settings))
            sessions[id] = session
            if session === newSession { newSession = Session(); configureNew(newSession) }
        }
        guard let pending = session.pending else { return nil }
        session.sending = true; session.error = ""
        defer { session.sending = false }
        do {
            if pending.isNew {
                let created = try await api.create(id: pending.conversationId, title: pending.title)
                listGeneration += 1; listLoading = false
                if !conversations.contains(where: { $0.id == created.id }) { conversations.insert(created, at: 0) }
            }
            let run = try await api.send(conversation: pending.conversationId, submission: pending.submission)
            session.pending = nil; session.draft = ""
            if session.detail == nil {
                session.detail = AIConversationDetail(id: pending.conversationId, title: pending.title,
                    createdAt: run.createdAt, updatedAt: run.updatedAt, runs: [run])
            } else if !session.detail!.runs.contains(where: { $0.id == run.id }) { session.detail!.runs.append(run) }
            observe(run.id, session: session)
            return visible === session ? pending.conversationId : nil
        } catch let error as AIAPIClient.APIError {
            if case .response(let status, _) = error, (400..<500).contains(status) { session.pending = nil }
            session.error = error.localizedDescription
        } catch { session.error = "送信結果を確認できません。同じ実行IDで再送できます。\n" + error.localizedDescription }
        return nil
    }
    func cancel() async {
        let session = visible
        guard let api, let run = session.activeRun else { return }
        do { replaceRun(try await api.cancel(run.id), session: session) }
        catch { session.error = error.localizedDescription }
    }
    func activity(_ id: String) -> String {
        guard let session = sessions[id] else { return "" }
        if session.sending { return "送信中" }
        if session.pending != nil { return "再送を確認" }
        guard let run = session.activeRun else { return "" }
        return run.status == "queued" ? "待機中" : "実行中"
    }
    func canDelete(_ id: String) -> Bool {
        guard let session = sessions[id] else { return true }
        return !session.sending && session.pending == nil && session.activeRun == nil
    }
    func delete(_ id: String) async -> Bool {
        guard let api, canDelete(id) else { return false }
        do {
            try await api.delete(id)
            if let session = sessions.removeValue(forKey: id) {
                for run in session.detail?.runs ?? [] { streams.removeValue(forKey: run.id)?.cancel(); eventsByRun.removeValue(forKey: run.id) }
                if visible === session { newChat() }
            }
            conversations.removeAll { $0.id == id }
            listGeneration += 1; listLoading = false
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func rename(_ title: String) async {
        let session = visible
        guard let api, let detail = session.detail else { return }
        do {
            let renamed = try await api.rename(detail.id, title: title)
            session.detail?.title = renamed.title
            if let index = conversations.firstIndex(where: { $0.id == detail.id }) { conversations[index].title = renamed.title }
        } catch { session.error = error.localizedDescription }
    }
    func trace(_ runId: String) -> AITrace { AITrace(events: eventsByRun[runId] ?? []) }
    func loadTrace(_ runId: String) async { await loadTrace(runId, session: visible) }
    private func loadTrace(_ runId: String, session: Session) async {
        guard let api else { return }
        do {
            var cursor = eventsByRun[runId]?.last?.seq ?? 0
            while !Task.isCancelled {
                let page = try await api.events(runId, after: cursor)
                replaceRun(page.run, session: session)
                for event in page.events { appendTrace(runId, event) }
                guard let last = page.events.last else { break }
                cursor = last.seq
                if cursor >= page.run.lastSeq { break }
            }
        } catch { if !Task.isCancelled { session.error = error.localizedDescription } }
    }
    private func replaceRun(_ run: AIRun, session: Session) {
        guard let index = session.detail?.runs.firstIndex(where: { $0.id == run.id }) else { return }
        if let current = session.detail?.runs[index], current.lastSeq > run.lastSeq { return }
        session.detail?.runs[index] = run
    }
    private func appendTrace(_ runId: String, _ event: AIEvent) {
        if let last = eventsByRun[runId]?.last, last.seq >= event.seq { return }
        eventsByRun[runId, default: []].append(event)
    }
    private func observe(_ runId: String, session: Session) {
        guard let api, streams[runId] == nil else { return }
        streams[runId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.streams.removeValue(forKey: runId) }
            while !Task.isCancelled {
                do {
                    let cursor = self.eventsByRun[runId]?.last?.seq ?? 0
                    for try await event in api.stream(runId, after: cursor) {
                        try Task.checkCancellation()
                        session.connection = ""
                        if let index = session.detail?.runs.firstIndex(where: { $0.id == runId }) { try session.detail?.runs[index].apply(event) }
                        self.appendTrace(runId, event)
                    }
                    let run = try await api.run(runId)
                    self.replaceRun(run, session: session)
                    if !run.isActive {
                        await self.loadTrace(runId, session: session)
                        session.connection = ""
                        return
                    }
                } catch {
                    if Task.isCancelled { return }
                    session.connection = "接続を再確立中（PCでの実行は継続）"
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
