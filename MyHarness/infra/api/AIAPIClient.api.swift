import Foundation

@MainActor
final class AIAPIClient {
    enum APIError: LocalizedError {
        case response(Int, String)
        case invalidResponse
        var errorDescription: String? {
            switch self {
            case .response(let code, let message): return "\(message)（\(code)）"
            case .invalidResponse: return "AIサーバーの応答を読み取れません。"
            }
        }
    }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
    private struct Failure: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
    struct Submission: Codable {
        let id: String
        let modelId: String
        let inputText: String
        let settings: AISettings
        let delivery: AIDelivery
        let attachmentIds: [String]
    }
    private let config: ActionInboxConfig
    private let authSession: CognitoAuthSession
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: ActionInboxConfig, authSession: CognitoAuthSession) {
        self.config = config; self.authSession = authSession
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        session = URLSession(configuration: configuration)
    }

    func models() async throws -> [AIModel] { try await request("/models", method: "GET", body: nil) }
    func repositories() async throws -> [AIRepository] { try await request("/repositories", method: "GET", body: nil) }
    func requests(_ runId: String) async throws -> [AIRequest] { try await request("/runs/\(runId)/requests", method: "GET", body: nil) }
    func reply(_ id: String, value: AIReply) async throws {
        struct Accepted: Decodable { let accepted: Bool }
        let _: Accepted = try await request("/requests/\(id)/reply", method: "POST", body: encoder.encode(value))
    }
    func sharing() async throws -> AISharing { try await request("/sharing", method: "GET", body: nil) }
    func saveSharing(_ value: AISharing) async throws -> AISharing { try await request("/sharing", method: "PATCH", body: encoder.encode(value)) }
    func conversations() async throws -> [AIConversation] { try await request("/conversations", method: "GET", body: nil) }
    func conversation(_ id: String) async throws -> AIConversationDetail { try await request("/conversations/\(id)", method: "GET", body: nil) }
    func run(_ id: String) async throws -> AIRun { try await request("/runs/\(id)", method: "GET", body: nil) }
    func create(id: String, title: String, context: AIContextInput) async throws -> AIConversation {
        struct Creation: Encodable { let id: String; let title: String; let context: AIContextInput }
        return try await request("/conversations", method: "POST", body: encoder.encode(Creation(id: id, title: title, context: context)))
    }
    func send(conversation: String, submission: Submission) async throws -> AIRun {
        try await request("/conversations/\(conversation)/runs", method: "POST", body: encoder.encode(submission))
    }
    func upload(conversation: String, attachment: AIComposerAttachment) async throws -> AIAttachment {
        struct Metadata: Encodable {
            let id: String; let kind: AIAttachmentKind; let groupId: String; let fileName: String
            let contentType: String; let frameIndex: Int; let frameCount: Int
        }
        let boundary = "MyHarness-" + UUID().uuidString.lowercased()
        let metadata = try encoder.encode(Metadata(id: attachment.id, kind: attachment.kind, groupId: attachment.groupId,
            fileName: attachment.fileName, contentType: attachment.contentType, frameIndex: attachment.frameIndex, frameCount: attachment.frameCount))
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n")
        body.append(metadata); append("\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"upload.jpg\"\r\nContent-Type: \(attachment.contentType)\r\n\r\n")
        body.append(attachment.data); append("\r\n--\(boundary)--\r\n")
        var request = try await makeRequest("/conversations/\(conversation)/attachments", method: "POST", body: body)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try await response(request)
    }
    func attachment(_ id: String) async throws -> Data {
        let request = try await makeRequest("/attachments/\(id)", method: "GET", body: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw APIError.invalidResponse
        }
        return data
    }
    func deleteAttachment(_ id: String) async throws {
        struct Deleted: Decodable { let deleted: Bool }
        let _: Deleted = try await request("/attachments/\(id)", method: "DELETE", body: nil)
    }
    func cancel(_ id: String) async throws -> AIRun { try await request("/runs/\(id)/cancel", method: "POST", body: Data("{}".utf8)) }
    func delete(_ id: String) async throws {
        struct Deleted: Decodable { let deleted: Bool }
        let _: Deleted = try await request("/conversations/\(id)", method: "DELETE", body: nil)
    }
    func rename(_ id: String, title: String) async throws -> AIConversationDetail {
        try await request("/conversations/\(id)", method: "PATCH", body: encoder.encode(["title": title]))
    }
    func events(_ id: String, after: Int) async throws -> AIEventPage {
        try await request("/runs/\(id)/events?afterSeq=\(after)", method: "GET", body: nil)
    }

    func stream(_ id: String, after: Int) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    var request = try await makeRequest("/runs/\(id)/events?afterSeq=\(after)", method: "GET", body: nil)
                    guard let url = request.url,
                          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                        throw APIError.invalidResponse
                    }
                    switch components.scheme {
                    case "https": components.scheme = "wss"
                    case "http": components.scheme = "ws"
                    default: throw APIError.invalidResponse
                    }
                    guard let webSocketURL = components.url else { throw APIError.invalidResponse }
                    request.url = webSocketURL
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let socket = session.webSocketTask(with: request)
                    socket.resume()
                    let pingTask = Task { @MainActor [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(10)) }
                            catch { return }
                            guard let self else { return }
                            do { try await self.ping(socket) }
                            catch { socket.cancel(with: .abnormalClosure, reason: nil); return }
                        }
                    }
                    defer {
                        pingTask.cancel()
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    while !Task.isCancelled {
                        try Task.checkCancellation()
                        let data: Data
                        switch try await socket.receive() {
                        case .string(let value): data = Data(value.utf8)
                        case .data(let value): data = value
                        @unknown default: throw APIError.invalidResponse
                        }
                        continuation.yield(try decoder.decode(AIEvent.self, from: data))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func request<Value: Decodable>(_ path: String, method: String, body: Data?) async throws -> Value {
        let request = try await makeRequest(path, method: method, body: body)
        return try await response(request)
    }
    private func response<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            guard let failure = try? decoder.decode(Failure.self, from: data) else { throw APIError.response(http.statusCode, "サーバーとの通信に失敗しました") }
            throw APIError.response(http.statusCode, failure.error.message)
        }
        return try decoder.decode(Envelope<Value>.self, from: data).data
    }
    private func makeRequest(_ path: String, method: String, body: Data?) async throws -> URLRequest {
        guard let url = URL(string: config.apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v5/ai" + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(try await authSession.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
}
