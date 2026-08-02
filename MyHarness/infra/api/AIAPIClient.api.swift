import Foundation

@MainActor
final class AIAPIClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "AI APIレスポンスを解釈できません。"
            case .requestFailed(let status, let message):
                return "AI APIエラー（\(status)）: \(message)"
            }
        }
    }

    struct CreateConversationRequest: Encodable {
        let title: String
        let runtimeId: String
        let hostId: String
        let provider: AIProvider
        let model: String
        let mode: AIConversationMode
        let workspaceId: String
        let reasoningEffort: AIReasoningEffort
        let temporary: Bool
    }

    struct ConversationPatchRequest: Encodable {
        let title: String
        let runtimeId: String
        let hostId: String
        let provider: AIProvider
        let model: String
        let workspaceId: String
        let mode: AIConversationMode
        let reasoningEffort: AIReasoningEffort
    }

    struct CreateTurnRequest: Encodable {
        let input: String
        let attachmentIds: [String]
        let branchFromMessageId: String
        let regenerateMessageId: String
    }

    struct ApprovalDecisionRequest: Encodable {
        let decision: String
    }

    private struct AttachmentUploadRequest: Encodable {
        let conversationId: String
        let fileName: String
        let contentType: String
        let dataBase64: String
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String
        }

        let error: APIError
    }

    private struct EventPage: Decodable {
        let run: AIRun
        let events: [AIEvent]
        let lastSeq: Int
    }

    private struct ConversationDetailTransport: Decodable {
        let id: String
        let title: String
        let runtimeId: String
        let hostId: String
        let provider: AIProvider
        let model: String
        let workspaceId: String
        let workspacePath: String
        let mode: AIConversationMode
        let status: AIConversationLifecycleStatus
        let latestRunStatus: AIConversationStatus
        let reasoningEffort: AIReasoningEffort
        let createdAt: Date
        let updatedAt: Date
        let messages: [AIMessage]
        let approvals: [AIApproval]
        let runs: [AIRun]

        var detail: AIConversationDetail {
            let summary = AIConversationSummary(
                id: id,
                title: title,
                runtimeId: runtimeId,
                provider: provider,
                model: model,
                hostId: hostId,
                workspaceId: workspaceId,
                mode: mode,
                status: status,
                latestRunStatus: latestRunStatus,
                reasoningEffort: reasoningEffort,
                workspacePath: workspacePath,
                lastMessagePreview: messages.last?.text ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            return AIConversationDetail(
                conversation: summary,
                messages: messages,
                run: runs.sorted { $0.createdAt < $1.createdAt }.last,
                events: [],
                approvals: approvals
            )
        }
    }

    private let config: ActionInboxConfig
    private let authSession: CognitoAuthSession
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var isBootstrapped = false

    init(
        config: ActionInboxConfig,
        authSession: CognitoAuthSession,
        urlSession: URLSession = .shared
    ) {
        self.config = config
        self.authSession = authSession
        self.urlSession = urlSession
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            try AIAPIDateDecoder.decode(decoder)
        }
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
    }

    func fetchModels() async throws -> [AIModelCatalogItem] {
        try await decode([AIModelCatalogItem].self, from: request(path: "/api/v3/ai/models", method: "GET"))
    }

    func fetchHosts() async throws -> [AIHostSummary] {
        try await decode([AIHostSummary].self, from: request(path: "/api/v3/ai/hosts", method: "GET"))
    }

    func fetchWorkspaces(hostId: String) async throws -> [AIWorkspaceSummary] {
        try await decode(
            [AIWorkspaceSummary].self,
            from: request(
                path: "/api/v3/ai/workspaces",
                method: "GET",
                queryItems: [URLQueryItem(name: "hostId", value: hostId)]
            )
        )
    }

    func fetchConversations() async throws -> [AIConversationSummary] {
        try await decode(
            [AIConversationSummary].self,
            from: request(path: "/api/v3/ai/conversations", method: "GET")
        )
    }

    func createConversation(_ input: CreateConversationRequest) async throws -> AIConversationSummary {
        try await decode(
            AIConversationSummary.self,
            from: request(path: "/api/v3/ai/conversations", method: "POST", body: input)
        )
    }

    func fetchConversation(id: String) async throws -> AIConversationDetail {
        try requireUUID(id)
        return try await decode(
            ConversationDetailTransport.self,
            from: request(path: "/api/v3/ai/conversations/\(id)", method: "GET")
        ).detail
    }

    func updateConversation(
        id: String,
        input: ConversationPatchRequest
    ) async throws -> AIConversationSummary {
        try requireUUID(id)
        return try await decode(
            AIConversationSummary.self,
            from: request(path: "/api/v3/ai/conversations/\(id)", method: "PATCH", body: input)
        )
    }

    func deleteConversation(id: String) async throws {
        try requireUUID(id)
        _ = try await request(path: "/api/v3/ai/conversations/\(id)", method: "DELETE")
    }

    func createTurn(conversationId: String, input: CreateTurnRequest) async throws -> AITurnAccepted {
        try requireUUID(conversationId)
        let run = try await decode(
            AIRun.self,
            from: request(
                path: "/api/v3/ai/conversations/\(conversationId)/turns",
                method: "POST",
                body: input
            )
        )
        return AITurnAccepted(runId: run.id, conversationId: run.conversationId, status: run.status)
    }

    func fetchRun(id: String) async throws -> AIRun {
        try requireUUID(id)
        return try await decode(AIRun.self, from: request(path: "/api/v3/ai/runs/\(id)", method: "GET"))
    }

    func fetchEvents(runId: String, afterSeq: Int) async throws -> [AIEvent] {
        try requireUUID(runId)
        return try await decode(
            EventPage.self,
            from: request(
                path: "/api/v3/ai/runs/\(runId)/events",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "afterSeq", value: String(afterSeq)),
                    URLQueryItem(name: "stream", value: "false")
                ]
            )
        ).events
    }

    func streamEvents(runId: String, afterSeq: Int) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    try requireUUID(runId)
                    try await bootstrapCurrentUser()
                    var request = try await authenticatedRequest(
                        path: "/api/v3/ai/runs/\(runId)/events",
                        method: "GET",
                        queryItems: [URLQueryItem(name: "afterSeq", value: String(afterSeq))],
                        bodyData: nil,
                        accept: "text/event-stream"
                    )
                    request.setValue(String(afterSeq), forHTTPHeaderField: "Last-Event-ID")
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ClientError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw ClientError.requestFailed(httpResponse.statusCode, "イベント接続に失敗しました。")
                    }

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let data = Data(dataLines.joined(separator: "\n").utf8)
                                continuation.yield(try decoder.decode(AIEvent.self, from: data))
                                dataLines.removeAll(keepingCapacity: true)
                            }
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancelRun(id: String) async throws -> AIRun {
        try requireUUID(id)
        return try await decode(
            AIRun.self,
            from: request(path: "/api/v3/ai/runs/\(id)/cancel", method: "POST", bodyData: Data("{}".utf8))
        )
    }

    func decideApproval(id: String, decision: String) async throws -> AIApproval {
        try requireUUID(id)
        return try await decode(
            AIApproval.self,
            from: request(
                path: "/api/v3/ai/approvals/\(id)/decision",
                method: "POST",
                body: ApprovalDecisionRequest(decision: decision)
            )
        )
    }

    func uploadAttachment(
        conversationId: String,
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> AIAttachment {
        try requireUUID(conversationId)
        return try await decode(
            AIAttachment.self,
            from: request(
                path: "/api/v3/ai/attachments",
                method: "POST",
                body: AttachmentUploadRequest(
                    conversationId: conversationId,
                    fileName: fileName,
                    contentType: mimeType,
                    dataBase64: data.base64EncodedString()
                )
            )
        )
    }

    func deleteAttachment(id: String) async throws {
        try requireUUID(id)
        _ = try await request(path: "/api/v3/ai/attachments/\(id)", method: "DELETE")
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder.decode(Envelope<Value>.self, from: data).data
    }

    private func requireUUID(_ value: String) throws {
        guard UUID(uuidString: value)?.uuidString.lowercased() == value else {
            throw ClientError.invalidResponse
        }
    }

    private func bootstrapCurrentUser() async throws {
        guard !isBootstrapped else { return }
        var request = URLRequest(url: endpoint(path: "/api/auth/bootstrap", queryItems: []))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await authSession.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(try await authSession.idToken(), forHTTPHeaderField: "X-ID-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw try requestError(status: httpResponse.statusCode, data: data)
        }
        isBootstrapped = true
    }

    private func request(path: String, method: String) async throws -> Data {
        try await request(path: path, method: method, queryItems: [], bodyData: nil)
    }

    private func request(path: String, method: String, queryItems: [URLQueryItem]) async throws -> Data {
        try await request(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    private func request<Value: Encodable>(path: String, method: String, body: Value) async throws -> Data {
        try await request(path: path, method: method, queryItems: [], bodyData: encoder.encode(body))
    }

    private func request(path: String, method: String, bodyData: Data) async throws -> Data {
        try await request(path: path, method: method, queryItems: [], bodyData: bodyData)
    }

    private func request(
        path: String,
        method: String,
        bodyData: Data,
        contentType: String
    ) async throws -> Data {
        try await request(
            path: path,
            method: method,
            queryItems: [],
            bodyData: bodyData,
            contentType: contentType
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        contentType: String = "application/json"
    ) async throws -> Data {
        try await bootstrapCurrentUser()
        let request = try await authenticatedRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            accept: "application/json",
            contentType: contentType
        )
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw try requestError(status: httpResponse.statusCode, data: data)
        }
        return data
    }

    private func authenticatedRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        accept: String,
        contentType: String = "application/json"
    ) async throws -> URLRequest {
        var request = URLRequest(
            url: endpoint(path: path, queryItems: queryItems),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = method
        request.setValue("Bearer \(try await authSession.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func requestError(status: Int, data: Data) throws -> ClientError {
        let body = String(data: data, encoding: .utf8) ?? ""
        let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message) ?? body
        return ClientError.requestFailed(status, message)
    }

    private func endpoint(path: String, queryItems: [URLQueryItem]) -> URL {
        let url = path.split(separator: "/").map(String.init).reduce(config.apiBaseURL) { current, component in
            current.appendingPathComponent(component)
        }
        guard !queryItems.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
    }
}

private enum AIAPIDateDecoder {
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
    }
}
