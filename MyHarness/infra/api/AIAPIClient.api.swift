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
    func conversations() async throws -> [AIConversation] { try await request("/conversations", method: "GET", body: nil) }
    func conversation(_ id: String) async throws -> AIConversationDetail { try await request("/conversations/\(id)", method: "GET", body: nil) }
    func run(_ id: String) async throws -> AIRun { try await request("/runs/\(id)", method: "GET", body: nil) }
    func create(id: String, title: String) async throws -> AIConversation {
        try await request("/conversations", method: "POST", body: encoder.encode(["id": id, "title": title]))
    }
    func send(conversation: String, submission: Submission) async throws -> AIRun {
        try await request("/conversations/\(conversation)/runs", method: "POST", body: encoder.encode(submission))
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
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(String(after), forHTTPHeaderField: "Last-Event-ID")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                    guard http.statusCode == 200 else { throw APIError.response(http.statusCode, "実行状況への接続に失敗しました") }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        // AI v4 emits one JSON data line per event. Do not rely
                        // on AsyncLineSequence preserving empty separator lines.
                        if line.hasPrefix("data:") {
                            let data = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                            continuation.yield(try decoder.decode(AIEvent.self, from: data))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request<Value: Decodable>(_ path: String, method: String, body: Data?) async throws -> Value {
        let request = try await makeRequest(path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            guard let failure = try? decoder.decode(Failure.self, from: data) else { throw APIError.response(http.statusCode, "サーバーとの通信に失敗しました") }
            throw APIError.response(http.statusCode, failure.error.message)
        }
        return try decoder.decode(Envelope<Value>.self, from: data).data
    }
    private func makeRequest(_ path: String, method: String, body: Data?) async throws -> URLRequest {
        guard let url = URL(string: config.apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v4/ai" + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(try await authSession.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
}
