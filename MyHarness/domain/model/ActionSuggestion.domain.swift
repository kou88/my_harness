import Foundation
import SwiftUI

enum ActionSuggestionDecision: String, Codable, CaseIterable, Hashable {
    case approved
    case rejected
    case later

    var label: String {
        switch self {
        case .approved:
            return "承認"
        case .rejected:
            return "却下"
        case .later:
            return "後で"
        }
    }

    var systemImage: String {
        switch self {
        case .approved:
            return "checkmark.circle"
        case .rejected:
            return "xmark.circle"
        case .later:
            return "clock"
        }
    }
}

enum ActionSuggestionRiskLevel: String, Codable, Hashable {
    case low
    case medium
    case high
    case critical
    case unknown

    var label: String {
        switch self {
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        case .critical:
            return "危険"
        case .unknown:
            return "不明"
        }
    }

    var tint: Color {
        switch self {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high, .critical:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

struct ActionInboxSummary: Decodable, Hashable {
    var totalCount: Int?
    var pendingCount: Int?
    var highRiskCount: Int?
    var approvalRequiredCount: Int?
    var resultReviewCount: Int?
    var executingCount: Int?
    var problemCount: Int?
    var completedCount: Int?
    var updatedAt: Date?
}

struct ActionInboxPayload: Decodable, Hashable {
    var summary: ActionInboxSummary?
    var items: [ActionInboxItem]
}

struct ActionInboxItem: Identifiable, Decodable, Hashable {
    var id: String
    var title: String?
    var summary: String?
    var status: String?
    var riskLevel: ActionSuggestionRiskLevel?
    var actionType: String?
    var sourceType: String?
    var version: Int?
    var expectedVersion: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var dueAt: Date?
    var hostId: String?
    var executionId: String?
    var needId: String?
    var codexResultId: String?
    var requiresAppConfirmation: Bool?

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return id
    }

    var displaySummary: String {
        if let summary, !summary.isEmpty, summary != displayTitle {
            return summary
        }
        return "詳細を開いて確認してください。"
    }

    var displayRiskLevel: ActionSuggestionRiskLevel {
        riskLevel ?? .unknown
    }

    var isOpenForDecision: Bool {
        guard let status else { return true }
        return ["pending", "recommended", "later", "open", "suggested", "awaiting_review"].contains(status)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case suggestionId
        case title
        case summary
        case status
        case riskLevel
        case actionType
        case sourceType
        case expectedVersion
        case version
        case createdAt
        case updatedAt
        case dueAt
        case hostId
        case executionId
        case needId
        case codexResultId
        case requiresAppConfirmation
        case requiresConfirmation
    }

    init(
        id: String,
        title: String?,
        summary: String?,
        status: String?,
        riskLevel: ActionSuggestionRiskLevel?,
        actionType: String?,
        sourceType: String?,
        version: Int?,
        expectedVersion: Int?,
        createdAt: Date?,
        updatedAt: Date?,
        dueAt: Date?,
        hostId: String?,
        executionId: String?,
        needId: String?,
        codexResultId: String?,
        requiresAppConfirmation: Bool?
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.riskLevel = riskLevel
        self.actionType = actionType
        self.sourceType = sourceType
        self.version = version
        self.expectedVersion = expectedVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
        self.hostId = hostId
        self.executionId = executionId
        self.needId = needId
        self.codexResultId = codexResultId
        self.requiresAppConfirmation = requiresAppConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .suggestionId)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "ActionInboxItem.id is required")
            )
        }

        id = decodedId
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        riskLevel = try container.decodeIfPresent(ActionSuggestionRiskLevel.self, forKey: .riskLevel)
        actionType = try container.decodeIfPresent(String.self, forKey: .actionType)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        expectedVersion = try container.decodeIfPresent(Int.self, forKey: .expectedVersion) ?? version
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId)
        executionId = try container.decodeIfPresent(String.self, forKey: .executionId)
        needId = try container.decodeIfPresent(String.self, forKey: .needId)
        codexResultId = try container.decodeIfPresent(String.self, forKey: .codexResultId)
        requiresAppConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresAppConfirmation)
            ?? container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation)
    }
}

