import Foundation

enum ProductOpsProject {
    static let landlordSaaS = "landlord_saas"
    static let landlordSaaSVenture = "landlord-saas"
}

enum VentureDecision: String, Encodable, Hashable {
    case approved
    case deferred
    case rejected
}

struct VentureDecisionInboxPayload: Decodable, Hashable {
    var generatedAt: Date
    var recommendationStatus: String
    var lastGeneratedAt: Date?
    var lastError: String?
    var items: [VentureDecisionInboxItem]

    var recommendationStatusMessage: String? {
        switch recommendationStatus {
        case "queued":
            return "次の提案を準備待ちです。バックエンドのHeartbeatが生成します。"
        case "generating":
            return "次の提案を生成しています。完了すると通知されます。"
        case "failed":
            return lastError.map { "提案生成に失敗しました: \($0)" } ?? "提案生成に失敗しました。"
        default:
            return nil
        }
    }
}

struct VentureNextActionsPayload: Decodable, Hashable {
    var generatedAt: Date
    var decisionInbox: VentureDecisionInboxPayload
    var developmentMissions: [VentureDevelopmentMissionItem]
    var researchMissions: [VentureResearchMissionItem]
    var messageMissions: [VentureMessageMissionItem]
    var verificationMissions: [VentureVerificationMissionItem]
    var knowledgeChangeMissions: [VentureKnowledgeChangeMissionItem]
    var monitoringAlerts: [VentureMonitoringAlertItem]
    var missionProgress: VentureMissionProgressPayload
}

struct VentureDecisionInboxItem: Identifiable, Decodable, Hashable {
    var proposalId: String
    var title: String
    var whyNow: String
    var expectedOutcome: String
    var status: String
    var version: Int
    var rank: Int
    var totalScore: Double
    var actionKind: String
    var actionChannel: String
    var intentKind: String
    var betKind: String?
    var opportunityId: String?
    var hypothesisId: String?
    var approvalEffect: String
    var suggestedSuccessCriteria: [String]
    var suggestedStopConditions: [String]
    var availableDecisions: [String]

    var id: String { proposalId }

    var approvalLabel: String {
        switch actionKind {
        case "outreach":
            return "下書きを作る"
        case "research":
            return "調査を開始"
        case "build_experiment":
            return "Codexで試作"
        case "specify_experiment":
            return "仕様案を作る"
        case "analyze":
            return "分析する"
        default:
            return "承認"
        }
    }

    var actionLabel: String {
        switch actionKind {
        case "outreach":
            return "下書き"
        case "research":
            return "調査"
        case "build_experiment":
            return "Codex"
        case "specify_experiment":
            return "仕様"
        case "analyze":
            return "分析"
        default:
            return "Proposal"
        }
    }

    var approvalReason: String {
        switch actionKind {
        case "outreach":
            return "外部送信せず、質問文の下書きまで作る"
        case "research":
            return "追加調査を進める"
        case "build_experiment":
            return "Codexで小さな試作を進める"
        case "specify_experiment":
            return "実装前の仕様案を作る"
        case "analyze":
            return "情報整理と分析を進める"
        default:
            return "次の学習Betとして進める"
        }
    }
}

struct VentureDevelopmentMissionListPayload: Decodable, Hashable {
    var items: [VentureDevelopmentMissionItem]
}

struct VentureResearchMissionListPayload: Decodable, Hashable {
    var items: [VentureResearchMissionItem]
}

struct VentureMessageMissionListPayload: Decodable, Hashable {
    var items: [VentureMessageMissionItem]
}

struct VentureVerificationMissionListPayload: Decodable, Hashable {
    var items: [VentureVerificationMissionItem]
}

struct VentureKnowledgeChangeMissionListPayload: Decodable, Hashable {
    var items: [VentureKnowledgeChangeMissionItem]
}

struct VentureMonitoringAlertListPayload: Decodable, Hashable {
    var items: [VentureMonitoringAlertItem]
}

struct VentureMonitoringScanResult: Decodable, Hashable {
    var scannedAt: Date
    var detectedCount: Int
    var createdCount: Int
}

struct VentureSideEffectPolicy: Decodable, Hashable {
    var externalSend: Bool
    var repositoryWrite: Bool
    var dataMutation: Bool
    var productionChange: Bool
}

struct VentureMissionCatalogPayload: Decodable, Hashable {
    var generatedAt: Date
    var capabilities: [VentureMissionCapabilityCatalogEntry]
    var humanReviewBoundaries: [String]
}

