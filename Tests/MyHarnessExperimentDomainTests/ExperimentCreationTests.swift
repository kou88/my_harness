import Foundation
import Testing
@testable import MyHarnessExperimentDomain

private let parentID = "d320a249-060a-4129-b77b-8067014d8e01"
private let operationID = UUID(uuidString: "C8872A86-C837-4EE3-A03E-23870FDD2D08")!

private func json<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

@Test func hypothesisCreationRequiresCriteriaAndCannotJudge() throws {
    var draft = ExperimentHypothesisDraft.empty(themeID: parentID)
    draft.statement = "  価格提示後に申込みがある  "
    draft.question = "有料で利用するか"
    draft.successCriteria = "5人中2人が申し込む"
    #expect(throws: (any Error).self) { try ExperimentHypothesisCreateRequest(operationID: operationID, draft: draft) }
    draft.falsificationCriteria = "5人とも申し込まない"
    let object = try json(ExperimentHypothesisCreateRequest(operationID: operationID, draft: draft))
    #expect(Set(object.keys) == Set(["operationId", "themeId", "statement", "background", "question", "successCriteria", "falsificationCriteria", "priority", "status"]))
    #expect(object["operationId"] as? String == operationID.uuidString.lowercased())
    #expect(object["statement"] as? String == "価格提示後に申込みがある")
    #expect(object["status"] as? String == "unverified")
    draft.status = .supported
    #expect(throws: (any Error).self) { try ExperimentHypothesisCreateRequest(operationID: operationID, draft: draft) }
}

@Test func taskCreationEncodesNoDeadlineAsNullAndDatesAsISO8601() throws {
    var draft = ExperimentTaskDraft.empty(hypothesisID: parentID, assigneeID: "current-user")
    draft.title = "5人に価格を提示する"
    draft.method = "同じ条件の資料で確認"
    draft.expectedOutcome = "申し込む人数"
    let request = try ExperimentTaskCreateRequest(operationID: operationID, draft: draft)
    let object = try json(request)
    #expect(Set(object.keys) == Set(["operationId", "hypothesisId", "title", "method", "expectedOutcome", "status", "dueAt", "priority", "assigneeKind", "assigneeId"]))
    #expect(object["dueAt"] is NSNull)
    #expect(object["assigneeKind"] as? String == "human")
    #expect(object["assigneeId"] as? String == "current-user")
    draft.dueAt = Date(timeIntervalSince1970: 1_792_800_000)
    let dated = try json(ExperimentTaskCreateRequest(operationID: operationID, draft: draft))
    let timestamp = try #require(dated["dueAt"] as? String)
    #expect(try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp) == draft.dueAt)
    draft.status = .completed
    #expect(throws: (any Error).self) { try ExperimentTaskCreateRequest(operationID: operationID, draft: draft) }
    // A retry keeps the original payload even if the editor's draft changes.
    #expect(try json(request)["dueAt"] is NSNull)
}

@Test func noteCreationSeparatesFactsAndInterpretationAndValidatesSources() throws {
    let observed = Date(timeIntervalSince1970: 1_792_800_000)
    var draft = ExperimentNoteDraft.empty(taskID: parentID, observedAt: observed)
    draft.title = "面談結果"
    draft.interpretation = "利用意思がありそう"
    #expect(throws: (any Error).self) { try ExperimentNoteCreateRequest(operationID: operationID, draft: draft) }
    draft.facts = "価格提示した5人中2人から申込みを受けた"
    draft.sources = [ExperimentSourceDraft(id: UUID(), label: "面談記録", url: "file:///private/record.md")]
    #expect(throws: (any Error).self) { try ExperimentNoteCreateRequest(operationID: operationID, draft: draft) }
    draft.sources[0].url = "https://example.com/record"
    let object = try json(ExperimentNoteCreateRequest(operationID: operationID, draft: draft))
    #expect(Set(object.keys) == Set(["operationId", "taskId", "title", "observedAt", "facts", "interpretation", "sources", "findings", "unresolved", "nextCandidates"]))
    #expect(object["facts"] as? String == draft.facts)
    #expect(object["interpretation"] as? String == draft.interpretation)
    let timestamp = try #require(object["observedAt"] as? String)
    #expect(try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp) == observed)
    let sources = try #require(object["sources"] as? [[String: String]])
    #expect(sources == [["label": "面談記録", "url": "https://example.com/record"]])
    draft.sources = []
    #expect(try json(ExperimentNoteCreateRequest(operationID: operationID, draft: draft))["sources"] is [Any])
}

@Test func creationRequiresASelectedParentAndEnforcesAPITextLimits() {
    var draft = ExperimentTaskDraft.empty(hypothesisID: "", assigneeID: "current-user")
    draft.title = "検証"
    draft.method = "確認"
    draft.expectedOutcome = "記録"
    #expect(throws: (any Error).self) { try ExperimentTaskCreateRequest(operationID: operationID, draft: draft) }
    draft.hypothesisID = parentID
    draft.title = String(repeating: "😀", count: 251)
    #expect(throws: (any Error).self) { try ExperimentTaskCreateRequest(operationID: operationID, draft: draft) }
    draft.title = "検証"
    draft.method = String(repeating: "a", count: 100_001)
    #expect(throws: (any Error).self) { try ExperimentTaskCreateRequest(operationID: operationID, draft: draft) }
}