struct ActionSuggestion: Identifiable, Decodable, Hashable {
    var id: String
    var title: String?
    var summary: String?
    var body: String?
    var status: String?
    var riskLevel: ActionSuggestionRiskLevel?
    var actionType: String?
    var sourceType: String?
    var sourceURL: URL?
    var version: Int
    var expectedVersion: Int
    var createdAt: Date?
    var updatedAt: Date?
    var dueAt: Date?
    var hostId: String?
    var executionId: String?
    var needId: String?
    var codexResultId: String?
    var requiresAppConfirmation: Bool?
    var sourceItems: [ActionSuggestionEvidenceItem]
    var needEvidence: [ActionSuggestionEvidenceItem]
    var researchResults: [ActionSuggestionResearchResult]

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return id
    }

    var detailText: String {
        if let body, !body.isEmpty {
            return body
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return "詳細本文はまだありません。"
    }

    var displayRiskLevel: ActionSuggestionRiskLevel {
        riskLevel ?? .unknown
    }

    var shouldConfirmApprovalInApp: Bool {
        if requiresAppConfirmation == true {
            return true
        }
        if riskLevel == .high || riskLevel == .critical {
            return true
        }

        let joined = [actionType, sourceType]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return [
            "external",
            "send",
            "deploy",
            "production",
            "prod",
            "pull_request",
            "pr"
        ].contains { joined.contains($0) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case suggestionId
        case title
        case summary
        case body
        case detail
        case description
        case status
        case riskLevel
        case actionType
        case sourceType
        case sourceURL
        case sourceUrl
        case expectedVersion
        case version
        case createdAt
        case updatedAt
        case dueAt
        case hostId
        case executionId
        case needId
        case codexResultId
        case requiresAppConfirmation
        case requiresConfirmation
        case executions
        case evidence
        case sourceItems
        case needEvidence
        case researchResults
    }

    init(
        id: String,
        title: String?,
        summary: String?,
        body: String?,
        status: String?,
        riskLevel: ActionSuggestionRiskLevel?,
        actionType: String?,
        sourceType: String?,
        sourceURL: URL?,
        version: Int,
        expectedVersion: Int,
        createdAt: Date?,
        updatedAt: Date?,
        dueAt: Date?,
        hostId: String?,
        executionId: String?,
        needId: String?,
        codexResultId: String?,
        requiresAppConfirmation: Bool?,
        sourceItems: [ActionSuggestionEvidenceItem],
        needEvidence: [ActionSuggestionEvidenceItem],
        researchResults: [ActionSuggestionResearchResult]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.status = status
        self.riskLevel = riskLevel
        self.actionType = actionType
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.version = version
        self.expectedVersion = expectedVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
        self.hostId = hostId
        self.executionId = executionId
        self.needId = needId
        self.codexResultId = codexResultId
        self.requiresAppConfirmation = requiresAppConfirmation
        self.sourceItems = sourceItems
        self.needEvidence = needEvidence
        self.researchResults = researchResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .suggestionId)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "ActionSuggestion.id is required")
            )
        }

        guard
            let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version)
                ?? container.decodeIfPresent(Int.self, forKey: .expectedVersion)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.version,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ActionSuggestion.version is required for decisions"
                )
            )
        }

        id = decodedId
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        riskLevel = try container.decodeIfPresent(ActionSuggestionRiskLevel.self, forKey: .riskLevel)
        actionType = try container.decodeIfPresent(String.self, forKey: .actionType)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(URL.self, forKey: .sourceUrl)
        version = decodedVersion
        expectedVersion = decodedVersion
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        hostId = try container.decodeIfPresent(String.self, forKey: .hostId)
        let executions = try container.decodeIfPresent([ActionSuggestionExecution].self, forKey: .executions) ?? []
        executionId = try container.decodeIfPresent(String.self, forKey: .executionId)
            ?? executions.first?.id
        needId = try container.decodeIfPresent(String.self, forKey: .needId)
        codexResultId = try container.decodeIfPresent(String.self, forKey: .codexResultId)
        requiresAppConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresAppConfirmation)
            ?? container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation)
        let apiEvidence = try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .evidence) ?? []
        sourceItems = try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .sourceItems) ?? []
        needEvidence = Self.deduplicatedEvidence(
            (try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .needEvidence) ?? []) + apiEvidence
        )
        let executionResults = executions.flatMap(\.results)
        researchResults = (try container.decodeIfPresent([ActionSuggestionResearchResult].self, forKey: .researchResults) ?? []) + executionResults
    }

    private static func deduplicatedEvidence(_ items: [ActionSuggestionEvidenceItem]) -> [ActionSuggestionEvidenceItem] {
        var seen = Set<String>()
        return items.filter { item in
            seen.insert(item.id).inserted
        }
    }
}

