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
            case .requestFailed(let status, let message):
                return "APIエラー（\(status)）: \(message)"
            }
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            var code: String
            var message: String
        }

        var error: APIError
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

    private struct VentureNextActionsEnvelope: Decodable {
        var data: VentureNextActionsPayload
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

    private struct VentureProposalDetailEnvelope: Decodable {
        var data: VentureProposalDetail
    }

    private struct VentureMissionDetailEnvelope: Decodable {
        var data: VentureMissionDetail
    }

    private struct VentureDirectMissionRequestEnvelope: Decodable {
        var data: VentureDirectMissionRequestResult
    }

    private struct VentureDevelopmentMissionListEnvelope: Decodable {
        var data: VentureDevelopmentMissionListPayload
    }

    private struct VentureDevelopmentMissionEnvelope: Decodable {
        var data: VentureDevelopmentMissionItem
    }

    private struct VentureResearchMissionListEnvelope: Decodable {
        var data: VentureResearchMissionListPayload
    }

    private struct VentureResearchMissionEnvelope: Decodable {
        var data: VentureResearchMissionItem
    }

    private struct VentureMessageMissionListEnvelope: Decodable {
        var data: VentureMessageMissionListPayload
    }

    private struct VentureMessageMissionEnvelope: Decodable {
        var data: VentureMessageMissionItem
    }

    private struct VentureVerificationMissionListEnvelope: Decodable {
        var data: VentureVerificationMissionListPayload
    }

    private struct VentureVerificationMissionEnvelope: Decodable {
        var data: VentureVerificationMissionItem
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

    private struct VentureResearchClipCandidateEnvelope: Decodable {
        var data: VentureResearchClipCandidatePayload
    }

    private struct VentureResearchClipSaveEnvelope: Decodable {
        var data: VentureResearchClipSaveResult
    }

    private struct VentureResearchClipPageEnvelope: Decodable {
        var data: VentureResearchClipPage
    }

    private struct VentureResearchClipEnvelope: Decodable {
        var data: VentureResearchClip
    }

    private struct VentureResearchClipAssociationOptionsEnvelope: Decodable {
        var data: VentureResearchClipAssociationOptions
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

    private struct VenturePolicyEnvelope: Decodable {
        var data: VenturePolicy
    }

    private struct VenturePolicyRevisionContextEnvelope: Decodable {
        var data: VenturePolicyRevisionContext
    }

    private struct VenturePolicyRevisionEnvelope: Decodable {
        var data: VenturePolicyRevisionDetail
    }

    private struct DevelopmentTasksEnvelope: Decodable {
        var data: [DevelopmentTask]
    }

    private struct DevelopmentTaskEnvelope: Decodable {
        var data: DevelopmentTask
    }

    private struct PushDeviceEnvelope: Decodable {
        var data: PushDevice
    }

    private struct NotificationPreferencesEnvelope: Decodable {
        var data: PushNotificationPreferences
    }

    private struct BlogPostsEnvelope: Decodable {
        var data: [BlogPost]
    }

    private struct BlogPostEnvelope: Decodable {
        var data: BlogPost
    }

    private struct PushDevice: Decodable {
        var id: String
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

    private struct VentureResearchClipSaveRequest: Encodable {
        struct Item: Encodable {
            var itemKey: String
            var userNote: String
            var opportunityId: String?
            var hypothesisId: String?

            private enum CodingKeys: String, CodingKey {
                case itemKey
                case userNote
                case opportunityId
                case hypothesisId
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(itemKey, forKey: .itemKey)
                try container.encode(userNote, forKey: .userNote)
                if let opportunityId {
                    try container.encode(opportunityId, forKey: .opportunityId)
                } else {
                    try container.encodeNil(forKey: .opportunityId)
                }
                if let hypothesisId {
                    try container.encode(hypothesisId, forKey: .hypothesisId)
                } else {
                    try container.encodeNil(forKey: .hypothesisId)
                }
            }
        }

        var items: [Item]
    }

    private struct VentureResearchClipUpdateRequest: Encodable {
        var expectedVersion: Int
        var userNote: String
        var opportunityId: String?
        var hypothesisId: String?

        private enum CodingKeys: String, CodingKey {
            case expectedVersion
            case userNote
            case opportunityId
            case hypothesisId
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(expectedVersion, forKey: .expectedVersion)
            try container.encode(userNote, forKey: .userNote)
            if let opportunityId {
                try container.encode(opportunityId, forKey: .opportunityId)
            } else {
                try container.encodeNil(forKey: .opportunityId)
            }
            if let hypothesisId {
                try container.encode(hypothesisId, forKey: .hypothesisId)
            } else {
                try container.encodeNil(forKey: .hypothesisId)
            }
        }
    }

    private struct VentureResearchClipVersionRequest: Encodable {
        var expectedVersion: Int
    }

    private struct VentureDeliverableReviewRequest: Encodable {
        var expectedMissionVersion: Int
        var expectedRevisionHash: String?
        var decision: String
        var feedback: String

        private enum CodingKeys: String, CodingKey {
            case expectedMissionVersion
            case expectedRevisionHash
            case decision
            case feedback
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(expectedMissionVersion, forKey: .expectedMissionVersion)
            if let expectedRevisionHash {
                try container.encode(expectedRevisionHash, forKey: .expectedRevisionHash)
            } else {
                try container.encodeNil(forKey: .expectedRevisionHash)
            }
            try container.encode(decision, forKey: .decision)
            try container.encode(feedback, forKey: .feedback)
        }
    }

    private struct VentureMissionRetryRequest: Encodable {
        var expectedMissionVersion: Int
        var feedback: String
    }

    private struct VentureMissionCancelRequest: Encodable {
        var expectedMissionVersion: Int
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
    private var isBootstrapped = false
    private var bootstrapTask: Task<Void, Error>?

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

    func fetchBlogPosts() async throws -> [BlogPost] {
        let data = try await request(path: "/api/blog-posts", method: "GET")
        return try decoder.decode(BlogPostsEnvelope.self, from: data).data
    }

    func fetchBlogPost(id: String) async throws -> BlogPost {
        guard UUID(uuidString: id) != nil else {
            throw ClientError.invalidResponse
        }
        let data = try await request(path: "/api/blog-posts/\(id.lowercased())", method: "GET")
        return try decoder.decode(BlogPostEnvelope.self, from: data).data
    }

    func bootstrapCurrentUser() async throws {
        if isBootstrapped { return }
        if let bootstrapTask {
            return try await bootstrapTask.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
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
                let body = String(data: data, encoding: .utf8) ?? ""
                let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message) ?? body
                throw ClientError.requestFailed(httpResponse.statusCode, message)
            }
            isBootstrapped = true
        }
        bootstrapTask = task
        do {
            try await task.value
            bootstrapTask = nil
        } catch {
            bootstrapTask = nil
            throw error
        }
    }

    func invalidateBootstrap() {
        isBootstrapped = false
        bootstrapTask?.cancel()
        bootstrapTask = nil
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

    func fetchVentureNextActions(ventureId: String, limit: Int = 10, cursor: String? = nil) async throws -> VentureNextActionsPayload {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let data = try await request(
            path: "/api/v2/ventures/\(ventureId)/next-actions",
            method: "GET",
            queryItems: queryItems
        )
        return try decoder.decode(VentureNextActionsEnvelope.self, from: data).data
    }

    func fetchVentureMissionDetail(missionId: String) async throws -> VentureMissionDetail {
        let data = try await request(path: "/api/v2/missions/\(missionId)", method: "GET")
        return try decoder.decode(VentureMissionDetailEnvelope.self, from: data).data
    }

    func createDirectMission(
        ventureId: String,
        request directRequest: VentureDirectMissionRequest
    ) async throws -> VentureDirectMissionRequestResult {
        let data: Data
        switch directRequest {
        case .research(let requestBody):
            data = try await request(
                path: "/api/v2/ventures/\(ventureId)/mission-requests",
                method: "POST",
                body: requestBody
            )
        case .message(let requestBody):
            data = try await request(
                path: "/api/v2/ventures/\(ventureId)/mission-requests",
                method: "POST",
                body: requestBody
            )
        }
        return try decoder.decode(VentureDirectMissionRequestEnvelope.self, from: data).data
    }

    func fetchVentureProposalDetail(proposalId: String) async throws -> VentureProposalDetail {
        let data = try await request(path: "/api/v2/proposals/\(proposalId)", method: "GET")
        return try decoder.decode(VentureProposalDetailEnvelope.self, from: data).data
    }

    func reviewVentureDeliverable(
        deliverableId: String,
        expectedMissionVersion: Int,
        expectedRevisionHash: String?,
        decision: String,
        feedback: String
    ) async throws {
        try await request(
            path: "/api/v2/deliverables/\(deliverableId)/reviews",
            method: "POST",
            body: VentureDeliverableReviewRequest(
                expectedMissionVersion: expectedMissionVersion,
                expectedRevisionHash: expectedRevisionHash,
                decision: decision,
                feedback: feedback
            )
        )
    }

    func retryVentureMission(missionId: String, expectedMissionVersion: Int, feedback: String) async throws {
        try await request(
            path: "/api/v2/missions/\(missionId)/retry",
            method: "POST",
            body: VentureMissionRetryRequest(expectedMissionVersion: expectedMissionVersion, feedback: feedback)
        )
    }

    func cancelVentureMission(missionId: String, expectedMissionVersion: Int) async throws {
        try await request(
            path: "/api/v2/missions/\(missionId)/cancel",
            method: "POST",
            body: VentureMissionCancelRequest(expectedMissionVersion: expectedMissionVersion)
        )
    }

    func dismissVentureMission(missionId: String) async throws {
        try await request(
            path: "/api/v2/missions/\(missionId)/dismiss",
            method: "POST"
        )
    }

    func fetchVentureDevelopmentMissions(ventureId: String) async throws -> VentureDevelopmentMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/development-missions", method: "GET")
        return try decoder.decode(VentureDevelopmentMissionListEnvelope.self, from: data).data
    }

    func fetchVentureResearchMissions(ventureId: String) async throws -> VentureResearchMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/research-missions", method: "GET")
        return try decoder.decode(VentureResearchMissionListEnvelope.self, from: data).data
    }

    func fetchResearchClipCandidates(deliverableId: String) async throws -> VentureResearchClipCandidatePayload {
        let data = try await request(
            path: "/api/v2/deliverables/\(deliverableId)/research-clip-candidates",
            method: "GET"
        )
        return try decoder.decode(VentureResearchClipCandidateEnvelope.self, from: data).data
    }

    func saveResearchClip(
        deliverableId: String,
        itemKey: String,
        userNote: String,
        opportunityId: String?,
        hypothesisId: String?
    ) async throws -> VentureResearchClipSaveResult.Item {
        let data = try await request(
            path: "/api/v2/deliverables/\(deliverableId)/research-clips",
            method: "POST",
            body: VentureResearchClipSaveRequest(items: [.init(
                itemKey: itemKey,
                userNote: userNote,
                opportunityId: opportunityId,
                hypothesisId: hypothesisId
            )])
        )
        guard let item = try decoder.decode(VentureResearchClipSaveEnvelope.self, from: data).data.items.first else {
            throw ClientError.invalidResponse
        }
        return item
    }

    func fetchResearchClips(ventureId: String, cursor: String? = nil) async throws -> VentureResearchClipPage {
        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let data = try await request(
            path: "/api/v2/ventures/\(ventureId)/research-clips",
            method: "GET",
            queryItems: queryItems
        )
        return try decoder.decode(VentureResearchClipPageEnvelope.self, from: data).data
    }

    func fetchResearchClipAssociationOptions(ventureId: String) async throws -> VentureResearchClipAssociationOptions {
        let data = try await request(
            path: "/api/v2/ventures/\(ventureId)/research-clip-association-options",
            method: "GET"
        )
        return try decoder.decode(VentureResearchClipAssociationOptionsEnvelope.self, from: data).data
    }

    func updateResearchClip(
        clipId: String,
        expectedVersion: Int,
        userNote: String,
        opportunityId: String?,
        hypothesisId: String?
    ) async throws -> VentureResearchClip {
        let data = try await request(
            path: "/api/v2/research-clips/\(clipId)",
            method: "PATCH",
            body: VentureResearchClipUpdateRequest(
                expectedVersion: expectedVersion,
                userNote: userNote,
                opportunityId: opportunityId,
                hypothesisId: hypothesisId
            )
        )
        return try decoder.decode(VentureResearchClipEnvelope.self, from: data).data
    }

    func archiveResearchClip(clipId: String, expectedVersion: Int) async throws -> VentureResearchClip {
        let data = try await request(
            path: "/api/v2/research-clips/\(clipId)/archive",
            method: "POST",
            body: VentureResearchClipVersionRequest(expectedVersion: expectedVersion)
        )
        return try decoder.decode(VentureResearchClipEnvelope.self, from: data).data
    }

    func fetchVentureMessageMissions(ventureId: String) async throws -> VentureMessageMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/message-missions", method: "GET")
        return try decoder.decode(VentureMessageMissionListEnvelope.self, from: data).data
    }

    func fetchVentureVerificationMissions(ventureId: String) async throws -> VentureVerificationMissionListPayload {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/verification-missions", method: "GET")
        return try decoder.decode(VentureVerificationMissionListEnvelope.self, from: data).data
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

    func fetchVenturePolicy(ventureId: String) async throws -> VenturePolicy {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/policy", method: "GET")
        return try decoder.decode(VenturePolicyEnvelope.self, from: data).data
    }

    func fetchVenturePolicyRevisionContext(ventureId: String) async throws -> VenturePolicyRevisionContext {
        let data = try await request(path: "/api/v2/ventures/\(ventureId)/policy-context", method: "GET")
        return try decoder.decode(VenturePolicyRevisionContextEnvelope.self, from: data).data
    }

    func createVenturePolicyRevision(
        ventureId: String,
        request payload: VenturePolicyRevisionDraft
    ) async throws -> VenturePolicyRevisionDetail {
        let data = try await request(
            path: "/api/v2/ventures/\(ventureId)/policy-revisions",
            method: "POST",
            body: payload
        )
        return try decoder.decode(VenturePolicyRevisionEnvelope.self, from: data).data
    }

    func fetchVenturePolicyRevision(missionId: String) async throws -> VenturePolicyRevisionDetail {
        let data = try await request(path: "/api/v2/policy-revisions/\(missionId)", method: "GET")
        return try decoder.decode(VenturePolicyRevisionEnvelope.self, from: data).data
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
    ) async throws -> String {
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
        guard !data.isEmpty else { throw ClientError.invalidResponse }
        let device = try decoder.decode(PushDeviceEnvelope.self, from: data).data
        guard !device.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidResponse
        }
        return device.id
    }

    func fetchNotificationPreferences() async throws -> PushNotificationPreferences {
        let data = try await request(path: "/api/v2/notification-preferences", method: "GET")
        return try decoder.decode(NotificationPreferencesEnvelope.self, from: data).data
    }

    func updateNotificationPreferences(
        _ preferences: PushNotificationPreferences
    ) async throws -> PushNotificationPreferences {
        let data = try await request(
            path: "/api/v2/notification-preferences",
            method: "PUT",
            body: preferences
        )
        return try decoder.decode(NotificationPreferencesEnvelope.self, from: data).data
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
        try await bootstrapCurrentUser()
        return try await sendAuthenticatedRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            canRecoverBootstrap: true
        )
    }

    private func sendAuthenticatedRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        canRecoverBootstrap: Bool
    ) async throws -> Data {
        var request = URLRequest(
            url: endpoint(path: path, queryItems: queryItems),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
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
            let apiError = try? decoder.decode(ErrorEnvelope.self, from: data).error
            if canRecoverBootstrap,
               httpResponse.statusCode == 404,
               apiError?.code == "USER_NOT_BOOTSTRAPPED" {
                invalidateBootstrap()
                try await bootstrapCurrentUser()
                return try await sendAuthenticatedRequest(
                    path: path,
                    method: method,
                    queryItems: queryItems,
                    bodyData: bodyData,
                    canRecoverBootstrap: false
                )
            }
            let message = apiError?.message ?? body
            throw ClientError.requestFailed(httpResponse.statusCode, message)
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
