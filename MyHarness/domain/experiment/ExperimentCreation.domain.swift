import Foundation

enum ExperimentPriority: String, Codable, CaseIterable {
    case low, normal, high, urgent
    var title: String {
        switch self { case .low: "低"; case .normal: "通常"; case .high: "高"; case .urgent: "最優先" }
    }
}

private enum ExperimentInput {
    static func text(_ value: String, label: String, required: Bool, limit: Int) -> String {
        if required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "\(label)を入力してください。" }
        if value.utf16.count > limit { return "\(label)は\(limit)文字以内で入力してください。" }
        return ""
    }
    static func parent(_ id: String) -> String {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { return "追加先を選んでください。" }
        return ""
    }
    static func validate(_ message: String) throws {
        if !message.isEmpty { throw NSError(domain: "Experiments", code: 3, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func first(_ messages: [String]) -> String { messages.first(where: { !$0.isEmpty }) ?? "" }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }
}

struct ExperimentHypothesisDraft {
    var themeID: String
    var statement: String
    var background: String
    var question: String
    var successCriteria: String
    var falsificationCriteria: String
    var priority: ExperimentPriority
    var status: ExperimentStatus

    static func empty(themeID: String) -> Self {
        Self(themeID: themeID, statement: "", background: "", question: "", successCriteria: "", falsificationCriteria: "", priority: .normal, status: .unverified)
    }
    var validationMessage: String {
        ExperimentInput.first([
            ExperimentInput.parent(themeID),
            ExperimentInput.text(statement.trimmingCharacters(in: .whitespacesAndNewlines), label: "仮説", required: true, limit: 500),
            ExperimentInput.text(question, label: "確認したいこと", required: true, limit: 100_000),
            ExperimentInput.text(successCriteria, label: "成功基準", required: true, limit: 100_000),
            ExperimentInput.text(falsificationCriteria, label: "反証基準", required: true, limit: 100_000),
            ExperimentInput.text(background, label: "根拠・背景", required: false, limit: 100_000),
            [.unverified, .testing].contains(status) ? "" : "仮説のステータスが不正です。",
        ])
    }
}

struct ExperimentHypothesisCreateRequest: Encodable {
    let operationId: String
    let themeId: String
    let statement: String
    let background: String
    let question: String
    let successCriteria: String
    let falsificationCriteria: String
    let priority: ExperimentPriority
    let status: ExperimentStatus

    init(operationID: UUID, draft: ExperimentHypothesisDraft) throws {
        try ExperimentInput.validate(draft.validationMessage)
        operationId = operationID.uuidString.lowercased(); themeId = draft.themeID
        statement = draft.statement.trimmingCharacters(in: .whitespacesAndNewlines)
        background = draft.background; question = draft.question
        successCriteria = draft.successCriteria; falsificationCriteria = draft.falsificationCriteria
        priority = draft.priority; status = draft.status
    }
}

struct ExperimentTaskDraft {
    var hypothesisID: String
    var title: String
    var method: String
    var expectedOutcome: String
    var status: ExperimentStatus
    var dueAt: Date?
    var priority: ExperimentPriority
    var assigneeID: String

    static func empty(hypothesisID: String, assigneeID: String) -> Self {
        Self(hypothesisID: hypothesisID, title: "", method: "", expectedOutcome: "", status: .pending, dueAt: nil, priority: .normal, assigneeID: assigneeID)
    }
    var validationMessage: String {
        ExperimentInput.first([
            ExperimentInput.parent(hypothesisID),
            ExperimentInput.text(title.trimmingCharacters(in: .whitespacesAndNewlines), label: "タイトル", required: true, limit: 500),
            ExperimentInput.text(method, label: "検証方法", required: true, limit: 100_000),
            ExperimentInput.text(expectedOutcome, label: "成果物・測定項目", required: true, limit: 100_000),
            ExperimentInput.text(assigneeID, label: "実施者", required: true, limit: 200),
            [.pending, .inProgress, .paused].contains(status) ? "" : "TODOのステータスが不正です。",
        ])
    }
}

struct ExperimentTaskCreateRequest: Encodable {
    let operationId: String
    let hypothesisId: String
    let title: String
    let method: String
    let expectedOutcome: String
    let status: ExperimentStatus
    let dueAt: String?
    let priority: ExperimentPriority
    let assigneeKind: String
    let assigneeId: String

    init(operationID: UUID, draft: ExperimentTaskDraft) throws {
        try ExperimentInput.validate(draft.validationMessage)
        operationId = operationID.uuidString.lowercased(); hypothesisId = draft.hypothesisID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        method = draft.method; expectedOutcome = draft.expectedOutcome; status = draft.status
        dueAt = draft.dueAt.map(ExperimentInput.timestamp)
        priority = draft.priority; assigneeKind = "human"; assigneeId = draft.assigneeID
    }
    private enum CodingKeys: String, CodingKey {
        case operationId, hypothesisId, title, method, expectedOutcome, status, dueAt, priority, assigneeKind, assigneeId
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(hypothesisId, forKey: .hypothesisId)
        try values.encode(title, forKey: .title); try values.encode(method, forKey: .method)
        try values.encode(expectedOutcome, forKey: .expectedOutcome); try values.encode(status, forKey: .status)
        if let dueAt { try values.encode(dueAt, forKey: .dueAt) } else { try values.encodeNil(forKey: .dueAt) }
        try values.encode(priority, forKey: .priority); try values.encode(assigneeKind, forKey: .assigneeKind)
        try values.encode(assigneeId, forKey: .assigneeId)
    }
}

struct ExperimentSourceDraft: Identifiable {
    let id: UUID
    var label: String
    var url: String
}

struct ExperimentNoteDraft {
    var taskID: String
    var title: String
    var observedAt: Date
    var facts: String
    var interpretation: String
    var sources: [ExperimentSourceDraft]
    var findings: String
    var unresolved: String
    var nextCandidates: String

    static func empty(taskID: String, observedAt: Date) -> Self {
        Self(taskID: taskID, title: "", observedAt: observedAt, facts: "", interpretation: "", sources: [], findings: "", unresolved: "", nextCandidates: "")
    }
    var validationMessage: String {
        let textValidation = ExperimentInput.first([
            ExperimentInput.parent(taskID),
            ExperimentInput.text(title.trimmingCharacters(in: .whitespacesAndNewlines), label: "タイトル", required: true, limit: 500),
            ExperimentInput.text(facts, label: "観測した事実", required: true, limit: 100_000),
        ] + [(interpretation, "解釈・考察"), (findings, "判明したこと"), (unresolved, "未解決事項"), (nextCandidates, "次の検証候補")].map {
            ExperimentInput.text($0.0, label: $0.1, required: false, limit: 100_000)
        })
        if !textValidation.isEmpty { return textValidation }
        if sources.count > 100 { return "参照元は100件以内で登録してください。" }
        for source in sources {
            let labelValidation = ExperimentInput.text(source.label.trimmingCharacters(in: .whitespacesAndNewlines), label: "参照元の名前", required: true, limit: 500)
            if !labelValidation.isEmpty { return labelValidation }
            guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()),
                  let host = url.host, !host.isEmpty else { return "参照元のURLはhttpまたはhttpsで入力してください。" }
        }
        return ""
    }
}

struct ExperimentNoteCreateRequest: Encodable {
    struct Source: Encodable { let label: String; let url: String }
    let operationId: String
    let taskId: String
    let title: String
    let observedAt: String
    let facts: String
    let interpretation: String
    let sources: [Source]
    let findings: String
    let unresolved: String
    let nextCandidates: String

    init(operationID: UUID, draft: ExperimentNoteDraft) throws {
        try ExperimentInput.validate(draft.validationMessage)
        operationId = operationID.uuidString.lowercased(); taskId = draft.taskID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        observedAt = ExperimentInput.timestamp(draft.observedAt)
        facts = draft.facts; interpretation = draft.interpretation
        sources = draft.sources.map { Source(label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines), url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines)) }
        findings = draft.findings; unresolved = draft.unresolved; nextCandidates = draft.nextCandidates
    }
}
