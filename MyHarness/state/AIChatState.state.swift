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
        var attachments: [AIComposerAttachment] = []
        var error = ""
        var connection = ""
        var sending = false
        var loading = false
        var loadGeneration = 0
        var pending: Pending?
        var harness: AIHarness = .hermes
        var repository: AIRepositorySelection = .unselected
        var delivery: AIDelivery = .changes
        var activeRun: AIRun? { detail?.runs.last(where: { $0.isActive }) }
    }
    fileprivate struct Pending {
        let conversationId: String
        let title: String
        let isNew: Bool
        let context: AIContextInput
        let submission: AIAPIClient.Submission
        let uploads: [AIComposerAttachment]
    }
    var inferenceHosts: [AIInferenceHost] = []
    var inferenceError = ""
    private var inferenceLoading = false
    func refreshInference() async {
        guard !inferenceLoading else { return }
        guard let api, isSignedIn else { inferenceError = "推論管理にはログインとサーバー設定が必要です。"; return }
        inferenceLoading = true
        defer { inferenceLoading = false }
        do { inferenceHosts = try await api.inferenceHosts(); inferenceError = "" }
        catch { inferenceError = error.localizedDescription }
    }
    func saveInference(hostId: String, policy: AIInferencePolicy) async -> Bool {
        guard let api else { inferenceError = "サーバーが設定されていません。"; return false }
        do {
            let saved = try await api.saveInferencePolicy(hostId: hostId, policy: policy)
            if let index = inferenceHosts.firstIndex(where: { $0.hostId == hostId }) { inferenceHosts[index].desiredPolicy = saved }
            inferenceError = ""
            await loadList()
            return true
        } catch { inferenceError = error.localizedDescription; return false }
    }
    var conversations: [AIConversation] = []
    var models: [AIModel] = []
    var repositories: [AIRepository] = []
    var requestsByRun: [String: [AIRequest]] = [:]
    var replying: Set<String> = []
    private(set) var sharing: AISharing?
    private(set) var savingSharing = false
    var sharedMode: Bool { sharing?.enabled == true }
    var eventsByRun: [String: [AIEvent]] = [:]
    var searchText = ""
    private var sessions: [String: Session] = [:]
    private var newSession: Session
    private var visible: Session
    private var listLoading = false
    private var listGeneration = 0
    private var streams: [String: Task<Void, Never>] = [:]
    private var reconciliations: [String: Task<Void, Never>] = [:]
    private var presentations: [String: AIStreamingPresentation] = [:]
    private var presentationTasks: [String: Task<Void, Never>] = [:]
    private var attachmentDataById: [String: Data] = [:]
    private let api: AIAPIClient?
    private let authSession: CognitoAuthSession?
    private let configurationErrorMessage: String?
    private let reconciliationInterval: Duration
    private(set) var isSignedIn: Bool

    var detail: AIConversationDetail? { visible.detail }
    var harness: AIHarness { visible.detail?.context.harness ?? visible.harness }
    var repositorySelection: AIRepositorySelection { visible.repository }
    var delivery: AIDelivery {
        get { visible.delivery }
        set { if activeRun == nil && !isSending && !hasPendingSubmission { visible.delivery = newValue } }
    }
    var selectedModel: AIModel? { visible.model }
    var settings: AISettings? { visible.settings }
    var composerText: String { get { visible.draft } set { visible.draft = newValue } }
    var composerAttachments: [AIComposerAttachment] { visible.attachments }
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
        guard sharing != nil, !savingSharing, let model = selectedModel, let settings else { return false }
        if harness == .opencode {
            if case .opencode(let context) = visible.detail?.context {
                guard context.hostId == model.hostId else { return false }
            } else {
                guard case .selected(let repo, let branch) = visible.repository,
                      repo.online, repo.hostId == model.hostId, repo.branches.contains(branch) else { return false }
            }
        }
        let modalitiesAccepted = visible.attachments.allSatisfy { model.accepts($0.modality) }
        let hasInput = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !visible.attachments.isEmpty
        return model.online && model.accepts(settings) && modalitiesAccepted && (visible.attachments.isEmpty || harness == .hermes)
            && hasInput && !isSending && !visible.loading && activeRun == nil
    }

    init(apiClient: AIAPIClient?, authSession: CognitoAuthSession?, configurationErrorMessage: String?, reconciliationInterval: Duration) {
        api = apiClient; self.authSession = authSession; self.configurationErrorMessage = configurationErrorMessage
        self.reconciliationInterval = reconciliationInterval
        isSignedIn = authSession?.isSignedIn == true
        let initial = Session(); newSession = initial; visible = initial
    }
    func signIn() async {
        do { try await authSession?.signIn(); await loadList() }
        catch { errorMessage = error.localizedDescription }
    }
    func choose(_ model: AIModel) {
        guard !sharedMode, !visible.sending, visible.activeRun == nil, visible.pending == nil else { return }
        guard visible.attachments.allSatisfy({ model.accepts($0.modality) }) else {
            errorMessage = "添付中の画像・動画に対応するモデルを選んでください。"
            return
        }
        configure(visible, model: model)
        UserDefaults.standard.set(model.id, forKey: "agent-chat-selected-model")
    }
    func addComposerAttachments(_ attachments: [AIComposerAttachment]) {
        guard visible.pending == nil, visible.activeRun == nil, !visible.sending, harness == .hermes, let model = selectedModel else { return }
        guard attachments.allSatisfy({ model.accepts($0.modality) }) else {
            errorMessage = "選択中のモデルはこの画像・動画入力に対応していません。"; return
        }
        let combined = visible.attachments + attachments
        let images = combined.filter { $0.kind == .image }
        let videoGroups = Set(combined.filter { $0.kind == .videoFrame }.map(\.groupId))
        guard images.count <= 4, videoGroups.count <= 1, combined.count <= 12 else {
            errorMessage = "画像は4枚、動画は1本（最大8フレーム）まで追加できます。"; return
        }
        visible.attachments = combined
        errorMessage = ""
    }
    func removeComposerAttachment(groupId: String) {
        guard visible.pending == nil, !visible.sending else { return }
        visible.attachments.removeAll { $0.groupId == groupId }
    }
    func cachedAttachmentData(_ id: String) -> Data? { attachmentDataById[id] }
    func loadAttachmentData(_ id: String) async {
        guard attachmentDataById[id] == nil, let api else { return }
        do { attachmentDataById[id] = try await api.attachment(id) }
        catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func chooseHarness(_ value: AIHarness) {
        guard visible.detail == nil, !isSending, !hasPendingSubmission else { return }
        guard visible.attachments.isEmpty || value == .hermes else {
            errorMessage = "画像・動画を削除してからOpenCodeへ切り替えてください。"
            return
        }
        visible.harness = value
        if value == .hermes { visible.delivery = .changes }
    }
    func chooseRepository(_ repository: AIRepository, branch: String) {
        guard visible.detail == nil, !isSending, !hasPendingSubmission, repository.branches.contains(branch) else { return }
        visible.repository = .selected(repository, branch: branch)
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
        if sharedMode { applySharing(to: session); return }
        if let id = UserDefaults.standard.string(forKey: "agent-chat-selected-model"), let model = models.first(where: { $0.id == id }) {
            configure(session, model: model)
        }
    }
    func saveSettings(_ value: AISettings) {
        guard !visible.sending, visible.activeRun == nil, visible.pending == nil else { return }
        if let sharing, sharing.enabled, value.contextLength != sharing.contextLength {
            errorMessage = "共有モードのコンテキスト長はトップ画面で変更してください。"; return
        }
        guard let model = selectedModel, model.accepts(value) else { errorMessage = "このモデルでは指定した設定を使用できません。"; return }
        visible.settings = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "agent-chat-settings-" + model.id) }
    }
    private func applySharing(to session: Session) {
        guard let sharing, sharing.enabled, session.activeRun == nil, session.pending == nil else { return }
        guard let model = models.first(where: { $0.id == sharing.modelId }) else {
            session.model = nil; session.error = "共有モデルを利用できません。トップ画面で共有設定を確認してください。"; return
        }
        if session.settings == nil { configure(session, model: model) }
        session.model = model
        session.settings?.contextLength = sharing.contextLength
        if let settings = session.settings, !model.accepts(settings) {
            session.error = "共有モデルに推論設定が対応していません。推論量・出力上限を確認してください。"
        }
    }
    func saveSharing(_ value: AISharing) async -> Bool {
        guard let api, !savingSharing else { return false }
        savingSharing = true
        defer { savingSharing = false }
        do {
            sharing = try await api.saveSharing(value)
            listGeneration += 1; listLoading = false
            for session in Array(sessions.values) + [newSession] { applySharing(to: session) }
            errorMessage = ""
            return true
        } catch { errorMessage = error.localizedDescription; return false }
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
            async let mode = api.sharing()
            async let repos = api.repositories()
            let loaded = try await (list, catalog, mode, repos)
            guard token == listGeneration else { return }
            conversations = loaded.0; models = loaded.1; sharing = loaded.2
            repositories = loaded.3
            for session in Array(sessions.values) + [newSession] {
                if let model = session.model {
                    session.model = models.first(where: { $0.id == model.id })
                    if session.model == nil { session.error = "選択中のモデルが一覧にありません。モデルを選び直してください。" }
                }
                applySharing(to: session)
            }
            if visible.model == nil && visible.settings == nil { configureNew(visible) }
        } catch { if token == listGeneration && !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func newChat() {
        if visible !== newSession {
            flushPresentations(in: visible)
            visible = newSession
        }
        if visible.model == nil && visible.settings == nil { configureNew(visible) }
    }
    func openConversation(id: String) async {
        let session: Session
        if let existing = sessions[id] { session = existing }
        else { session = Session(); sessions[id] = session }
        if visible !== session { flushPresentations(in: visible) }
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
            for run in loaded.runs { synchronizePresentation(run, session: session) }
            if let last = loaded.runs.last { session.delivery = last.delivery }
            if session.model == nil && session.settings == nil {
                if let last = loaded.runs.last {
                    session.model = models.first(where: { $0.id == last.modelId }); session.settings = last.settings
                    if session.model == nil { session.error = "この会話のモデルが一覧にありません。モデルを選び直してください。" }
                } else { configureNew(session) }
            }
            applySharing(to: session)
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
            // Refresh global policy before creating a run. A remote change must
            // be shown to the user, never silently change the submitted model.
            session.sending = true
            do {
                let current = try await api.sharing()
                guard current == sharing else {
                    sharing = current
                    for target in Array(sessions.values) + [newSession] { applySharing(to: target) }
                    session.error = "共有設定が変更されました。モデル・設定を確認してから送信してください。"
                    session.sending = false; return nil
                }
            } catch { session.error = error.localizedDescription; session.sending = false; return nil }
            session.sending = false
            guard let selectedModel = session.model, let settings = session.settings else { return nil }
            let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = conversationId ?? UUID().uuidString.lowercased()
            let context: AIContextInput
            if let detail = session.detail, case .opencode(let value) = detail.context {
                context = .opencode(repositoryId: value.repositoryId, baseBranch: value.baseBranch)
            } else if session.harness == .opencode {
                guard case .selected(let repo, let branch) = session.repository else {
                    session.error = "作業repoとブランチを選んでください。"; return nil
                }
                context = .opencode(repositoryId: repo.id, baseBranch: branch)
            } else { context = .hermes }
            let title = text.isEmpty ? (session.attachments.contains(where: { $0.kind == .videoFrame }) ? "動画について" : "画像について") : String(text.prefix(80))
            session.pending = Pending(conversationId: id, title: title, isNew: conversationId == nil,
                context: context, submission: AIAPIClient.Submission(id: UUID().uuidString.lowercased(), modelId: selectedModel.id, inputText: text,
                    settings: settings, delivery: session.delivery, attachmentIds: session.attachments.map(\.id)), uploads: session.attachments)
            sessions[id] = session
            if session === newSession { newSession = Session(); configureNew(newSession) }
        }
        guard let pending = session.pending else { return nil }
        session.sending = true; session.error = ""
        defer { session.sending = false }
        do {
            if pending.isNew {
                let created = try await api.create(id: pending.conversationId, title: pending.title, context: pending.context)
                if session.detail == nil {
                    session.detail = AIConversationDetail(id: created.id, title: created.title, context: created.context, createdAt: created.createdAt, updatedAt: created.updatedAt, runs: [])
                }
                listGeneration += 1; listLoading = false
                if !conversations.contains(where: { $0.id == created.id }) { conversations.insert(created, at: 0) }
            }
            for attachment in pending.uploads {
                _ = try await api.upload(conversation: pending.conversationId, attachment: attachment)
            }
            let run = try await api.send(conversation: pending.conversationId, submission: pending.submission)
            for attachment in pending.uploads { attachmentDataById[attachment.id] = attachment.data }
            session.pending = nil; session.draft = ""; session.attachments = []
            guard session.detail != nil else { throw AIContractError.malformedEvent }
            if !session.detail!.runs.contains(where: { $0.id == run.id }) {
                session.detail!.runs.append(run)
                synchronizePresentation(run, session: session)
            }
            observe(run.id, session: session)
            return visible === session ? pending.conversationId : nil
        } catch let error as AIAPIClient.APIError {
            if case .response(let status, _) = error, (400..<500).contains(status) {
                session.pending = nil
                for attachment in pending.uploads { try? await api.deleteAttachment(attachment.id) }
            }
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
                for run in session.detail?.runs ?? [] {
                    streams.removeValue(forKey: run.id)?.cancel()
                    reconciliations.removeValue(forKey: run.id)?.cancel()
                    presentationTasks.removeValue(forKey: run.id)?.cancel()
                    presentations.removeValue(forKey: run.id)
                    eventsByRun.removeValue(forKey: run.id)
                }
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
    func displayedOutput(for run: AIRun) -> String {
        run.isActive ? presentations[run.id]?.displayed ?? run.outputText : run.outputText
    }
    func answer(_ request: AIRequest, reply: AIReply) async {
        guard let api, !replying.contains(request.id) else { return }
        let session = visible
        replying.insert(request.id)
        defer { replying.remove(request.id) }
        do { try await api.reply(request.id, value: reply); requestsByRun[request.runId] = try await api.requests(request.runId) }
        catch { session.error = error.localizedDescription }
    }
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
            requestsByRun[runId] = try await api.requests(runId)
        } catch { if !Task.isCancelled { session.error = error.localizedDescription } }
    }
    private func replaceRun(_ run: AIRun, session: Session) {
        guard let index = session.detail?.runs.firstIndex(where: { $0.id == run.id }) else { return }
        if let current = session.detail?.runs[index], current.lastSeq > run.lastSeq { return }
        session.detail?.runs[index] = run
        synchronizePresentation(run, session: session)
    }
    private func appendTrace(_ runId: String, _ event: AIEvent) {
        if let last = eventsByRun[runId]?.last, last.seq >= event.seq { return }
        eventsByRun[runId, default: []].append(event)
    }
    private func observe(_ runId: String, session: Session) {
        guard let api else { return }
        if reconciliations[runId] == nil {
            reconciliations[runId] = Task { @MainActor [weak self] in
                defer { self?.reconciliations.removeValue(forKey: runId) }
                while !Task.isCancelled {
                    guard let self else { return }
                    do { try await Task.sleep(for: self.reconciliationInterval) }
                    catch { return }
                    guard session.detail?.runs.first(where: { $0.id == runId })?.isActive == true else {
                        self.streams.removeValue(forKey: runId)?.cancel()
                        return
                    }
                    do {
                        let run = try await api.run(runId)
                        try Task.checkCancellation()
                        self.replaceRun(run, session: session)
                        session.connection = ""
                        if !run.isActive {
                            await self.loadTrace(runId, session: session)
                            self.streams.removeValue(forKey: runId)?.cancel()
                            return
                        }
                    } catch {
                        if Task.isCancelled { return }
                        session.connection = "接続を再確立中（PCでの実行は継続）"
                    }
                }
            }
        }
        guard streams[runId] == nil else { return }
        streams[runId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.streams.removeValue(forKey: runId) }
            while !Task.isCancelled {
                do {
                    let cursor = self.eventsByRun[runId]?.last?.seq ?? 0
                    for try await event in api.stream(runId, after: cursor) {
                        try Task.checkCancellation()
                        session.connection = ""
                        if let index = session.detail?.runs.firstIndex(where: { $0.id == runId }) {
                            try session.detail?.runs[index].apply(event)
                            if let run = session.detail?.runs[index] { self.synchronizePresentation(run, session: session) }
                        }
                        self.appendTrace(runId, event)
                        if event.type == "request.created" || event.type == "request.resolved" {
                            self.requestsByRun[runId] = try await api.requests(runId)
                        }
                        if session.detail?.runs.first(where: { $0.id == runId })?.isActive == false {
                            await self.loadTrace(runId, session: session)
                            session.connection = ""
                            return
                        }
                    }
                    try Task.checkCancellation()
                    let run = try await api.run(runId)
                    try Task.checkCancellation()
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

    private func synchronizePresentation(_ run: AIRun, session: Session) {
        if !run.isActive || session !== visible {
            presentationTasks.removeValue(forKey: run.id)?.cancel()
            var presentation = presentations[run.id] ?? AIStreamingPresentation(text: run.outputText)
            presentation.receive(run.outputText)
            presentation.flush()
            presentations[run.id] = presentation
            return
        }
        guard var presentation = presentations[run.id] else {
            // History and a reopened conversation appear immediately. Only
            // deltas received after this point are visually paced.
            presentations[run.id] = AIStreamingPresentation(text: run.outputText)
            return
        }
        presentation.receive(run.outputText)
        presentations[run.id] = presentation
        guard presentation.needsAdvance, presentationTasks[run.id] == nil else { return }
        presentationTasks[run.id] = Task { @MainActor [weak self] in
            defer { self?.presentationTasks.removeValue(forKey: run.id) }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                guard let self, var current = self.presentations[run.id] else { return }
                let needsMore = current.advance()
                self.presentations[run.id] = current
                if !needsMore { return }
            }
        }
    }

    private func flushPresentations(in session: Session) {
        for run in session.detail?.runs ?? [] {
            presentationTasks.removeValue(forKey: run.id)?.cancel()
            presentations[run.id] = AIStreamingPresentation(text: run.outputText)
        }
    }
}