struct VentureMissionCapabilityCatalogEntry: Decodable, Hashable, Identifiable {
    var capability: String
    var label: String
    var description: String
    var primaryDeliverableKind: String
    var executorPreference: String
    var sideEffectPolicy: VentureSideEffectPolicy
    var reviewPolicy: String
    var automationBoundary: String
    var humanDecision: String

    var id: String { capability }
}

struct VentureMissionProgressPayload: Decodable, Hashable {
    struct Totals: Decodable, Hashable {
        var total: Int
        var waitingForHuman: Int
        var running: Int
        var failed: Int
    }

    var generatedAt: Date
    var totals: Totals
    var capabilities: [VentureMissionCapabilityProgress]
    var humanReviewBoundaries: [String]
}

struct VentureMissionCapabilityProgress: Decodable, Hashable, Identifiable {
    var capability: String
    var label: String
    var primaryDeliverableKind: String
    var reviewPolicy: String
    var sideEffectPolicy: VentureSideEffectPolicy
    var total: Int
    var queued: Int
    var running: Int
    var awaitingReview: Int
    var failed: Int
    var completed: Int
    var canceled: Int

    var id: String { capability }
}

struct VentureDevelopmentMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureDevelopmentMission
    var result: VentureDevelopmentMissionResult?
    var deliverables: [VentureDeliverable]

    var id: String { mission.id }

    var productChangeDeliverable: VentureProductChangeDeliverable? {
        deliverables
            .first { $0.kind == "product_change" }?
            .productChangePayload
    }
}

struct VentureResearchMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureResearchMission
    var result: VentureResearchMissionResult?
    var deliverables: [VentureDeliverable]

    var id: String { mission.id }

    var researchReportDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "research_report" }
    }

    var researchReport: VentureResearchReportDeliverable? {
        researchReportDeliverable?.researchReportPayload
    }
}

struct VentureMessageMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureMessageMission
    var result: VentureMessageMissionResult?
    var deliverables: [VentureDeliverable]

    var id: String { mission.id }

    var messageDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "message" }
    }

    var message: VentureMessageDeliverable? {
        messageDeliverable?.messagePayload ?? result?.message
    }
}

struct VentureVerificationMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureVerificationMission
    var result: VentureVerificationMissionResult?
    var deliverables: [VentureDeliverable]

    var id: String { mission.id }

    var verificationReportDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "verification_report" }
    }

    var verificationReport: VentureVerificationReportDeliverable? {
        verificationReportDeliverable?.verificationReportPayload ?? result?.report
    }
}

struct VentureKnowledgeChangeMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureKnowledgeChangeMission
    var result: VentureKnowledgeChangeMissionResult?
    var deliverables: [VentureDeliverable]

    var id: String { mission.id }

    var knowledgeChangeDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "knowledge_change" }
    }

    var knowledgeChange: VentureKnowledgeChangeDeliverable? {
        knowledgeChangeDeliverable?.knowledgeChangePayload ?? result?.knowledgeChange
    }
}

struct VentureMonitoringAlertItem: Identifiable, Decodable, Hashable {
    var alert: VentureMonitoringAlert
    var deliverables: [VentureDeliverable]

    var id: String { alert.id }

    var alertDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "alert" }
    }

    var alertPayload: VentureAlertDeliverable? {
        alertDeliverable?.alertPayload ?? VentureAlertDeliverable(
            severity: alert.severity,
            detectedIssue: alert.detectedIssue,
            recommendedAction: alert.recommendedAction,
            entityRefs: alert.entityRefs
        )
    }
}

