import Foundation

@MainActor
final class ActionInboxAPIClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "APIレスポンスを解釈できません。"
            case .requestFailed(let status, let body):
                return "API request failed: \(status) \(body)"
            }
        }
    }

    enum PushEnvironment: String, Codable {
        case development
        case production
    }

    private struct InboxEnvelope: Decodable {
        var data: ActionInboxPayload
    }

    private struct SuggestionEnvelope: Decodable {
        var data: ActionSuggestion
    }

    private struct PushDeviceEnvelope: Decodable {
        var data: PushDevice?
    }

    private struct PushDevice: Decodable {
        var id: String?
    }

    private struct DecisionRequest: Encodable {
        var decision: ActionSuggestionDecision
        var expectedVersion: Int
        var decisionNote: String?
        var hostId: String?
    }

    private struct VersionedOperationRequest: Encodable {
        var expectedVersion: Int
        var decisionNote: String?
        var hostId: String?
    }

    private struct PushDeviceRequest: Encodable {
        var platform: String
        var token: String
        var environment: PushEnvironment
        var appVersion: String
    }

    private let config: ActionInboxConfig
    private let authSession: CognitoAuthSession
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

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
            try ActionInboxDateDecoder.decode(decoder)
        }
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
    }

    func fetchInbox() async throws -> ActionInboxPayload {
        let data = try await request(path: "/api/action-inbox", method: "GET")
        return try decoder.decode(InboxEnvelope.self, from: data).data
    }

    func fetchSuggestion(id: String) async throws -> ActionSuggestion {
        let data = try await request(path: "/api/action-suggestions/\(id)", method: "GET")
        return try decoder.decode(SuggestionEnvelope.self, from: data).data
    }

    func decideSuggestion(
        id: String,
        decision: ActionSuggestionDecision,
        expectedVersion: Int,
        decisionNote: String?,
        hostId: String?
    ) async throws {
        try await request(
            path: "/api/action-suggestions/\(id)/decision",
            method: "POST",
            body: DecisionRequest(
                decision: decision,
                expectedVersion: expectedVersion,
                decisionNote: decisionNote,
                hostId: hostId
            )
        )
    }

    func adoptResult(
        id: String,
        expectedVersion: Int,
        decisionNote: String?,
        hostId: String?
    ) async throws {
        try await versionedSuggestionOperation(
            id: id,
            suffix: "adopt-result",
            expectedVersion: expectedVersion,
            decisionNote: decisionNote,
            hostId: hostId
        )
    }

    func rejectResult(
        id: String,
        expectedVersion: Int,
        decisionNote: String?,
        hostId: String?
    ) async throws {
        try await versionedSuggestionOperation(
            id: id,
            suffix: "reject-result",
            expectedVersion: expectedVersion,
            decisionNote: decisionNote,
            hostId: hostId
        )
    }

    func cancelSuggestion(
        id: String,
        expectedVersion: Int,
        decisionNote: String?,
        hostId: String?
    ) async throws {
        try await versionedSuggestionOperation(
            id: id,
            suffix: "cancel",
            expectedVersion: expectedVersion,
            decisionNote: decisionNote,
            hostId: hostId
        )
    }

    func registerPushDevice(
        token: String,
        environment: PushEnvironment,
        appVersion: String
    ) async throws -> String? {
        let data = try await request(
            path: "/api/push-devices",
            method: "POST",
            body: PushDeviceRequest(
                platform: "ios",
                token: token,
                environment: environment,
                appVersion: appVersion
            )
        )
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(PushDeviceEnvelope.self, from: data).data?.id
    }

    func deletePushDevice(id: String) async throws {
        try await request(path: "/api/push-devices/\(id)", method: "DELETE")
    }

    private func versionedSuggestionOperation(
        id: String,
        suffix: String,
        expectedVersion: Int,
        decisionNote: String?,
        hostId: String?
    ) async throws {
        try await request(
            path: "/api/action-suggestions/\(id)/\(suffix)",
            method: "POST",
            body: VersionedOperationRequest(
                expectedVersion: expectedVersion,
                decisionNote: decisionNote,
                hostId: hostId
            )
        )
    }

    @discardableResult
    private func request(path: String, method: String) async throws -> Data {
        try await request(path: path, method: method, bodyData: nil)
    }

    @discardableResult
    private func request<T: Encodable>(path: String, method: String, body: T) async throws -> Data {
        try await request(path: path, method: method, bodyData: encoder.encode(body))
    }

    private func request(path: String, method: String, bodyData: Data?) async throws -> Data {
        var request = URLRequest(url: endpoint(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try await authSession.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.requestFailed(httpResponse.statusCode, body)
        }
        return data
    }

    private func endpoint(path: String) -> URL {
        let trimmed = path.split(separator: "/").map(String.init)
        return trimmed.reduce(config.apiBaseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

}

private enum ActionInboxDateDecoder {
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
    }
}