private struct ActionSuggestionExecution: Decodable, Hashable {
    var id: String
    var results: [ActionSuggestionResearchResult]
}

private struct ActionSuggestionSourceItem: Decodable, Hashable {
    var id: String?
    var sourceType: String?
    var url: URL?
    var rawText: String?
    var sourceCreatedAt: Date?
}

struct ActionSuggestionEvidenceItem: Identifiable, Decodable, Hashable {
    var id: String
    var title: String?
    var summary: String?
    var text: String?
    var sourceType: String?
    var sourceURL: URL?
    var author: String?
    var capturedAt: Date?

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        if let text, !text.isEmpty {
            return String(text.prefix(80))
        }
        return id
    }

    var displayBody: String {
        if let text, !text.isEmpty {
            return text
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return "本文はありません。"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId
        case itemId
        case title
        case summary
        case text
        case body
        case content
        case rawText
        case externalKey
        case sourceType
        case sourceURL
        case sourceUrl
        case url
        case author
        case capturedAt
        case note
        case relation
        case relevance
        case sourceItem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedSourceItem = try container.decodeIfPresent(ActionSuggestionSourceItem.self, forKey: .sourceItem)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        let textValue = try container.decodeIfPresent(String.self, forKey: .text)
        let bodyValue = try container.decodeIfPresent(String.self, forKey: .body)
        let contentValue = try container.decodeIfPresent(String.self, forKey: .content)
        let rawTextValue = try container.decodeIfPresent(String.self, forKey: .rawText)
        let noteValue = try container.decodeIfPresent(String.self, forKey: .note)
        text = textValue ?? bodyValue ?? contentValue ?? rawTextValue ?? noteValue ?? nestedSourceItem?.rawText
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? nestedSourceItem?.sourceType
        let sourceURLValue = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        let sourceUrlValue = try container.decodeIfPresent(URL.self, forKey: .sourceUrl)
        let urlValue = try container.decodeIfPresent(URL.self, forKey: .url)
        sourceURL = sourceURLValue ?? sourceUrlValue ?? urlValue ?? nestedSourceItem?.url
        author = try container.decodeIfPresent(String.self, forKey: .author)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
            ?? nestedSourceItem?.sourceCreatedAt
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
        let decodedSourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        let decodedItemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        let decodedExternalKey = try container.decodeIfPresent(String.self, forKey: .externalKey)
        id = decodedId
            ?? decodedSourceId
            ?? decodedItemId
            ?? decodedExternalKey
            ?? nestedSourceItem?.id
            ?? sourceURL?.absoluteString
            ?? title
            ?? text
            ?? decoder.codingPath.map(\.stringValue).joined(separator: ".")
    }
}

struct ActionSuggestionResearchResult: Identifiable, Decodable, Hashable {
    var id: String
    var title: String?
    var summary: String?
    var body: String?
    var sourceItems: [ActionSuggestionEvidenceItem]
    var needEvidence: [ActionSuggestionEvidenceItem]

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return id
    }

    var displayBody: String {
        if let body, !body.isEmpty {
            return body
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        return "調査結果本文はありません。"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case resultId
        case title
        case summary
        case body
        case text
        case sourceItems
        case needEvidence
        case resultType
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        let resultPayload = try container.decodeIfPresent(ActionSuggestionResearchReportPayload.self, forKey: .result)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? resultPayload?.summary
        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? resultPayload?.summary
        sourceItems = (try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .sourceItems) ?? []) + (resultPayload?.sources ?? [])
        needEvidence = try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .needEvidence) ?? []
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .resultId)
            ?? title
            ?? summary
            ?? decoder.codingPath.map(\.stringValue).joined(separator: ".")
    }
}

private struct ActionSuggestionResearchReportPayload: Decodable, Hashable {
    var summary: String?
    var sources: [ActionSuggestionEvidenceItem]

    enum CodingKeys: String, CodingKey {
        case summary
        case sources
        case report
    }

    private struct Report: Decodable, Hashable {
        var summary: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let report = try container.decodeIfPresent(Report.self, forKey: .report)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? report?.summary
        sources = try container.decodeIfPresent([ActionSuggestionEvidenceItem].self, forKey: .sources) ?? []
    }
}
