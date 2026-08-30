import Foundation

// Compile the production AIChatState and AIModels with a controlled transport.
// No authentication, network, GPU or user's preferences are used by this test.
@MainActor final class CognitoAuthSession {
    let isSignedIn = true
    func signIn() async throws {}
}
@MainActor final class AIAPIClient {
    enum APIError: Error { case response(Int, String) }
    struct Submission { let id: String; let modelId: String; let inputText: String; let settings: AISettings }
    let model = AIModel(id: "regression-model", hostId: "host", hostName: "host", model: "test", name: "test", online: true,
        contextLengths: [65536], maxOutputTokens: 32768, reasoningEfforts: ["low"], reasoningBudgets: ["low": 512],
        initialSettings: AISettings(contextLength: 65536, maxOutputTokens: 1024, reasoningEffort: "low"))
    var details: [String: AIConversationDetail] = [:]
    var history: [String: [AIEvent]] = [:]
    var listeners: [String: AsyncThrowingStream<AIEvent, Error>.Continuation] = [:]
    var pausedLoads: Set<String> = []
    var loadWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    var pauseSend = false
    var sendWaiter: CheckedContinuation<Void, Never>?
    var cancelled: [String] = []
    func models() async throws -> [AIModel] { [model] }
    func conversations() async throws -> [AIConversation] {
        details.values.map { AIConversation(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
    }
    func create(id: String, title: String) async throws -> AIConversation {
        details[id] = AIConversationDetail(id: id, title: title, createdAt: "test", updatedAt: "test", runs: [])
        return AIConversation(id: id, title: title, createdAt: "test", updatedAt: "test")
    }
    func conversation(_ id: String) async throws -> AIConversationDetail {
        let snapshot = details[id]!
        if pausedLoads.contains(id) { await withCheckedContinuation { loadWaiters[id] = $0 } }
        return snapshot
    }
    func send(conversation: String, submission: Submission) async throws -> AIRun {
        if pauseSend { await withCheckedContinuation { sendWaiter = $0 } }
        let run = AIRun(id: submission.id, conversationId: conversation, hostId: "host", modelId: model.id, model: model.model,
            settings: submission.settings, inputText: submission.inputText, outputText: "", status: "queued", cancelRequested: false,
            lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "test", updatedAt: "test")
        details[conversation]!.runs.append(run)
        return run
    }
    func run(_ id: String) async throws -> AIRun { details.values.flatMap(\.runs).first { $0.id == id }! }
    func events(_ id: String, after: Int) async throws -> AIEventPage {
        AIEventPage(run: try await run(id), events: (history[id] ?? []).filter { $0.seq > after })
    }
    func stream(_ id: String, after: Int) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            listeners[id] = continuation
            for event in history[id] ?? [] where event.seq > after { continuation.yield(event) }
        }
    }
    func cancel(_ id: String) async throws -> AIRun { cancelled.append(id); return try await run(id) }
    func delete(_ id: String) async throws { details.removeValue(forKey: id) }
    func rename(_ id: String, title: String) async throws -> AIConversationDetail { details[id]!.title = title; return details[id]! }
    func emit(_ id: String, type: String, data: [String: AIJSON]) throws {
        let event = AIEvent(seq: (history[id]?.count ?? 0) + 1, type: type, data: data, createdAt: "test")
        history[id, default: []].append(event)
        for key in details.keys {
            if let index = details[key]!.runs.firstIndex(where: { $0.id == id }) { try details[key]!.runs[index].apply(event) }
        }
        listeners[id]?.yield(event)
    }
}

@main struct SessionRegression {
    @MainActor static func main() async throws {
        let api = AIAPIClient()
        let state = AIChatState(apiClient: api, authSession: CognitoAuthSession(), configurationErrorMessage: nil)
        await state.loadList(); state.choose(api.model)
        _ = try await api.create(id: "a", title: "A")
        _ = try await api.create(id: "b", title: "B")
        state.composerText = "new draft"
        await state.openConversation(id: "a"); state.composerText = "draft A"
        await state.openConversation(id: "b"); state.composerText = "draft B"
        await state.openConversation(id: "a")
        precondition(state.composerText == "draft A", "A's draft must survive switching")
        state.newChat(); precondition(state.composerText == "new draft")

        // A's older GET returns after B is open: neither title nor input changes.
        api.pausedLoads.insert("a")
        let delayedOpen = Task { await state.openConversation(id: "a") }
        while api.loadWaiters["a"] == nil { await Task.yield() }
        await state.openConversation(id: "b")
        api.loadWaiters.removeValue(forKey: "a")!.resume(); api.pausedLoads.remove("a")
        await delayedOpen.value
        precondition(state.detail?.id == "b" && state.composerText == "draft B")

        // The HTTP submission for A is still pending when B is opened.
        await state.openConversation(id: "a"); api.pauseSend = true
        let delayedSend = Task { await state.send(conversationId: "a") }
        while api.sendWaiter == nil { await Task.yield() }
        api.pausedLoads.insert("a")
        let staleRefresh = Task { await state.openConversation(id: "a") }
        while api.loadWaiters["a"] == nil { await Task.yield() }
        await state.openConversation(id: "b")
        precondition(!state.isSending && state.canSend, "A's submission must not lock B")
        api.sendWaiter!.resume(); api.sendWaiter = nil; api.pauseSend = false
        let navigation = await delayedSend.value
        precondition(navigation == nil && state.detail?.id == "b", "A must not steal focus")
        api.loadWaiters.removeValue(forKey: "a")!.resume(); api.pausedLoads.remove("a")
        await staleRefresh.value
        precondition(state.activity("a") == "待機中", "An old empty snapshot must not erase A's accepted run")
        let runA = api.details["a"]!.runs.last!.id
        let b = await state.send(conversationId: "b")
        precondition(b == "b")
        let runB = api.details["b"]!.runs.last!.id
        while api.listeners[runA] == nil || api.listeners[runB] == nil { await Task.yield() }
        precondition(state.activity("a") == "待機中" && state.activity("b") == "待機中")
        try api.emit(runA, type: "run.started", data: [:])
        try api.emit(runA, type: "text.delta", data: ["text": .string("only A")])
        try api.emit(runB, type: "run.started", data: [:])
        try api.emit(runB, type: "text.delta", data: ["text": .string("only B")])
        while state.detail?.runs.last?.outputText != "only B" { await Task.yield() }
        precondition(state.detail?.id == "b")
        await state.openConversation(id: "a")
        precondition(state.detail?.runs.last?.outputText == "only A")
        await state.cancel(); precondition(api.cancelled == [runA], "Stop targets the visible run only")
        try api.emit(runA, type: "run.completed", data: ["responseId": .string("response-a")])
        try api.emit(runB, type: "run.completed", data: ["responseId": .string("response-b")])
        while !state.canDelete("a") || !state.canDelete("b") { await Task.yield() }
        await state.openConversation(id: "b"); state.composerText = "B remains"
        let deleted = await state.delete("a")
        precondition(deleted && state.detail?.id == "b" && state.composerText == "B remains")
        for listener in api.listeners.values { listener.finish() }
        print("PASS: draft isolation, delayed navigation, concurrent streams, queue status, targeted stop and deletion")
    }
}
