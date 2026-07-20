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

enum VentureDirectMissionRequest: Hashable {
    case research(VentureDirectResearchMissionRequest)
    case message(VentureDirectMessageMissionRequest)

    var clientRequestId: String {
        switch self {
        case .research(let request): request.clientRequestId
        case .message(let request): request.clientRequestId
        }
    }
}

struct VentureDirectResearchMissionRequest: Encodable, Hashable {
    struct TargetSegment: Encodable, Hashable {
        var kind: String
    }

    var clientRequestId: String
    let kind = "research"
    var instruction: String
    var channel: String
    var targetSegment: TargetSegment
    var sampleTarget: Int
    var inclusionCriteria: [String]
    var exclusionCriteria: [String]
    var relatedOpportunityId: String?
    var relatedHypothesisId: String?
}

struct VentureDirectMessageMissionRequest: Encodable, Hashable {
    var clientRequestId: String
    let kind = "message"
    var instruction: String
    var channel: String
    var purpose: String
    var audience: String
    var sourceUrl: String?
    var sourceText: String?
    var tone: String
    var constraints: [String]
}

struct VentureDirectMissionRequestResult: Decodable, Hashable {
    var requestId: String
    var missionId: String
    var kind: String
    var status: String
    var createdAt: Date
}

struct VentureDecisionInboxPayload: Decodable, Hashable {
    var generatedAt: Date
    var recommendationStatus: String
    var lastGeneratedAt: Date?
    var lastSynthesisAt: Date?
    var lastError: String?
    var idleReason: String?
    var agenda: VentureDecisionAgendaSummary?
    var items: [VentureDecisionInboxItem]

    var recommendationStatusMessage: String? {
        switch recommendationStatus {
        case "queued":
            return "次の提案を準備待ちです。バックエンドのHeartbeatが生成します。"
        case "generating":
            return "次の提案を生成しています。完了すると通知されます。"
        case "failed":
            return lastError.map { "提案生成に失敗しました: \(Self.displayError($0))" } ?? "提案生成に失敗しました。"
        default:
            return nil
        }
    }

    var idleStatusMessage: String {
        switch idleReason {
        case "agenda_in_progress":
            return "現在の判断に必要な作業が進行中です。結果が採用されると再評価します。"
        case "insufficient_grounding":
            return "判断に使える根拠が不足しています。新しいLearningが採用されると再評価します。"
        case "insufficient_substance":
            return "品質基準を満たす次の一手がありません。新しい判断材料を待っています。"
        case "no_open_decision":
            return "今すぐ決めるべき論点はありません。事業認識が変わると再評価します。"
        default:
            return "前回から事業認識に変化はありません。調査結果や直接入力が採用されると再評価します。"
        }
    }

    private static func displayError(_ message: String) -> String {
        if message.contains("No online OS Agent host is tagged for Codex App Server") {
            return "MacのCodex実行環境がオフラインです。接続後に再試行してください。"
        }
        return message
    }
}

struct VentureDecisionAgendaSummary: Decodable, Hashable {
    var id: String
    var question: String
    var currentPosition: String
    var primaryUnknown: String
    var costOfDelay: String
    var status: String
}

struct VentureNextActionsPayload: Decodable, Hashable {
    var generatedAt: Date
    var decisionInbox: VentureDecisionInboxPayload
    var missionItems: VentureMissionSummaryPage
    var monitoringAlerts: [VentureMonitoringAlertItem]
    var missionProgress: VentureMissionProgressPayload
}

struct VentureMissionSummaryPage: Decodable, Hashable {
    var items: [VentureMissionSummaryItem]
    var nextCursor: String?
}

struct VentureMissionSummaryItem: Identifiable, Decodable, Hashable {
    var id: String
    var missionKind: String
    var capability: String
    var deliverableKind: String
    var title: String
    var summary: String
    var status: String
    var missionVersion: Int
    var currentAttemptId: String?
    var currentDeliverableId: String?
    var availableActions: [String]
    var sideEffectPolicy: VentureSideEffectPolicy
    var verification: VentureVerificationSummary?
    var updatedAt: Date

    var kindLabel: String {
        switch missionKind {
        case "development": return "Codex実装"
        case "research": return "調査"
        case "message": return "文案"
        case "verification": return "検証"
        case "decision_brief": return "判断材料"
        case "knowledge_change": return "Knowledge"
        default: return capability
        }
    }
}

struct VentureVerificationSummary: Decodable, Hashable {
    var missionId: String
    var status: String
    var verdict: String?
    var summary: String?
    var updatedAt: Date
}

struct VentureDeliverableSpec: Decodable, Hashable {
    var kind: String
    var title: String
    var description: String
    var requiredSections: [String]
    var acceptanceCriteria: [String]
}

struct VentureMissionOrigin: Decodable, Hashable {
    var kind: String
    var proposalId: String?
    var betId: String?
    var requestId: String?
    var requestedByUserId: String?
    var clientRequestId: String?
    var requestHash: String?
    var reason: String?
    var sourceId: String?
}

