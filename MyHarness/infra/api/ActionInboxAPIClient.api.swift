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

    private struct NeedCandidatesEnvelope: Decodable {
        var data: [NeedCandidate]
    }

    private struct NextActionsEnvelope: Decodable {
        var data: NextActionsPayload
    }

    private struct VentureDecisionInboxEnvelope: Decodable {
        var data: VentureDecisionInboxPayload
    }

    private struct VentureProposalGenerateEnvelope: Decodable {
        var data: VentureProposalGenerateResult
    }

    private struct VentureRecommendationHeartbeatEnvelope: Decodable {
        var data: VentureRecommendationHeartbeatResult
    }

    private struct VentureProposalDecisionEnvelope: Decodable {
        var data: VentureProposalDecisionResult
    }

    private struct VentureDevelopmentMissionListEnvelope: Decodable {
        var data: VentureDevelopmentMissionListPayload
    }

    private struct VentureResearchMissionListEnvelope: Decodable {
        var data: VentureResearchMissionListPayload
    }

    private struct VentureMessageMissionListEnvelope: Decodable {
        var data: VentureMessageMissionListPayload
    }

    private struct VentureVerificationMissionListEnvelope: Decodable {
        var data: VentureVerificationMissionListPayload
    }

    private struct VentureKnowledgeChangeMissionListEnvelope: Decodable {
        var data: VentureKnowledgeChangeMissionListPayload
    }

    private struct VentureMonitoringAlertListEnvelope: Decodable {
        var data: VentureMonitoringAlertListPayload
    }

    private struct VentureMonitoringScanEnvelope: Decodable {
        var data: VentureMonitoringScanResult
    }

    private struct VentureMissionCatalogEnvelope: Decodable {
        var data: VentureMissionCatalogPayload
    }

    private struct VentureMissionProgressEnvelope: Decodable {
        var data: VentureMissionProgressPayload
    }

    private struct VentureLearningAdoptionEnvelope: Decodable {
        var data: VentureLearningAdoptionResult
    }

    private struct NeedsEnvelope: Decodable {
        var data: [Need]
    }

    private struct NeedEnvelope: Decodable {
        var data: Need
    }

    private struct NeedPursueEnvelope: Decodable {
        var data: NeedPursueResult
    }

    private struct ProjectPolicyEnvelope: Decodable {
        var data: ProjectPolicy
    }

    private struct DevelopmentTasksEnvelope: Decodable {
        var data: [DevelopmentTask]
    }

    private struct DevelopmentTaskEnvelope: Decodable {
        var data: DevelopmentTask
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

    private struct ProjectRequest: Encodable {
        var projectId: String
    }

    private struct NeedDecisionRequest: Encodable {
        var decisionNote: String?
    }

    private struct NeedMemoRequest: Encodable {
        var projectId: String
        var memo: String
        var sourceType: String
    }

    private struct DevelopmentTaskPatchRequest: Encodable {
        var status: String?
        var priority: String?
        var assignedExecutor: String?
    }

    private struct DevelopmentTasksReorderRequest: Encodable {
        var projectId: String
        var orderedIds: [String]
    }

    private struct VentureProposalGenerateResult: Decodable {
        var recommendationSetId: String
        var generatedAt: Date
        var count: Int
    }

    private struct VentureProposalDecisionRequest: Encodable {
        struct BetCommitment: Encodable {
            var successCriteria: [String]
            var stopConditions: [String]
        }

        var expectedVersion: Int
        var decision: VentureDecision
        var reason: String
        var feedback: DecisionFeedback?
        var betCommitment: BetCommitment?

        struct DecisionFeedback: Encodable {
            var reasonCodes: [String]
            var note: String?
            var preferredProposalId: String?
        }
    }

    private struct VentureLearningAdoptionRequest: Encodable {
        var decisionNote: String
    }

    private struct EmptyRequest: Encodable {}

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

    func fetchNextActions(projectId: String) async throws -> NextActionsPayload {
        let data = try await request(
            path: "/api/product-ops/next-actions",
            method: "GET",
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        return try decoder.decode(NextActionsEnvelope.self, from: data).data
    }

    func fetchVentureDecisionInbox(ventureId: String) async throws -> VentureDecisionInboxPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/decision-inbox", method: "GET")
        return try decoder.decode(VentureDecisionInboxEnvelope.self, from: data).data
    }

    func fetchVentureDevelopmentMissions(ventureId: String) async throws -> VentureDevelopmentMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/development-missions", method: "GET")
        return try decoder.decode(VentureDevelopmentMissionListEnvelope.self, from: data).data
    }

    func fetchVentureResearchMissions(ventureId: String) async throws -> VentureResearchMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/research-missions", method: "GET")
        return try decoder.decode(VentureResearchMissionListEnvelope.self, from: data).data
    }

    func fetchVentureMessageMissions(ventureId: String) async throws -> VentureMessageMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/message-missions", method: "GET")
        return try decoder.decode(VentureMessageMissionListEnvelope.self, from: data).data
    }

    func fetchVentureVerificationMissions(ventureId: String) async throws -> VentureVerificationMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/verification-missions", method: "GET")
        return try decoder.decode(VentureVerificationMissionListEnvelope.self, from: data).data
    }

    func fetchVentureKnowledgeChangeMissions(ventureId: String) async throws -> VentureKnowledgeChangeMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/knowledge-change-missions", method: "GET")
        return try decoder.decode(VentureKnowledgeChangeMissionListEnvelope.self, from: data).data
    }

    func fetchVentureMonitoringAlerts(ventureId: String) async throws -> VentureMonitoringAlertListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/monitoring-alerts", method: "GET")
        return try decoder.decode(VentureMonitoringAlertListEnvelope.self, from: data).data
    }

    func scanVentureMonitoringAlerts(ventureId: String) async throws -> VentureMonitoringScanResult {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/monitoring-alerts/scan", method: "POST", body: EmptyRequest())
        return try decoder.decode(VentureMonitoringScanEnvelope.self, from: data).data
    }

    func fetchVentureMissionCatalog() async throws -> VentureMissionCatalogPayload {
        let data = try await request(path: "/api/v2/mission-catalog", method: "GET")
        return try decoder.decode(VentureMissionCatalogEnvelope.self, from: data).data
    }

    func fetchVentureMissionProgress(ventureId: String) async throws -> VentureMissionProgressPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/mission-progress", method: "GET")
        return try decoder.decode(VentureMissionProgressEnvelope.self, from: data).data
    }

    func adoptResearchLearning(deliverableId: String, decisionNote: String) async throws -> VentureLearningAdoptionResult {
        let data = try await request(
            path: "/api/v2/deliverables/\(deliverableId)/adopt-learning",
            method: "POST",
            body: VentureLearningAdoptionRequest(decisionNote: decisionNote)
        )
        return try decoder.decode(VentureLearningAdoptionEnvelope.self, from: data).data
    }

    @discardableResult
    func generateVentureProposals(ventureId: String) async throws -> Int {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/proposals/generate", method: "POST", body: EmptyRequest())
        return try decoder.decode(VentureProposalGenerateEnvelope.self, from: data).data.count
    }

    @discardableResult
    func runVentureRecommendationHeartbeat(ventureId: String) async throws -> VentureRecommendationHeartbeatResult {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/recommendations/heartbeat", method: "POST", body: EmptyRequest())
        return try decoder.decode(VentureRecommendationHeartbeatEnvelope.self, from: data).data
    }

    @discardableResult
    func decideVentureProposal(
        proposalId: String,
        expectedVersion: Int,
        decision: VentureDecision,
        reason: String,
        reasonCodes: [String],
        feedbackNote: String?,
        preferredProposalId: String?,
        successCriteria: [String],
        stopConditions: [String]
    ) async throws -> VentureProposalDecisionResult {
        let commitment = decision == .approved
            ? VentureProposalDecisionRequest.BetCommitment(successCriteria: successCriteria, stopConditions: stopConditions)
            : nil
        let data = try await request(
            path: "/api/v2/proposals/\(proposalId)/decisions",
            method: "POST",
            body: VentureProposalDecisionRequest(
                expectedVersion: expectedVersion,
                decision: decision,
                reason: reason,
                feedback: VentureProposalDecisionRequest.DecisionFeedback(
                    reasonCodes: reasonCodes,
                    note: feedbackNote,
                    preferredProposalId: preferredProposalId
                ),
                betCommitment: commitment
            )
        )
        return try decoder.decode(VentureProposalDecisionEnvelope.self, from: data).data
    }

    func fetchNeeds() async throws -> [Need] {
        let data = try await request(path: "/api/needs", method: "GET")
        return try decoder.decode(NeedsEnvelope.self, from: data).data
    }

    func fetchSuggestion(id: String) async throws -> ActionSuggestion {
        let data = try await request(path: "/api/action-suggestions/\(id)", method: "GET")
        return try decoder.decode(SuggestionEnvelope.self, from: data).data
    }

    func fetchNeedCandidates(projectId: String) async throws -> [NeedCandidate] {
        let data = try await request(
            path: "/api/need-candidates",
            method: "GET",
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        return try decoder.decode(NeedCandidatesEnvelope.self, from: data).data
    }

    func pursueNeedCandidate(id: String, projectId: String) async throws -> NeedPursueResult {
        let data = try await request(
            path: "/api/needs/\(id)/pursue",
            method: "POST",
            body: ProjectRequest(projectId: projectId)
        )
        return try decoder.decode(NeedPursueEnvelope.self, from: data).data
    }

    func holdNeedCandidate(id: String, decisionNote: String?) async throws -> Need {
        let data = try await request(
            path: "/api/needs/\(id)/hold",
            method: "POST",
            body: NeedDecisionRequest(decisionNote: decisionNote)
        )
        return try decoder.decode(NeedEnvelope.self, from: data).data
    }

    func rejectNeedCandidate(id: String, decisionNote: String?) async throws -> Need {
        let data = try await request(
            path: "/api/needs/\(id)/reject-candidate",
            method: "POST",
            body: NeedDecisionRequest(decisionNote: decisionNote)
        )
        return try decoder.decode(NeedEnvelope.self, from: data).data
    }

    func createNeedFromMemo(projectId: String, memo: String) async throws -> Need {
        let data = try await request(
            path: "/api/needs/from-memo",
            method: "POST",
            body: NeedMemoRequest(projectId: projectId, memo: memo, sourceType: "manual")
        )
        return try decoder.decode(NeedEnvelope.self, from: data).data
    }

    func fetchProjectPolicy(projectId: String) async throws -> ProjectPolicy {
        let data = try await request(path: "/api/project-policies/\(projectId)", method: "GET")
        return try decoder.decode(ProjectPolicyEnvelope.self, from: data).data
    }

    func updateProjectPolicy(projectId: String, fields: ProjectPolicyEditableFields) async throws -> ProjectPolicy {
        let data = try await request(
            path: "/api/project-policies/\(projectId)",
            method: "PATCH",
            body: fields
        )
        return try decoder.decode(ProjectPolicyEnvelope.self, from: data).data
    }

    func fetchDevelopmentTasks(projectId: String) async throws -> [DevelopmentTask] {
        let data = try await request(
            path: "/api/development-tasks",
            method: "GET",
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        return try decoder.decode(DevelopmentTasksEnvelope.self, from: data).data
    }

    func updateDevelopmentTask(
        id: String,
        status: String?,
        priority: String?,
        assignedExecutor: String?
    ) async throws -> DevelopmentTask {
        let data = try await request(
            path: "/api/development-tasks/\(id)",
            method: "PATCH",
            body: DevelopmentTaskPatchRequest(
                status: status,
                priority: priority,
                assignedExecutor: assignedExecutor
            )
        )
        return try decoder.decode(DevelopmentTaskEnvelope.self, from: data).data
    }

    func reorderDevelopmentTasks(projectId: String, orderedIds: [String]) async throws -> [DevelopmentTask] {
        let data = try await request(
            path: "/api/development-tasks/reorder",
            method: "POST",
            body: DevelopmentTasksReorderRequest(projectId: projectId, orderedIds: orderedIds)
        )
        return try decoder.decode(DevelopmentTasksEnvelope.self, from: data).data
    }

    func startCodexDevelopmentTask(id: String) async throws -> ActionSuggestion {
        let data = try await request(
            path: "/api/development-tasks/\(id)/start-codex",
            method: "POST",
            body: EmptyRequest()
        )
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
        try await request(path: path, method: method, queryItems: [], bodyData: nil)
    }

    @discardableResult
    private func request(path: String, method: String, queryItems: [URLQueryItem]) async throws -> Data {
        try await request(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    @discardableResult
    private func request<T: Encodable>(path: String, method: String, body: T) async throws -> Data {
        try await request(path: path, method: method, queryItems: [], bodyData: encoder.encode(body))
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Data {
        var request = URLRequest(url: endpoint(path: path, queryItems: queryItems))
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

    private func endpoint(path: String, queryItems: [URLQueryItem]) -> URL {
        let trimmed = path.split(separator: "/").map(String.init)
        let url = trimmed.reduce(config.apiBaseURL) { url, component in
            url.appendingPathComponent(component)
        }
        guard !queryItems.isEmpty else {
            return url
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
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
