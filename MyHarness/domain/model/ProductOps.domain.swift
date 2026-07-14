import Foundation

enum ProductOpsProject {
    static let landlordSaaS = "landlord_saas"
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
    var version: Int
    var createdAt: Date
    var updatedAt: Date
}

struct ProjectPolicyEditableFields: Encodable, Hashable {
    var targetPersona: String
    var productGoal: String
    var valueProposition: String
    var pricingHypothesis: String
    var evaluationCriteria: [String]
    var constraints: [String]
    var nonGoals: [String]

    init(
        targetPersona: String,
        productGoal: String,
        valueProposition: String,
        pricingHypothesis: String,
        evaluationCriteria: [String],
        constraints: [String],
        nonGoals: [String]
    ) {
        self.targetPersona = targetPersona
        self.productGoal = productGoal
        self.valueProposition = valueProposition
        self.pricingHypothesis = pricingHypothesis
        self.evaluationCriteria = evaluationCriteria
        self.constraints = constraints
        self.nonGoals = nonGoals
    }

    init(policy: ProjectPolicy) {
        self.init(
            targetPersona: policy.targetPersona,
            productGoal: policy.productGoal,
            valueProposition: policy.valueProposition,
            pricingHypothesis: policy.pricingHypothesis,
            evaluationCriteria: policy.evaluationCriteria,
            constraints: policy.constraints,
            nonGoals: policy.nonGoals
        )
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