struct VentureGenericMission: Identifiable, Decodable, Hashable {
    var id: String
    var ventureId: String
    var origin: VentureMissionOrigin
    var sourceProposalId: String?
    var sourceBetId: String?
    var capability: String
    var primaryDeliverableSpec: VentureDeliverableSpec
    var supportingDeliverableSpecs: [VentureDeliverableSpec]
    var sideEffectPolicy: VentureSideEffectPolicy
    var reviewPolicy: String
    var status: String
    var version: Int
    var currentAttemptId: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureMissionInstructionSnapshot: Decodable, Hashable {
    var schemaKey: String
    var schemaVersion: Int
    var contextSnapshotHash: String
    var objective: String
    var referenceIds: [String]
    var payload: ProductOpsMetadataValue

    var approvedInstruction: String? {
        guard let value = payload.unwrappedObjectValue?["approvedInstruction"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct VentureMissionAttempt: Identifiable, Decodable, Hashable {
    var id: String
    var missionId: String
    var attemptNumber: Int
    var revisionOfDeliverableId: String?
    var sourceReviewId: String?
    var executorType: String
    var agentTaskId: String?
    var executorSessionId: String?
    var executorTurnId: String?
    var status: String
    var instructionSnapshot: VentureMissionInstructionSnapshot
    var error: String?
    var createdAt: Date
    var updatedAt: Date
}

struct VentureDeliverableReview: Identifiable, Decodable, Hashable {
    var id: String
    var missionId: String
    var attemptId: String
    var deliverableId: String
    var actorId: String
    var decision: String
    var feedback: String?
    var reviewedAt: Date
}

struct VentureMissionDetail: Decodable, Hashable {
    var mission: VentureGenericMission
    var currentAttempt: VentureMissionAttempt?
    var attempts: [VentureMissionAttempt]
    var deliverables: [VentureDeliverable]
    var reviews: [VentureDeliverableReview]
    var verification: VentureMissionVerification?
    var availableActions: [String]

    var currentDeliverable: VentureDeliverable? {
        guard let attemptId = mission.currentAttemptId else { return nil }
        return deliverables
            .filter {
                $0.attemptId == attemptId && $0.kind == mission.primaryDeliverableSpec.kind
            }
            .max { $0.createdAt < $1.createdAt }
    }

    var approvedInstruction: String? {
        let orderedAttempts = attempts.sorted { $0.attemptNumber > $1.attemptNumber }
        return ([currentAttempt].compactMap { $0 } + orderedAttempts)
            .compactMap(\.instructionSnapshot.approvedInstruction)
            .first
    }

    var displayObjective: String {
        let title = mission.primaryDeliverableSpec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = mission.primaryDeliverableSpec.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let attemptObjective = currentAttempt?.instructionSnapshot.objective
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let approved = approvedInstruction ?? ""

        if !attemptObjective.isEmpty && attemptObjective != approved {
            return attemptObjective
        }
        if !description.isEmpty && description != approved && description != title {
            return description
        }
        return title
    }

    var revisionReviews: [VentureDeliverableReview] {
        reviews
            .filter {
                $0.decision == "revision_requested"
                    && !($0.feedback ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.reviewedAt < $1.reviewedAt }
    }
}

struct VentureMissionVerification: Decodable, Hashable {
    var missionId: String
    var sourceDeliverableId: String
    var status: String
    var result: VentureVerificationMissionResult?
    var deliverables: [VentureDeliverable]

    var reportDeliverable: VentureDeliverable? {
        deliverables.first { $0.kind == "verification_report" }
    }

    var report: VentureVerificationReportDeliverable? {
        guard let reportDeliverable else { return result?.report }
        guard case .verificationReport(let report) = try? reportDeliverable.decodePayload() else { return nil }
        return report
    }

    var reportDecodingError: String? {
        guard let reportDeliverable else { return nil }
        do {
            guard case .verificationReport = try reportDeliverable.decodePayload() else {
                return "検証成果物の種類が一致しません。"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var summary: String {
        reportDeliverable?.displaySummary ?? result?.summary ?? ""
    }
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
    var approvalRisk: String
    var intentKind: String
    var betKind: String?
    var opportunityId: String?
    var hypothesisId: String?
    var approvalEffect: String
    var suggestedSuccessCriteria: [String]
    var suggestedStopConditions: [String]
    var availableDecisions: [String]
    var decisionQuestion: String
    var targetUnknown: String
    var recommendedAction: String
    var decisionRuleSummary: String
    var groundingCount: Int

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
        case "revise_decision_frame":
            return "判断軸を更新"
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
        case "revise_decision_frame":
            return "判断軸"
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
        case "revise_decision_frame":
            return "提案の判断軸を新しいVersionへ更新する"
        default:
            return "次の学習Betとして進める"
        }
    }
}

struct VentureProposalDetail: Decodable, Hashable {
    var proposal: VentureProposalDetailProposal
    var assessment: VentureProposalDetailAssessment
    var recommendation: VentureProposalDetailRecommendation
    var opportunity: VentureProposalDetailOpportunity
    var hypothesis: VentureProposalDetailHypothesis
    var strategy: VentureProposalDetailStrategy
    var decisionFrame: VentureProposalDetailDecisionFrame
    var learnings: [VentureProposalDetailLearning]
}

struct VentureProposalDetailProposal: Decodable, Hashable {
    var proposalId: String
    var title: String
    var summary: String
    var whyNow: String
    var expectedOutcome: String
    var status: String
    var version: Int
    var actionKind: String
    var actionChannel: String
    var approvalRisk: String
    var intentKind: String
    var betKind: String?
    var approvalEffect: String
    var targetUnknowns: [String]
    var unblocksDecision: String
    var evidenceRefs: [String]
    var suggestedSuccessCriteria: [String]
    var suggestedStopConditions: [String]
    var decisionFrameChange: VentureProposalDecisionFrameChange?
    var decisionAgenda: VentureProposalDecisionAgenda
    var groundingRefs: [VentureKnowledgeRef]
    var actionSpec: VentureProposalActionSpec
    var expectedObservation: String
    var decisionRule: VentureProposalDecisionRule
    var contextSpecificReason: String
}

struct VentureProposalDecisionAgenda: Decodable, Hashable {
    var id: String
    var question: String
    var currentPosition: String
    var primaryUnknown: String
    var alternativeExplanation: String?
    var costOfDelay: String
    var status: String
}

struct VentureKnowledgeRef: Decodable, Hashable {
    var kind: String
    var id: String
    var relation: String

    var stableId: String { "\(kind):\(id):\(relation)" }
}

struct VentureProposalActionSpec: Decodable, Hashable {
    var target: String
    var method: String
    var quantity: String
    var timebox: String
    var deliverableKind: String
}

struct VentureProposalDecisionRule: Decodable, Hashable {
    var proceedWhen: String
    var stopWhen: String
    var reconsiderWhen: String
}

struct VentureProposalDecisionFrameChange: Decodable, Hashable {
    var baseDecisionFrameVersionId: String
    var proposedDecisionFrameVersionId: String
    var rationale: String
    var currentLenses: [VentureProposalDecisionLens]
    var proposedLenses: [VentureProposalDecisionLens]
}

struct VentureProposalDecisionLens: Decodable, Hashable, Identifiable {
    var key: String
    var label: String
    var weight: Double
    var direction: String
    var required: Bool
    var description: String

    var id: String { key }
}

struct VentureProposalDetailAssessment: Decodable, Hashable {
    var rank: Int
    var totalScore: Double
    var scores: [String: Double]
    var whyNow: String
    var algorithmKey: String
    var assessedAt: Date
    var businessScore: Double
    var substanceScore: Double
    var substanceScores: VentureProposalSubstanceScores
    var finalScore: Double
}

struct VentureProposalSubstanceScores: Decodable, Hashable {
    var grounding: Double
    var decisionLeverage: Double
    var informationGain: Double
    var specificity: Double
    var novelty: Double
    var executability: Double
    var appliesToUnrelatedVenture: Bool
    var reasons: [String]
}

struct VentureProposalDetailRecommendation: Decodable, Hashable {
    var recommendationSetId: String
    var generatedAt: Date
    var metadata: VentureProposalDetailRecommendationMetadata
}

struct VentureProposalDetailRecommendationMetadata: Decodable, Hashable {
    var draftingPolicyKey: String
    var draftingPromptVersion: String
    var draftingModel: String
    var ratingPolicyKey: String
    var ratingAlgorithmVersion: String
}

struct VentureProposalDetailOpportunity: Decodable, Hashable {
    var id: String
    var problemStatement: String
    var desiredOutcomeStatement: String
    var evidenceSummary: String
    var unknowns: [String]
    var confidence: String
    var status: String
}

struct VentureProposalDetailHypothesis: Decodable, Hashable {
    var id: String
    var statement: String
    var status: String
    var criticality: Int
    var confidence: Int
    var unknowns: [String]
}

struct VentureProposalDetailTargetSegment: Decodable, Hashable {
    var key: String
    var label: String
    var description: String
}

struct VentureProposalDetailStrategy: Decodable, Hashable {
    var id: String
    var mission: String
    var targetSegments: [VentureProposalDetailTargetSegment]
    var desiredOutcomes: [String]
    var focusAreas: [String]
    var exclusions: [String]
}

struct VentureProposalDetailDecisionFrame: Decodable, Hashable {
    var id: String
    var stage: String
    var maxRecommendations: Int
}

struct VentureProposalDetailLearning: Identifiable, Decodable, Hashable {
    var id: String
    var summary: String
    var createdAt: Date
}

struct VentureDevelopmentMissionListPayload: Decodable, Hashable {
    var items: [VentureDevelopmentMissionItem]
}

struct VentureResearchMissionListPayload: Decodable, Hashable {
    var items: [VentureResearchMissionItem]
}

struct VentureResearchClipSourceSnapshot: Decodable, Hashable {
    var type: String
    var externalKey: String
    var author: String?
    var publishedAt: String?
    var metadata: [String: ProductOpsMetadataValue]
}

struct VentureResearchClipCandidatePayload: Decodable, Hashable {
    var deliverableId: String
    var ventureId: String
    var missionId: String
    var extractorVersion: Int
    var items: [VentureResearchClipCandidate]
}

struct VentureResearchClipCandidate: Identifiable, Decodable, Hashable {
    var itemKey: String
    var extractorSchemaKey: String
    var extractorVersion: Int
    var kind: String
    var label: String
    var relation: String?
    var text: String
    var context: String
    var sourceUrl: String?
    var sourceSnapshot: VentureResearchClipSourceSnapshot
    var savedClip: VentureResearchClip?

    var id: String { itemKey }
}

struct VentureResearchClip: Identifiable, Decodable, Hashable {
    var id: String
    var ownerUserId: String
    var ventureId: String
    var deliverableId: String
    var itemKey: String
    var extractorSchemaKey: String
    var extractorVersion: Int
    var itemKind: String
    var relation: String?
    var textSnapshot: String
    var contextSnapshot: String
    var sourceUrl: String?
    var sourceSnapshot: VentureResearchClipSourceSnapshot
    var userNote: String
    var opportunityId: String?
    var hypothesisId: String?
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}

struct VentureResearchClipSaveResult: Decodable, Hashable {
    struct Item: Decodable, Hashable {
        var clip: VentureResearchClip
        var outcome: String
    }

    var deliverableId: String
    var items: [Item]
}

struct VentureResearchClipPage: Decodable, Hashable {
    var items: [VentureResearchClipListItem]
    var nextCursor: String?
}

struct VentureResearchClipListItem: Identifiable, Decodable, Hashable {
    struct SourceState: Decodable, Hashable {
        var sourceMissionId: String
        var sourceMissionStatus: String
        var sourceReviewDecision: String?
        var isCurrentDeliverable: Bool
        var verificationStatus: String?
        var verificationVerdict: String?
    }

    var clip: VentureResearchClip
    var sourceState: SourceState

    var id: String { clip.id }
}

struct VentureResearchClipAssociationOptions: Decodable, Hashable {
    struct Opportunity: Identifiable, Decodable, Hashable {
        var id: String
        var title: String
        var status: String
    }

    struct Hypothesis: Identifiable, Decodable, Hashable {
        var id: String
        var opportunityId: String
        var statement: String
        var status: String
    }

    var opportunities: [Opportunity]
    var hypotheses: [Hypothesis]
}

struct VentureMessageMissionListPayload: Decodable, Hashable {
    var items: [VentureMessageMissionItem]
}

struct VentureVerificationMissionListPayload: Decodable, Hashable {
    var items: [VentureVerificationMissionItem]
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
    var betId: String?
    var sourceProposalId: String?
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
    var betId: String?
    var sourceProposalId: String?
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

struct VentureDeliverable: Identifiable, Decodable, Hashable {
    var id: String
    var missionId: String
    var attemptId: String
    var revisionOfDeliverableId: String?
    var resultId: String?
    var kind: String
    var title: String
    var summary: String
    var payload: ProductOpsMetadataValue
    var createdAt: Date

    var displaySummary: String {
        guard let data = summary.data(using: .utf8),
              let value = try? JSONDecoder().decode(ProductOpsMetadataValue.self, from: data),
              let object = value.unwrappedObjectValue,
              let normalized = object["summary"]?.stringValue,
              !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return summary
        }
        return normalized
    }

    func decodePayload() throws -> VentureDecodedDeliverablePayload {
        switch kind {
        case "decision_brief":
            return .decisionBrief(try VentureDecisionBriefDeliverable(payload: payload))
        case "product_change":
            return .productChange(try VentureProductChangeDeliverable(payload: payload))
        case "research_report":
            return .researchReport(try VentureResearchReportDeliverable(payload: payload))
        case "message":
            return .message(try VentureMessageDeliverable(payload: payload))
        case "verification_report":
            return .verificationReport(try VentureVerificationReportDeliverable(payload: payload))
        case "knowledge_change":
            return .knowledgeChange(try VentureKnowledgeChangeDeliverable(payload: payload))
        case "alert":
            return .alert(try VentureAlertDeliverable(payload: payload))
        default:
            throw VentureDeliverablePayloadDecodingError(
                kind: kind,
                reason: "未対応の成果物種類です。"
            )
        }
    }

    var productChangePayload: VentureProductChangeDeliverable? {
        guard case .productChange(let value) = try? decodePayload() else { return nil }
        return value
    }

    var researchReportPayload: VentureResearchReportDeliverable? {
        guard case .researchReport(let value) = try? decodePayload() else { return nil }
        return value
    }

    var messagePayload: VentureMessageDeliverable? {
        guard case .message(let value) = try? decodePayload() else { return nil }
        return value
    }

    var verificationReportPayload: VentureVerificationReportDeliverable? {
        guard case .verificationReport(let value) = try? decodePayload() else { return nil }
        return value
    }

    var knowledgeChangePayload: VentureKnowledgeChangeDeliverable? {
        guard case .knowledgeChange(let value) = try? decodePayload() else { return nil }
        return value
    }

    var alertPayload: VentureAlertDeliverable? {
        guard case .alert(let value) = try? decodePayload() else { return nil }
        return value
    }
}

enum VentureDecodedDeliverablePayload: Hashable {
    case decisionBrief(VentureDecisionBriefDeliverable)
    case researchReport(VentureResearchReportDeliverable)
    case message(VentureMessageDeliverable)
    case productChange(VentureProductChangeDeliverable)
    case knowledgeChange(VentureKnowledgeChangeDeliverable)
    case verificationReport(VentureVerificationReportDeliverable)
    case alert(VentureAlertDeliverable)
}

struct VentureDeliverablePayloadDecodingError: LocalizedError, Hashable {
    var kind: String
    var reason: String

    var errorDescription: String? {
        "成果物（\(kind)）のデータが不正です。\(reason)"
    }
}

private struct VentureDeliverablePayloadReader {
    var kind: String
    var object: [String: ProductOpsMetadataValue]

    init(kind: String, payload: ProductOpsMetadataValue) throws {
        guard let object = payload.unwrappedObjectValue else {
            throw VentureDeliverablePayloadDecodingError(
                kind: kind,
                reason: "JSONオブジェクトを取得できません。"
            )
        }
        self.kind = kind
        self.object = object
    }

    init(kind: String, object: [String: ProductOpsMetadataValue]) {
        self.kind = kind
        self.object = object
    }

    func requiredString(_ keys: String...) throws -> String {
        let (key, value) = try requiredValue(keys)
        guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw invalidField(key, expectation: "空でない文字列")
        }
        return text
    }

    func requiredStringArray(_ keys: String...) throws -> [String] {
        let (key, value) = try requiredValue(keys)
        guard let values = value.arrayValue else {
            throw invalidField(key, expectation: "文字列配列")
        }
        return try values.enumerated().map { index, item in
            guard let text = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw invalidField("\(key)[\(index)]", expectation: "空でない文字列")
            }
            return text
        }
    }

    func requiredInt(_ keys: String...) throws -> Int {
        let (key, value) = try requiredValue(keys)
        guard let number = value.intValue else {
            throw invalidField(key, expectation: "整数")
        }
        return number
    }

    func requiredDouble(_ keys: String...) throws -> Double {
        let (key, value) = try requiredValue(keys)
        guard case .number(let number) = value else {
            throw invalidField(key, expectation: "数値")
        }
        return number
    }

    func requiredBool(_ keys: String...) throws -> Bool {
        let (key, value) = try requiredValue(keys)
        guard case .bool(let flag) = value else {
            throw invalidField(key, expectation: "真偽値")
        }
        return flag
    }

    func requiredObject(_ keys: String...) throws -> [String: ProductOpsMetadataValue] {
        let (key, value) = try requiredValue(keys)
        guard let object = value.objectValue else {
            throw invalidField(key, expectation: "オブジェクト")
        }
        return object
    }

    func requiredNullableObject(_ keys: String...) throws -> [String: ProductOpsMetadataValue]? {
        let (key, value) = try requiredValue(keys)
        if case .null = value {
            return nil
        }
        guard let object = value.objectValue else {
            throw invalidField(key, expectation: "nullまたはオブジェクト")
        }
        return object
    }

    func requiredNullableStringArray(_ keys: String...) throws -> [String]? {
        let (key, value) = try requiredValue(keys)
        if case .null = value {
            return nil
        }
        guard let values = value.arrayValue else {
            throw invalidField(key, expectation: "nullまたは文字列配列")
        }
        return try values.enumerated().map { index, item in
            guard let text = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw invalidField("\(key)[\(index)]", expectation: "空でない文字列")
            }
            return text
        }
    }

    func requiredObjectArray(_ keys: String...) throws -> [[String: ProductOpsMetadataValue]] {
        let (key, value) = try requiredValue(keys)
        guard let values = value.arrayValue else {
            throw invalidField(key, expectation: "オブジェクト配列")
        }
        return try values.enumerated().map { index, item in
            guard let object = item.objectValue else {
                throw invalidField("\(key)[\(index)]", expectation: "オブジェクト")
            }
            return object
        }
    }

    func requiredNullableString(_ keys: String...) throws -> String? {
        let (key, value) = try requiredValue(keys)
        if case .null = value {
            return nil
        }
        guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw invalidField(key, expectation: "nullまたは空でない文字列")
        }
        return text
    }

    private func requiredValue(_ keys: [String]) throws -> (String, ProductOpsMetadataValue) {
        for key in keys {
            if let value = object[key] {
                return (key, value)
            }
        }
        throw VentureDeliverablePayloadDecodingError(
            kind: kind,
            reason: "必須項目「\(keys.joined(separator: " / "))」がありません。"
        )
    }

    private func invalidField(_ field: String, expectation: String) -> VentureDeliverablePayloadDecodingError {
        VentureDeliverablePayloadDecodingError(
            kind: kind,
            reason: "「\(field)」は\(expectation)である必要があります。"
        )
    }
}

struct VentureDecisionBriefDeliverable: Hashable {
    var decisionQuestion: String
    var recommendation: String
    var reasons: [String]
    var contraryEvidence: [String]
    var risks: [String]
    var unknowns: [String]
    var nextOperations: [String]

    init(payload: ProductOpsMetadataValue) throws {
        let reader = try VentureDeliverablePayloadReader(kind: "decision_brief", payload: payload)
        decisionQuestion = try reader.requiredString("decisionQuestion", "decision_question")
        recommendation = try reader.requiredString("recommendation")
        reasons = try reader.requiredStringArray("reasons")
        contraryEvidence = try reader.requiredStringArray("contraryEvidence", "contrary_evidence")
        risks = try reader.requiredStringArray("risks")
        unknowns = try reader.requiredStringArray("unknowns")
        nextOperations = try reader.requiredStringArray("nextOperations", "next_operations")
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

    init(payload: ProductOpsMetadataValue) throws {
        let reader = try VentureDeliverablePayloadReader(kind: "product_change", payload: payload)
        changedBehavior = try reader.requiredStringArray("changedBehavior", "changed_behavior")
        userVisibleImpact = try reader.requiredString("userVisibleImpact", "user_visible_impact")
        changedRepositories = try reader.requiredStringArray("changedRepositories", "changed_repositories")
        pullRequests = try reader.requiredStringArray("pullRequests", "pull_requests")
        unresolvedIssues = try reader.requiredStringArray("unresolvedIssues", "unresolved_issues")
        checks = try reader.requiredObjectArray("checks").map { object in
            let checkReader = VentureDeliverablePayloadReader(kind: "product_change.checks", object: object)
            let status = try checkReader.requiredString("status")
            guard ["passed", "failed", "not_run"].contains(status) else {
                throw VentureDeliverablePayloadDecodingError(
                    kind: "product_change",
                    reason: "checks.statusが許可値ではありません。"
                )
            }
            return Check(
                name: try checkReader.requiredString("name"),
                status: status,
                detail: try checkReader.requiredString("detail")
            )
        }
    }
}

struct VentureResearchExecutionLog: Hashable {
    var queries: [String]
    var checkedCount: Int
    var selectedCount: Int
    var excludedCount: Int
    var limitations: [String]
}

struct VentureGrokExecution: Hashable {
    struct Requested: Hashable {
        var surface: String
        var mode: String
        var model: String
        var reasoning: String
    }

    struct Applied: Hashable {
        var pageURL: String
        var surface: String
        var modeLabel: String
        var modelLabel: String?
        var reasoningLabel: String?
        var reasoningAppliedBy: String
    }

    var requested: Requested
    var applied: Applied
}

struct VentureResearchReportDeliverable: Decodable, Hashable {
    var artifactMarkdown: String?
    var researchQuestion: String
    var conclusion: String
    var findings: [String]
    var supportingEvidence: [String]
    var contradictingEvidence: [String]
    var sources: [String]
    var unknowns: [String]
    var nextQuestions: [String]
    var executionLog: VentureResearchExecutionLog?
    var grokExecution: VentureGrokExecution?
    var rawResult: ProductOpsMetadataValue?

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
        artifactMarkdown = nil
        self.researchQuestion = researchQuestion
        self.conclusion = conclusion
        self.findings = findings
        self.supportingEvidence = supportingEvidence
        self.contradictingEvidence = contradictingEvidence
        self.sources = sources
        self.unknowns = unknowns
        self.nextQuestions = nextQuestions
        executionLog = nil
        grokExecution = nil
        rawResult = nil
    }

    init(from decoder: Decoder) throws {
        try self.init(payload: ProductOpsMetadataValue(from: decoder))
    }

    init(payload: ProductOpsMetadataValue) throws {
        let rootReader = try VentureDeliverablePayloadReader(kind: "research_report", payload: payload)
        let reportReader: VentureDeliverablePayloadReader
        if let reportObject = rootReader.object["report"]?.unwrappedObjectValue {
            reportReader = VentureDeliverablePayloadReader(kind: "research_report.report", object: reportObject)
        } else {
            reportReader = rootReader
        }

        artifactMarkdown = Self.nonemptyString(
            rootReader.object["artifactMarkdown"]
                ?? rootReader.object["artifact_markdown"]
                ?? reportReader.object["artifactMarkdown"]
                ?? reportReader.object["artifact_markdown"]
        )
        researchQuestion = try reportReader.requiredString("researchQuestion", "research_question")
        conclusion = try reportReader.requiredString("conclusion")
        findings = try reportReader.requiredStringArray("findings")
        supportingEvidence = try reportReader.requiredStringArray("supportingEvidence", "supporting_evidence")
        contradictingEvidence = try reportReader.requiredStringArray("contradictingEvidence", "contradicting_evidence")
        sources = Self.sourceStrings(
            rootReader.object["sources"] ?? reportReader.object["sources"]
        )
        unknowns = try reportReader.requiredStringArray("unknowns")
        nextQuestions = try reportReader.requiredStringArray("nextQuestions", "next_questions")
        executionLog = Self.executionLog(
            rootReader.object["executionLog"]
                ?? rootReader.object["execution_log"]
                ?? reportReader.object["executionLog"]
                ?? reportReader.object["execution_log"]
        )
        grokExecution = Self.grokExecution(
            rootReader.object["grokExecution"]
                ?? rootReader.object["grok_execution"]
                ?? reportReader.object["grokExecution"]
                ?? reportReader.object["grok_execution"]
        )
        rawResult = rootReader.object["rawResult"]
            ?? rootReader.object["raw_result"]
            ?? reportReader.object["rawResult"]
            ?? reportReader.object["raw_result"]
    }

    private static func nonemptyString(_ value: ProductOpsMetadataValue?) -> String? {
        guard let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func sourceStrings(_ value: ProductOpsMetadataValue?) -> [String] {
        guard let values = value?.arrayValue else { return [] }
        return values.compactMap { item in
            if let source = nonemptyString(item) {
                return source
            }
            guard let object = item.unwrappedObjectValue else { return nil }
            return nonemptyString(object["url"])
                ?? nonemptyString(object["sourceUrl"])
                ?? nonemptyString(object["source_url"])
        }
    }

    private static func executionLog(_ value: ProductOpsMetadataValue?) -> VentureResearchExecutionLog? {
        guard let object = value?.unwrappedObjectValue else { return nil }
        return VentureResearchExecutionLog(
            queries: object["queries"]?.stringArrayValue ?? [],
            checkedCount: object["checkedCount"]?.intValue ?? object["checked_count"]?.intValue ?? 0,
            selectedCount: object["selectedCount"]?.intValue ?? object["selected_count"]?.intValue ?? 0,
            excludedCount: object["excludedCount"]?.intValue ?? object["excluded_count"]?.intValue ?? 0,
            limitations: object["limitations"]?.stringArrayValue ?? []
        )
    }

    private static func grokExecution(_ value: ProductOpsMetadataValue?) -> VentureGrokExecution? {
        guard let object = value?.unwrappedObjectValue,
              let requested = object["requested"]?.unwrappedObjectValue,
              let applied = object["applied"]?.unwrappedObjectValue,
              let requestedSurface = nonemptyString(requested["surface"]),
              let requestedMode = nonemptyString(requested["mode"]),
              let requestedModel = nonemptyString(requested["model"]),
              let requestedReasoning = nonemptyString(requested["reasoning"]),
              let pageURL = nonemptyString(applied["pageUrl"] ?? applied["page_url"]),
              let appliedSurface = nonemptyString(applied["surface"]),
              let modeLabel = nonemptyString(applied["modeLabel"] ?? applied["mode_label"]),
              let reasoningAppliedBy = nonemptyString(
                applied["reasoningAppliedBy"] ?? applied["reasoning_applied_by"]
              ) else {
            return nil
        }
        return VentureGrokExecution(
            requested: .init(
                surface: requestedSurface,
                mode: requestedMode,
                model: requestedModel,
                reasoning: requestedReasoning
            ),
            applied: .init(
                pageURL: pageURL,
                surface: appliedSurface,
                modeLabel: modeLabel,
                modelLabel: nonemptyString(applied["modelLabel"] ?? applied["model_label"]),
                reasoningLabel: nonemptyString(applied["reasoningLabel"] ?? applied["reasoning_label"]),
                reasoningAppliedBy: reasoningAppliedBy
            )
        )
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

    init(payload: ProductOpsMetadataValue) throws {
        let reader = try VentureDeliverablePayloadReader(kind: "message", payload: payload)
        channel = try reader.requiredString("channel")
        purpose = try reader.requiredString("purpose")
        subject = try reader.requiredNullableString("subject")
        body = try reader.requiredString("body")
        candidateRecipients = try reader.requiredStringArray("candidateRecipients", "candidate_recipients")
        guard ["x_post", "x_reply", "email", "direct_message"].contains(channel) else {
            throw VentureDeliverablePayloadDecodingError(kind: "message", reason: "channelが許可値ではありません。")
        }
        guard ["question", "outreach", "announcement", "follow_up"].contains(purpose) else {
            throw VentureDeliverablePayloadDecodingError(kind: "message", reason: "purposeが許可値ではありません。")
        }
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

    init(payload: ProductOpsMetadataValue) throws {
        let rootReader = try VentureDeliverablePayloadReader(kind: "verification_report", payload: payload)
        let reader: VentureDeliverablePayloadReader
        if let report = rootReader.object["report"] {
            guard let reportObject = report.unwrappedObjectValue else {
                throw VentureDeliverablePayloadDecodingError(
                    kind: "verification_report",
                    reason: "reportはJSONオブジェクトである必要があります。"
                )
            }
            reader = VentureDeliverablePayloadReader(kind: "verification_report", object: reportObject)
        } else {
            reader = rootReader
        }
        verdict = try reader.requiredString("verdict")
        guard ["passed", "failed", "review_required"].contains(verdict) else {
            throw VentureDeliverablePayloadDecodingError(
                kind: "verification_report",
                reason: "verdictが許可値ではありません。"
            )
        }
        checkedCriteria = try reader.requiredObjectArray("checkedCriteria", "checked_criteria").map { object in
            let itemReader = VentureDeliverablePayloadReader(kind: "verification_report.checkedCriteria", object: object)
            let status = try itemReader.requiredString("status")
            guard ["passed", "failed", "not_run"].contains(status) else {
                throw VentureDeliverablePayloadDecodingError(
                    kind: "verification_report",
                    reason: "checkedCriteria.statusが許可値ではありません。"
                )
            }
            return CheckedCriterion(
                criterion: try itemReader.requiredString("criterion"),
                status: status,
                detail: try itemReader.requiredString("detail")
            )
        }
        risks = try reader.requiredStringArray("risks")
        requiredFollowUps = try reader.requiredStringArray("requiredFollowUps", "required_follow_ups")
    }
}

struct VentureKnowledgeReference: Decodable, Hashable {
    var kind: String
    var id: String
    var relation: String
}

struct VenturePolicyTargetSegment: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var description: String

    var id: String { key }
}

struct VenturePolicyDecisionLens: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var weight: Double
    var direction: String
    var required: Bool
    var description: String

    var id: String { key }
}

struct VenturePolicyHardGate: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var description: String
    var parameters: [String: ProductOpsMetadataValue]

    var id: String { key }
}

struct VenturePolicyObjectiveDefinition: Decodable, Hashable, Identifiable {
    var key: String
    var label: String
    var description: String

    var id: String { key }
}

struct VenturePolicyDecisionLensDefinition: Decodable, Hashable, Identifiable {
    var key: String
    var label: String
    var direction: String
    var description: String

    var id: String { key }
}

struct VenturePolicyHardGateDefinition: Decodable, Hashable, Identifiable {
    var key: String
    var label: String
    var description: String

    var id: String { key }
}

struct VenturePolicyStrategyDefinition: Codable, Hashable {
    var mission: String
    var targetSegments: [VenturePolicyTargetSegment]
    var desiredOutcomes: [String]
    var commercialHypotheses: [String]
    var focusAreas: [String]
    var exclusions: [String]
    var researchGuardrails: [String]
    var deliveryGuardrails: [String]
}

struct VenturePolicyDecisionFrameDefinition: Codable, Hashable {
    var stage: String
    var objectiveIds: [String]
    var lenses: [VenturePolicyDecisionLens]
    var hardGates: [VenturePolicyHardGate]
    var maxRecommendations: Int
}

struct VentureKnowledgeChangeDeliverable: Decodable, Hashable {
    var schemaVersion: Int
    var kind: String
    var basePolicyTextVersionId: String
    var baseStrategyVersionId: String
    var baseDecisionFrameVersionId: String
    var nextPolicyText: String?
    var nextStrategy: VenturePolicyStrategyDefinition?
    var nextDecisionFrame: VenturePolicyDecisionFrameDefinition?
    var rationale: String
    var expectedImpact: String
    var contraryEvidence: [String]
    var sourceRefs: [VentureKnowledgeReference]
    var risk: String
    var consultationSummary: String?

    init(payload: ProductOpsMetadataValue) throws {
        let reader = try VentureDeliverablePayloadReader(kind: "knowledge_change", payload: payload)
        schemaVersion = try reader.requiredInt("schemaVersion")
        kind = try reader.requiredString("kind")
        basePolicyTextVersionId = try reader.requiredString("basePolicyTextVersionId")
        baseStrategyVersionId = try reader.requiredString("baseStrategyVersionId")
        baseDecisionFrameVersionId = try reader.requiredString("baseDecisionFrameVersionId")
        nextPolicyText = try reader.requiredNullableString("nextPolicyText")
        nextStrategy = try reader.requiredNullableObject("nextStrategy").map(Self.strategyDefinition)
        nextDecisionFrame = try reader.requiredNullableObject("nextDecisionFrame").map(Self.decisionFrameDefinition)
        rationale = try reader.requiredString("rationale")
        expectedImpact = try reader.requiredString("expectedImpact")
        contraryEvidence = try reader.requiredStringArray("contraryEvidence")
        sourceRefs = try reader.requiredObjectArray("sourceRefs").map(Self.knowledgeReference)
        risk = try reader.requiredString("risk")
        consultationSummary = try reader.requiredNullableString("consultationSummary")

        guard schemaVersion == 3 else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "schemaVersionは3である必要があります。")
        }
        guard kind == "policy_revision" else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "kindはpolicy_revisionである必要があります。")
        }
        guard nextPolicyText != nil || nextStrategy != nil || nextDecisionFrame != nil else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "方針変更内容がありません。")
        }
        guard ["medium", "high", "critical"].contains(risk) else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "riskが許可値ではありません。")
        }
    }

    private static func strategyDefinition(_ object: [String: ProductOpsMetadataValue]) throws -> VenturePolicyStrategyDefinition {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.nextStrategy", object: object)
        return VenturePolicyStrategyDefinition(
            mission: try reader.requiredString("mission"),
            targetSegments: try reader.requiredObjectArray("targetSegments").map(targetSegment),
            desiredOutcomes: try reader.requiredStringArray("desiredOutcomes"),
            commercialHypotheses: try reader.requiredStringArray("commercialHypotheses"),
            focusAreas: try reader.requiredStringArray("focusAreas"),
            exclusions: try reader.requiredStringArray("exclusions"),
            researchGuardrails: try reader.requiredStringArray("researchGuardrails"),
            deliveryGuardrails: try reader.requiredStringArray("deliveryGuardrails")
        )
    }

    private static func decisionFrameDefinition(_ object: [String: ProductOpsMetadataValue]) throws -> VenturePolicyDecisionFrameDefinition {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.nextDecisionFrame", object: object)
        return VenturePolicyDecisionFrameDefinition(
            stage: try reader.requiredString("stage"),
            objectiveIds: try reader.requiredStringArray("objectiveIds"),
            lenses: try reader.requiredObjectArray("lenses").map(decisionLens),
            hardGates: try reader.requiredObjectArray("hardGates").map(hardGate),
            maxRecommendations: try reader.requiredInt("maxRecommendations")
        )
    }

    private static func targetSegment(_ object: [String: ProductOpsMetadataValue]) throws -> VenturePolicyTargetSegment {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.targetSegment", object: object)
        return VenturePolicyTargetSegment(
            key: try reader.requiredString("key"),
            label: try reader.requiredString("label"),
            description: try reader.requiredString("description")
        )
    }

    private static func decisionLens(_ object: [String: ProductOpsMetadataValue]) throws -> VenturePolicyDecisionLens {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.decisionLens", object: object)
        return VenturePolicyDecisionLens(
            key: try reader.requiredString("key"),
            label: try reader.requiredString("label"),
            weight: try reader.requiredDouble("weight"),
            direction: try reader.requiredString("direction"),
            required: try reader.requiredBool("required"),
            description: try reader.requiredString("description")
        )
    }

    private static func hardGate(_ object: [String: ProductOpsMetadataValue]) throws -> VenturePolicyHardGate {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.hardGate", object: object)
        return VenturePolicyHardGate(
            key: try reader.requiredString("key"),
            label: try reader.requiredString("label"),
            description: try reader.requiredString("description"),
            parameters: try reader.requiredObject("parameters")
        )
    }

    private static func knowledgeReference(_ object: [String: ProductOpsMetadataValue]) throws -> VentureKnowledgeReference {
        let reader = VentureDeliverablePayloadReader(kind: "knowledge_change.sourceRef", object: object)
        let reference = VentureKnowledgeReference(
            kind: try reader.requiredString("kind"),
            id: try reader.requiredString("id"),
            relation: try reader.requiredString("relation")
        )
        guard ["opportunity", "hypothesis", "learning", "mission_outcome", "deliverable_review", "decision_feedback"].contains(reference.kind) else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "sourceRefs.kindが許可値ではありません。")
        }
        guard ["supports", "contradicts", "context"].contains(reference.relation) else {
            throw VentureDeliverablePayloadDecodingError(kind: "knowledge_change", reason: "sourceRefs.relationが許可値ではありません。")
        }
        return reference
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

    init(payload: ProductOpsMetadataValue) throws {
        let reader = try VentureDeliverablePayloadReader(kind: "alert", payload: payload)
        severity = try reader.requiredString("severity")
        detectedIssue = try reader.requiredString("detectedIssue", "detected_issue")
        recommendedAction = try reader.requiredString("recommendedAction", "recommended_action")
        entityRefs = try reader.requiredStringArray("entityRefs", "entity_refs")
        guard ["info", "warning", "critical"].contains(severity) else {
            throw VentureDeliverablePayloadDecodingError(kind: "alert", reason: "severityが許可値ではありません。")
        }
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

struct VenturePolicy: Identifiable, Decodable, Hashable {
    var ventureId: String
    var policyText: String
    var policyTextVersionId: String
    var policyTextVersion: Int
    var policyTextUpdatedAt: Date
    var strategyVersionId: String
    var decisionFrameVersionId: String
    var mission: String
    var targetSegments: [VenturePolicyTargetSegment]
    var desiredOutcomes: [String]
    var commercialHypotheses: [String]
    var focusAreas: [String]
    var exclusions: [String]
    var researchGuardrails: [String]
    var deliveryGuardrails: [String]
    var systemSafetyConstraints: [String]
    var stage: String
    var objectives: [String]
    var lenses: [VenturePolicyDecisionLens]
    var hardGates: [VenturePolicyHardGate]
    var maxRecommendations: Int
    var objectiveDefinitions: [VenturePolicyObjectiveDefinition]
    var decisionLensDefinitions: [VenturePolicyDecisionLensDefinition]
    var hardGateDefinitions: [VenturePolicyHardGateDefinition]
    var currentView: String?
    var synthesisVersionId: String?
    var pendingPolicyChangeCount: Int
    var policyChangeStatusCounts: VenturePolicyChangeStatusCounts
    var generatedAt: Date

    var id: String { ventureId }
}

struct VenturePolicyChangeStatusCounts: Decodable, Hashable {
    var awaitingReview: Int
    var awaitingExternalInput: Int
    var pendingApply: Int
    var applyFailed: Int
}

struct VenturePolicyStrategySettingsRequest: Codable, Hashable {
    var mission: String
    var targetSegments: [VenturePolicyTargetSegment]
    var desiredOutcomes: [String]
    var commercialHypotheses: [String]
    var focusAreas: [String]
    var exclusions: [String]
    var researchGuardrails: [String]
    var deliveryGuardrails: [String]
}

struct VenturePolicyDecisionFrameSettingsRequest: Codable, Hashable {
    var stage: String
    var objectiveIds: [String]
    var lenses: [VenturePolicyDecisionLens]
    var hardGates: [VenturePolicyHardGate]
    var maxRecommendations: Int
}

struct VenturePolicyRevisionContext: Decodable, Hashable {
    var contextHash: String
}

struct VenturePolicyRevisionDraft: Encodable, Hashable {
    var clientRequestId: String
    var contextHash: String
    var basePolicyTextVersionId: String
    var baseStrategyVersionId: String
    var baseDecisionFrameVersionId: String
    var nextPolicyText: String?
    var nextStrategy: VenturePolicyStrategySettingsRequest?
    var nextDecisionFrame: VenturePolicyDecisionFrameSettingsRequest?
    var rationale: String
    var expectedImpact: String
    var contraryEvidence: [String]
    var sourceRefs: [VenturePolicyRevisionSourceReference]
    var risk: String
    var consultationSummary: String
    var executorSessionId: String?
    var executorTurnId: String?
}

struct VenturePolicyRevisionSourceReference: Codable, Hashable {
    var kind: String
    var id: String
    var relation: String
}

struct VenturePolicyDiffLine: Decodable, Hashable, Identifiable {
    var kind: String
    var oldLineNumber: Int?
    var newLineNumber: Int?
    var text: String

    var id: String { "\(kind)-\(oldLineNumber ?? 0)-\(newLineNumber ?? 0)-\(text)" }
}

struct VenturePolicyTextDiff: Decodable, Hashable {
    var before: String
    var after: String
    var hunks: [VenturePolicyDiffHunk]
}

struct VenturePolicyDiffHunk: Decodable, Hashable, Identifiable {
    var oldStart: Int
    var oldLineCount: Int
    var newStart: Int
    var newLineCount: Int
    var lines: [VenturePolicyDiffLine]

    var id: String { "\(oldStart)-\(oldLineCount)-\(newStart)-\(newLineCount)" }
}

struct VenturePolicyStructuredChange: Decodable, Hashable, Identifiable {
    var path: String
    var label: String
    var changeType: String
    var before: [String]
    var after: [String]
    var added: [String]
    var removed: [String]
    var reordered: Bool

    var id: String { path }
}

struct VenturePolicyRevisionImpactPreview: Decodable, Hashable {
    var staleProposalCount: Int
    var supersededRecommendationSetCount: Int
    var supersededSynthesisCount: Int
    var supersededAgendaItemCount: Int
}

struct VenturePolicyRevisionVersions: Decodable, Hashable {
    var policyTextVersionId: String
    var strategyVersionId: String
    var decisionFrameVersionId: String
}

struct VenturePolicyRevisionDetail: Decodable, Hashable, Identifiable {
    var missionId: String
    var missionVersion: Int
    var currentAttempt: VentureMissionAttempt?
    var reviews: [VentureDeliverableReview]
    var deliverableId: String
    var revisionHash: String
    var reviewDeepLink: String
    var origin: String
    var status: String
    var reviewStatus: String
    var applicationStatus: String
    var applicationError: String?
    var baseVersions: VenturePolicyRevisionVersions
    var currentVersions: VenturePolicyRevisionVersions
    var isStale: Bool
    var staleReasons: [String]
    var summary: String
    var rationale: String
    var expectedImpact: String
    var contraryEvidence: [String]
    var sourceRefs: [VenturePolicyRevisionSourceReference]
    var risk: String
    var consultationSummary: String?
    var policyTextDiff: VenturePolicyTextDiff
    var structuredChanges: [VenturePolicyStructuredChange]
    var impactPreview: VenturePolicyRevisionImpactPreview
    var canAdopt: Bool
    var canRequestRevision: Bool
    var canReject: Bool

    var id: String { missionId }
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

enum ProductOpsMetadataValue: Codable, Hashable {
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

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: ProductOpsDynamicCodingKey.self)
            for (key, item) in value {
                try container.encode(item, forKey: ProductOpsDynamicCodingKey(stringValue: key)!)
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            try container.encode(contentsOf: value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
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

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(exactly: value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var stringArrayValue: [String]? {
        guard let arrayValue else {
            return nil
        }
        return arrayValue.compactMap(\.stringValue)
    }

    var unwrappedObjectValue: [String: ProductOpsMetadataValue]? {
        if let objectValue {
            return objectValue
        }
        guard case .string(let value) = self,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ProductOpsMetadataValue.self, from: data) else {
            return nil
        }
        return decoded.objectValue
    }

    var prettyPrintedJSON: String {
        if case .string(let value) = self {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
               let data = trimmed.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ProductOpsMetadataValue.self, from: data) {
                return decoded.prettyPrintedJSON
            }
            return value
        }
        guard JSONSerialization.isValidJSONObject(foundationValue),
              let data = try? JSONSerialization.data(
                withJSONObject: foundationValue,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: foundationValue)
        }
        return text
    }

    private var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.foundationValue)
        case .array(let value): return value.map(\.foundationValue)
        case .null: return NSNull()
        }
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