struct VentureDevelopmentMission: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var agentOwnerUserId: String
    var ventureId: String
    var betId: String
    var sourceProposalId: String
    var repositories: [String]
    var objective: String
    var specification: [String]
    var acceptanceCriteria: [String]
    var status: String
    var agentTaskId: String?
    var resultId: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureResearchMission: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var agentOwnerUserId: String
    var ventureId: String
    var betId: String
    var sourceProposalId: String
    var channel: String
    var objective: String
    var researchQuestion: String
    var targetSegment: String
    var inclusionCriteria: [String]
    var exclusionCriteria: [String]
    var sampleTarget: Int
    var completionCriteria: [String]
    var status: String
    var agentTaskId: String?
    var resultId: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureMessageMission: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var agentOwnerUserId: String
    var ventureId: String
    var betId: String
    var sourceProposalId: String
    var channel: String
    var purpose: String
    var objective: String
    var audience: String
    var messageGoal: String
    var context: [String]
    var constraints: [String]
    var status: String
    var agentTaskId: String?
    var resultId: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureVerificationMission: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var agentOwnerUserId: String
    var ventureId: String
    var sourceMissionId: String
    var sourceDeliverableId: String
    var sourceDeliverableKind: String
    var objective: String
    var criteria: [String]
    var status: String
    var agentTaskId: String?
    var resultId: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureKnowledgeChangeMission: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var agentOwnerUserId: String
    var ventureId: String
    var sourceLearningId: String
    var sourceDeliverableId: String
    var projectId: String
    var projectPolicyVersion: Int
    var objective: String
    var status: String
    var agentTaskId: String?
    var resultId: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureMonitoringAlert: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var ventureId: String
    var missionId: String
    var deliverableId: String
    var dedupeKey: String
    var severity: String
    var detectedIssue: String
    var recommendedAction: String
    var entityRefs: [String]
    var status: String
    var createdAt: Date
    var updatedAt: Date
}

struct VentureDevelopmentMissionResult: Decodable, Hashable {
    struct PullRequest: Decodable, Hashable {
        var repository: String
        var url: String
    }

    struct Check: Decodable, Hashable {
        var name: String
        var status: String
        var detail: String
    }

    var id: String
    var missionId: String
    var agentTaskId: String
    var summary: String
    var changedRepositories: [String]
    var pullRequests: [PullRequest]
    var checks: [Check]
    var unresolvedIssues: [String]
    var rawResult: ProductOpsMetadataValue?
    var submittedAt: Date
}

struct VentureResearchMissionResult: Decodable, Hashable {
    var id: String
    var missionId: String
    var agentTaskId: String
    var summary: String
    var report: VentureResearchReportDeliverable
    var rawResult: ProductOpsMetadataValue?
    var submittedAt: Date
}

struct VentureMessageMissionResult: Decodable, Hashable {
    var id: String
    var missionId: String
    var agentTaskId: String
    var summary: String
    var message: VentureMessageDeliverable
    var rawResult: ProductOpsMetadataValue?
    var submittedAt: Date
}

struct VentureVerificationMissionResult: Decodable, Hashable {
    var id: String
    var missionId: String
    var agentTaskId: String
    var summary: String
    var report: VentureVerificationReportDeliverable
    var rawResult: ProductOpsMetadataValue?
    var submittedAt: Date
}

struct VentureKnowledgeChangeMissionResult: Decodable, Hashable {
    var id: String
    var missionId: String
    var agentTaskId: String
    var summary: String
    var knowledgeChange: VentureKnowledgeChangeDeliverable
    var rawResult: ProductOpsMetadataValue?
    var submittedAt: Date
}

struct VentureDeliverable: Identifiable, Decodable, Hashable {
    var id: String
    var missionId: String
    var resultId: String?
    var kind: String
    var title: String
    var summary: String
    var payload: ProductOpsMetadataValue
    var createdAt: Date

    var productChangePayload: VentureProductChangeDeliverable? {
        guard kind == "product_change" else {
            return nil
        }
        return VentureProductChangeDeliverable(payload: payload)
    }

    var researchReportPayload: VentureResearchReportDeliverable? {
        guard kind == "research_report" else {
            return nil
        }
        return VentureResearchReportDeliverable(payload: payload)
    }

    var messagePayload: VentureMessageDeliverable? {
        guard kind == "message" else {
            return nil
        }
        return VentureMessageDeliverable(payload: payload)
    }

    var verificationReportPayload: VentureVerificationReportDeliverable? {
        guard kind == "verification_report" else {
            return nil
        }
        return VentureVerificationReportDeliverable(payload: payload)
    }

    var knowledgeChangePayload: VentureKnowledgeChangeDeliverable? {
        guard kind == "knowledge_change" else {
            return nil
        }
        return VentureKnowledgeChangeDeliverable(payload: payload)
    }

    var alertPayload: VentureAlertDeliverable? {
        guard kind == "alert" else {
            return nil
        }
        return VentureAlertDeliverable(payload: payload)
    }
}

struct VentureProductChangeDeliverable: Hashable {
    struct Check: Hashable {
        var name: String
        var status: String
        var detail: String
    }

