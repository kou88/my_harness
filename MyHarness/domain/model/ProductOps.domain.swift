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
    var refreshRequired: Bool
    var items: [VentureDecisionInboxItem]
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
    var intentKind: String
    var opportunityId: String?
    var hypothesisId: String?
    var suggestedSuccessCriteria: [String]
    var suggestedStopConditions: [String]
    var availableDecisions: [String]

    var id: String { proposalId }
}

struct VentureDevelopmentMissionListPayload: Decodable, Hashable {
    var items: [VentureDevelopmentMissionItem]
}

struct VentureDevelopmentMissionItem: Identifiable, Decodable, Hashable {
    var mission: VentureDevelopmentMission
    var result: VentureDevelopmentMissionResult?

    var id: String { mission.id }
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
