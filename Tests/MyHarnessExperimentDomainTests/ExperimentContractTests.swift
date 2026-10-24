import Foundation
import Testing
@testable import MyHarnessExperimentDomain

private func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "tree", withExtension: "json"))
    return try Data(contentsOf: url)
}
private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
    }
    return decoder
}
@Test func cliCreatedTreeDecodesAsFourLevels() throws {
    let tree = try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: fixture()).data
    #expect(tree.theme.title == "HP＋CRM（動作確認）")
    let hypothesis = try #require(tree.hypotheses.first)
    #expect(tree.tasks(for: hypothesis).count == 2)
    let task = try #require(tree.tasks.first { $0.status == .completed })
    #expect(tree.notes(for: task).count == 1)
    #expect(tree.notes(for: task)[0].version == 2)
    #expect(tree.notes(for: task)[0].facts.contains("3,500円"))
}
@Test func taskProgressAndHypothesisJudgmentStayIndependent() throws {
    let tree = try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: fixture()).data
    #expect(tree.tasks.filter { $0.status == .completed }.count == 1)
    #expect(tree.tasks.filter { !$0.isFinished }.count == 1)
    #expect(tree.hypotheses[0].status == .inconclusive)
    #expect(tree.judgments[0].decision == .inconclusive)
    #expect(tree.tasks[0].hypothesisRevisionId == tree.hypotheses[0].definitionRevisionId)
    #expect(tree.judgments[0].hypothesisRevisionId == tree.hypotheses[0].definitionRevisionId)
}
@Test func missingCriteriaFailInsteadOfFillingAPlaceholder() throws {
    var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    var data = try #require(object["data"] as? [String: Any])
    var hypotheses = try #require(data["hypotheses"] as? [[String: Any]])
    hypotheses[0].removeValue(forKey: "successCriteria")
    data["hypotheses"] = hypotheses; object["data"] = data
    let corrupt = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) { try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: corrupt) }
}
@Test func noDeadlineAndNoCompletionTimeRemainExplicitAbsence() throws {
    let tree = try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: fixture()).data
    let pending = try #require(tree.tasks.first { $0.status == .pending })
    #expect(pending.dueAt == nil)
    #expect(pending.completedAt == nil)
    let completed = try #require(tree.tasks.first { $0.status == .completed })
    #expect(completed.completedAt != nil)
}

@Test func archivedHypothesisHidesDescendantsFromThemeTabs() throws {
    var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    var data = try #require(object["data"] as? [String: Any])
    var hypotheses = try #require(data["hypotheses"] as? [[String: Any]])
    hypotheses[0]["archivedAt"] = "2026-10-24T00:00:00.000Z"
    data["hypotheses"] = hypotheses; object["data"] = data
    let tree = try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: JSONSerialization.data(withJSONObject: object)).data
    #expect(tree.visibleHypotheses.isEmpty)
    #expect(tree.visibleTasks.isEmpty)
    #expect(tree.visibleNotes.isEmpty)
}

@Test func archivedTaskHidesItsNotesWhileOtherTasksRemainVisible() throws {
    var object = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    var data = try #require(object["data"] as? [String: Any])
    var tasks = try #require(data["tasks"] as? [[String: Any]])
    let completedIndex = try #require(tasks.firstIndex { $0["status"] as? String == "completed" })
    tasks[completedIndex]["archivedAt"] = "2026-10-24T00:00:00.000Z"
    data["tasks"] = tasks; object["data"] = data
    let tree = try decoder().decode(ExperimentEnvelope<ExperimentTree>.self, from: JSONSerialization.data(withJSONObject: object)).data
    #expect(tree.visibleHypotheses.count == 1)
    #expect(tree.visibleTasks.count == 1)
    #expect(tree.visibleTasks[0].status == .pending)
    #expect(tree.visibleNotes.isEmpty)
}

@Test func themeCreationEncodesTheStrictAPIContract() throws {
    let operationID = try #require(UUID(uuidString: "C8872A86-C837-4EE3-A03E-23870FDD2D08"))
    var draft = ExperimentThemeDraft.empty
    draft.title = "  新しいテーマ\n"
    draft.description = "目的のメモ"
    draft.status = .paused
    let request = try ExperimentThemeCreateRequest(operationID: operationID, draft: draft)
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String])
    #expect(Set(object.keys) == Set(["operationId", "title", "description", "audience", "constraints", "status"]))
    #expect(object["operationId"] == "c8872a86-c837-4ee3-a03e-23870fdd2d08")
    #expect(object["title"] == "新しいテーマ")
    #expect(object["description"] == "目的のメモ")
    #expect(object["audience"] == "")
    #expect(object["constraints"] == "")
    #expect(object["status"] == "paused")
}

@Test func themeCreationRejectsInvalidTitlesAndStatuses() throws {
    let id = UUID()
    var draft = ExperimentThemeDraft.empty
    draft.title = " \n "
    #expect(throws: (any Error).self) { try ExperimentThemeCreateRequest(operationID: id, draft: draft) }
    draft.title = String(repeating: "😀", count: 250)
    _ = try ExperimentThemeCreateRequest(operationID: id, draft: draft)
    draft.title += "😀"
    #expect(throws: (any Error).self) { try ExperimentThemeCreateRequest(operationID: id, draft: draft) }
    draft.title = "正常なテーマ"
    draft.status = .supported
    #expect(throws: (any Error).self) { try ExperimentThemeCreateRequest(operationID: id, draft: draft) }
    draft.status = .active
    draft.description = String(repeating: "a", count: 100_001)
    #expect(throws: (any Error).self) { try ExperimentThemeCreateRequest(operationID: id, draft: draft) }
}