    var changedBehavior: [String]
    var userVisibleImpact: String
    var changedRepositories: [String]
    var pullRequests: [String]
    var checks: [Check]
    var unresolvedIssues: [String]

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        changedBehavior = object["changedBehavior"]?.stringArrayValue ?? object["changed_behavior"]?.stringArrayValue ?? []
        userVisibleImpact = object["userVisibleImpact"]?.stringValue ?? object["user_visible_impact"]?.stringValue ?? ""
        changedRepositories = object["changedRepositories"]?.stringArrayValue ?? object["changed_repositories"]?.stringArrayValue ?? []
        pullRequests = object["pullRequests"]?.stringArrayValue ?? object["pull_requests"]?.stringArrayValue ?? []
        unresolvedIssues = object["unresolvedIssues"]?.stringArrayValue ?? object["unresolved_issues"]?.stringArrayValue ?? []
        checks = (object["checks"]?.arrayValue ?? []).compactMap { value in
            guard let check = value.objectValue else {
                return nil
            }
            return Check(
                name: check["name"]?.stringValue ?? "",
                status: check["status"]?.stringValue ?? "not_run",
                detail: check["detail"]?.stringValue ?? ""
            )
        }.filter { !$0.name.isEmpty }
    }
}

struct VentureResearchReportDeliverable: Decodable, Hashable {
    var researchQuestion: String
    var conclusion: String
    var findings: [String]
    var supportingEvidence: [String]
    var contradictingEvidence: [String]
    var sources: [String]
    var unknowns: [String]
    var nextQuestions: [String]

    init(
        researchQuestion: String,
        conclusion: String,
        findings: [String],
        supportingEvidence: [String],
        contradictingEvidence: [String],
        sources: [String],
        unknowns: [String],
        nextQuestions: [String]
    ) {
        self.researchQuestion = researchQuestion
        self.conclusion = conclusion
        self.findings = findings
        self.supportingEvidence = supportingEvidence
        self.contradictingEvidence = contradictingEvidence
        self.sources = sources
        self.unknowns = unknowns
        self.nextQuestions = nextQuestions
    }

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        researchQuestion = object["researchQuestion"]?.stringValue ?? object["research_question"]?.stringValue ?? ""
        conclusion = object["conclusion"]?.stringValue ?? ""
        findings = object["findings"]?.stringArrayValue ?? []
        supportingEvidence = object["supportingEvidence"]?.stringArrayValue ?? object["supporting_evidence"]?.stringArrayValue ?? []
        contradictingEvidence = object["contradictingEvidence"]?.stringArrayValue ?? object["contradicting_evidence"]?.stringArrayValue ?? []
        sources = object["sources"]?.stringArrayValue ?? []
        unknowns = object["unknowns"]?.stringArrayValue ?? []
        nextQuestions = object["nextQuestions"]?.stringArrayValue ?? object["next_questions"]?.stringArrayValue ?? []
    }
}

struct VentureMessageDeliverable: Decodable, Hashable {
    var channel: String
    var purpose: String
    var subject: String?
    var body: String
    var candidateRecipients: [String]

    init(
        channel: String,
        purpose: String,
        subject: String?,
        body: String,
        candidateRecipients: [String]
    ) {
        self.channel = channel
        self.purpose = purpose
        self.subject = subject
        self.body = body
        self.candidateRecipients = candidateRecipients
    }

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        channel = object["channel"]?.stringValue ?? ""
        purpose = object["purpose"]?.stringValue ?? ""
        subject = object["subject"]?.stringValue
        body = object["body"]?.stringValue ?? ""
        candidateRecipients = object["candidateRecipients"]?.stringArrayValue ?? object["candidate_recipients"]?.stringArrayValue ?? []
    }
}

struct VentureVerificationReportDeliverable: Decodable, Hashable {
    struct CheckedCriterion: Decodable, Hashable {
        var criterion: String
        var status: String
        var detail: String
    }

    var verdict: String
    var checkedCriteria: [CheckedCriterion]
    var risks: [String]
    var requiredFollowUps: [String]

    init(
        verdict: String,
        checkedCriteria: [CheckedCriterion],
        risks: [String],
        requiredFollowUps: [String]
    ) {
        self.verdict = verdict
        self.checkedCriteria = checkedCriteria
        self.risks = risks
        self.requiredFollowUps = requiredFollowUps
    }

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        verdict = object["verdict"]?.stringValue ?? "review_required"
        checkedCriteria = (object["checkedCriteria"]?.arrayValue ?? object["checked_criteria"]?.arrayValue ?? []).compactMap { value in
            guard let item = value.objectValue else {
                return nil
            }
            return CheckedCriterion(
                criterion: item["criterion"]?.stringValue ?? "",
                status: item["status"]?.stringValue ?? "not_run",
                detail: item["detail"]?.stringValue ?? ""
            )
        }.filter { !$0.criterion.isEmpty }
        risks = object["risks"]?.stringArrayValue ?? []
        requiredFollowUps = object["requiredFollowUps"]?.stringArrayValue ?? object["required_follow_ups"]?.stringArrayValue ?? []
    }
}

