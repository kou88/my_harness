import Foundation

// Compile the production AIChatState and AIModels with a controlled transport.
// No authentication, network, GPU or user's preferences are used by this test.
@MainActor final class CognitoAuthSession {
    let isSignedIn = true
    func signIn() async throws {}
}
@MainActor final class AIAPIClient {
    enum APIError: Error { case response(Int, String) }
    struct Submission { let id: String; let modelId: String; let inputText: String; let settings: AISettings; let delivery: AIDelivery; let attachmentIds: [String] }
    let model = AIModel(id: "regression-model", hostId: "host", hostName: "host", model: "test", name: "test", online: true,
        contextLengths: [65536], maxOutputTokens: 32768, reasoningEfforts: ["low"], reasoningBudgets: ["low": 512],
        initialSettings: AISettings(contextLength: 65536, maxOutputTokens: 1024, reasoningEffort: "low"), inputModalities: [.text, .image, .video])
    var sharingValue = AISharing(enabled: false, modelId: "", contextLength: 65536, maxConcurrentRuns: 2, revision: 1)
    func sharing() async throws -> AISharing { sharingValue }
    func saveSharing(_ value: AISharing) async throws -> AISharing { sharingValue = value; sharingValue.revision += 1; return sharingValue }
    var details: [String: AIConversationDetail] = [:]
    var history: [String: [AIEvent]] = [:]
    var listeners: [String: AsyncThrowingStream<AIEvent, Error>.Continuation] = [:]
    var pausedLoads: Set<String> = []
    var loadWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    var pauseSend = false
    var hideModel = false
    var sendWaiter: CheckedContinuation<Void, Never>?
    var cancelled: [String] = []
    var repositoryValues: [AIRepository] = []
    var requestValues: [String: [AIRequest]] = [:]
    var replies: [String] = []
    var runRequestCount = 0
    var uploaded: [String: AIAttachment] = [:]
    var attachmentValues: [String: Data] = [:]
    func repositories() async throws -> [AIRepository] { repositoryValues }
    func requests(_ runId: String) async throws -> [AIRequest] { requestValues[runId] ?? [] }
    func reply(_ id: String, value: AIReply) async throws {
        replies.append(id)
        for run in requestValues.keys {
            requestValues[run] = requestValues[run]!.map { request in
                request.id == id ? AIRequest(id: id, runId: run, kind: request.kind, payload: request.payload, status: "applied", createdAt: "test", updatedAt: "test") : request
            }
        }
    }
    func models() async throws -> [AIModel] { hideModel ? [] : [model] }
    func conversations() async throws -> [AIConversation] {
        details.values.map { AIConversation(id: $0.id, title: $0.title, context: $0.context, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
    }
    func create(id: String, title: String, context: AIContextInput) async throws -> AIConversation {
        let value: AIContext
        switch context {
        case .hermes: value = .hermes
        case .opencode(let repo, let branch): value = .opencode(AICodingContext(repositoryId: repo, repository: "test/repo", hostId: "host", baseBranch: branch, workBranch: "agent/" + id))
        }
        details[id] = AIConversationDetail(id: id, title: title, context: value, createdAt: "test", updatedAt: "test", runs: [])
        return AIConversation(id: id, title: title, context: value, createdAt: "test", updatedAt: "test")
    }
    func conversation(_ id: String) async throws -> AIConversationDetail {
        let snapshot = details[id]!
        if pausedLoads.contains(id) { await withCheckedContinuation { loadWaiters[id] = $0 } }
        return snapshot
    }
    func send(conversation: String, submission: Submission) async throws -> AIRun {
        if pauseSend { await withCheckedContinuation { sendWaiter = $0 } }
        let run = AIRun(id: submission.id, conversationId: conversation, hostId: "host", modelId: model.id, model: model.model,
            settings: submission.settings, delivery: submission.delivery, inputText: submission.inputText,
            attachments: submission.attachmentIds.compactMap { uploaded[$0] }, outputText: "", status: "queued", cancelRequested: false,
            lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "test", updatedAt: "test")
        details[conversation]!.runs.append(run)
        return run
    }
    func upload(conversation: String, attachment: AIComposerAttachment) async throws -> AIAttachment {
        let value = AIAttachment(id: attachment.id, conversationId: conversation, kind: attachment.kind, groupId: attachment.groupId,
            fileName: attachment.fileName, contentType: attachment.contentType, byteSize: attachment.data.count,
            frameIndex: attachment.frameIndex, frameCount: attachment.frameCount, createdAt: "test")
        uploaded[attachment.id] = value
        attachmentValues[attachment.id] = attachment.data
        return value
    }
    func attachment(_ id: String) async throws -> Data { attachmentValues[id] ?? Data() }
    func deleteAttachment(_ id: String) async throws {}
    func run(_ id: String) async throws -> AIRun {
        runRequestCount += 1
        guard let run = details.values.flatMap(\.runs).first(where: { $0.id == id }) else { throw APIError.response(404, "Deleted run") }
        return run
    }
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