struct VentureKnowledgeChangeDeliverable: Decodable, Hashable {
    var currentState: String
    var proposedState: String
    var reason: String
    var sourceIds: [String]

    init(
        currentState: String,
        proposedState: String,
        reason: String,
        sourceIds: [String]
    ) {
        self.currentState = currentState
        self.proposedState = proposedState
        self.reason = reason
        self.sourceIds = sourceIds
    }

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        currentState = object["currentState"]?.stringValue ?? object["current_state"]?.stringValue ?? ""
        proposedState = object["proposedState"]?.stringValue ?? object["proposed_state"]?.stringValue ?? ""
        reason = object["reason"]?.stringValue ?? ""
        sourceIds = object["sourceIds"]?.stringArrayValue ?? object["source_ids"]?.stringArrayValue ?? []
    }
}

struct VentureAlertDeliverable: Decodable, Hashable {
    var severity: String
    var detectedIssue: String
    var recommendedAction: String
    var entityRefs: [String]

    init(
        severity: String,
        detectedIssue: String,
        recommendedAction: String,
        entityRefs: [String]
    ) {
        self.severity = severity
        self.detectedIssue = detectedIssue
        self.recommendedAction = recommendedAction
        self.entityRefs = entityRefs
    }

    init?(payload: ProductOpsMetadataValue) {
        guard let object = payload.objectValue else {
            return nil
        }
        severity = object["severity"]?.stringValue ?? "warning"
        detectedIssue = object["detectedIssue"]?.stringValue ?? object["detected_issue"]?.stringValue ?? ""
        recommendedAction = object["recommendedAction"]?.stringValue ?? object["recommended_action"]?.stringValue ?? ""
        entityRefs = object["entityRefs"]?.stringArrayValue ?? object["entity_refs"]?.stringArrayValue ?? []
    }
}

struct VentureRecommendationJob: Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var ventureId: String
    var reason: String
    var status: String
    var runAfter: Date
    var leaseUntil: Date?
    var attempts: Int
    var lastError: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

struct VentureRecommendationHeartbeatResult: Decodable, Hashable {
    var status: String
    var reason: String
    var recommendationStatus: String
    var job: VentureRecommendationJob?
    var recommendationSetId: String?
    var generatedCount: Int
    var lastError: String?
}

struct VentureProposalDecisionResult: Decodable, Hashable {
    struct ProposalSnapshot: Decodable, Hashable {
        var id: String
        var status: String
        var version: Int
        var updatedAt: Date
    }

    struct DecisionSnapshot: Decodable, Hashable {
        var id: String
        var proposalId: String
        var actorId: String
        var status: String
        var reason: String
        var decidedAt: Date
    }

    struct BetSnapshot: Decodable, Hashable {
        var id: String
        var ventureId: String
        var proposalId: String
        var decisionId: String
        var kind: String
        var status: String
        var successCriteria: [String]
        var stopConditions: [String]
        var committedAt: Date
    }

    var proposal: ProposalSnapshot
    var decision: DecisionSnapshot
    var bet: BetSnapshot?
    var developmentMission: VentureDevelopmentMission?
    var researchMission: VentureResearchMission?
    var messageMission: VentureMessageMission?
}

struct VentureLearningAdoptionResult: Decodable, Hashable {
    struct Learning: Decodable, Hashable {
        var id: String
        var ownerUserId: String
        var ventureId: String
        var missionId: String
        var deliverableId: String
        var opportunityId: String
        var hypothesisId: String
        var summary: String
        var payload: ProductOpsMetadataValue
        var adoptedAt: Date
    }

    var learning: Learning
    var recommendationJob: VentureRecommendationJob
}

struct Need: Identifiable, Decodable, Hashable {
    var id: String
    var title: String
    var summary: String
    var domain: String?
    var mvp: String?
    var priority: String?
    var status: String?
    var sourceType: String?
    var sourceUrl: URL?
    var sourceText: String?
    var sourceCreatedAt: Date?
    var sourceDedupeKey: String?
    var tags: [String]
    var tagIds: [String]
    var metadata: ProductOpsMetadataValue?
    var createdAt: Date
    var updatedAt: Date

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? summary : title
    }

    var displaySummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayTitle : summary
    }
}

struct NeedCandidate: Identifiable, Decodable, Hashable {
    var need: Need
    var evidenceSummary: NeedEvidenceSummary
    var policyFit: NeedPolicyFit
    var suggestedAction: String

    var id: String { need.id }
}

struct NeedEvidenceSummary: Decodable, Hashable {
    var supportingCount: Int
    var contradictingCount: Int
    var exampleCount: Int
    var totalCount: Int
}

struct NeedPolicyFit: Decodable, Hashable {
    var totalScore: Double
    var scores: NeedPolicyScores
    var reason: String
}

struct NeedPolicyScores: Decodable, Hashable {
    var frequency: Double
    var pain: Double
    var loss: Double
    var personaFit: Double
    var testability: Double
}

struct NeedPursueResult: Decodable, Hashable {
    var need: Need
    var suggestions: [ActionSuggestion]
}

struct NextActionsPayload: Decodable, Hashable {
    var summary: NextActionsSummary
    var items: [NextActionItem]

    func replacingItems(reorderedTodoItems: [NextActionItem]) -> NextActionsPayload {
        var nextItems = items
        var remainingTodoItems = reorderedTodoItems
        let reorderedIds = Set(reorderedTodoItems.map(\.id))

        for index in nextItems.indices where reorderedIds.contains(nextItems[index].id) && !remainingTodoItems.isEmpty {
            nextItems[index] = remainingTodoItems.removeFirst()
        }

        return NextActionsPayload(summary: summary, items: nextItems)
    }
}

struct NextActionsSummary: Decodable, Hashable {
    var todoCount: Int
    var runningCount: Int
    var laterCount: Int
    var blockedCount: Int
    var updatedAt: Date
}

struct NextActionItem: Identifiable, Decodable, Hashable {
    var id: String
    var kind: String
    var title: String
    var detail: String
    var status: String
    var priority: Double
    var primaryAction: NextActionCommand
    var secondaryActions: [NextActionCommand]
    var sourceId: String
    var sourceType: String
    var sourceVersion: Int
    var hostId: String?
    var route: String
    var updatedAt: Date
}

struct NextActionCommand: Decodable, Hashable {
    var label: String
    var action: String
}

struct ProjectPolicy: Identifiable, Decodable, Hashable {
    var id: String
    var projectId: String
    var targetPersona: String
    var productGoal: String
    var valueProposition: String
    var pricingHypothesis: String
    var evaluationCriteria: [String]
    var constraints: [String]
    var nonGoals: [String]
    var bodyMarkdown: String
    var version: Int
    var createdAt: Date
    var updatedAt: Date
}

struct ProjectPolicyEditableFields: Encodable, Hashable {
    var bodyMarkdown: String

    init(bodyMarkdown: String) {
        self.bodyMarkdown = bodyMarkdown
    }

    init(policy: ProjectPolicy) {
        bodyMarkdown = policy.bodyMarkdown
    }
}

struct DevelopmentTask: Identifiable, Decodable, Hashable {
    var id: String
    var projectId: String
    var needId: String?
    var sourceSpecResultId: String?
    var sourceSuggestionId: String?
    var codexSuggestionId: String?
    var title: String
    var summary: String
    var status: String
    var rank: Int
    var priority: String
    var assignedExecutor: String?
    var repositoryIds: [String]
    var createdAt: Date
    var updatedAt: Date
}

enum ProductOpsMetadataValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ProductOpsMetadataValue])
    case array([ProductOpsMetadataValue])
    case null

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: ProductOpsDynamicCodingKey.self) {
            var values: [String: ProductOpsMetadataValue] = [:]
            for key in object.allKeys {
                values[key.stringValue] = try object.decode(ProductOpsMetadataValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        if var array = try? decoder.unkeyedContainer() {
            var values: [ProductOpsMetadataValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(ProductOpsMetadataValue.self))
            }
            self = .array(values)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try single.decode(String.self))
        }
    }
}

extension ProductOpsMetadataValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: ProductOpsMetadataValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [ProductOpsMetadataValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var stringArrayValue: [String]? {
        guard let arrayValue else {
            return nil
        }
        return arrayValue.compactMap(\.stringValue)
    }
}

private struct ProductOpsDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
