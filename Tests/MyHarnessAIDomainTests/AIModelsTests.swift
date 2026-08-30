import Foundation
import Testing
@testable import MyHarnessAIDomain

private func event(_ seq: Int, _ type: String, _ data: [String: AIJSON]) -> AIEvent {
    AIEvent(seq: seq, type: type, data: data, createdAt: "2026-08-30T00:00:00Z")
}
private func run() -> AIRun {
    AIRun(id: UUID().uuidString.lowercased(), conversationId: UUID().uuidString.lowercased(), hostId: UUID().uuidString.lowercased(), modelId: UUID().uuidString.lowercased(), model: "qwen", settings: AISettings(contextLength: 65536, maxOutputTokens: 4096, reasoningEffort: "medium"), delivery: .changes, inputText: "test", outputText: "", status: "queued", cancelRequested: false, lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "", updatedAt: "")
}
@Test func replayDoesNotDuplicateOutput() throws {
    var value = run()
    let delta = event(1, "text.delta", ["text": .string("回答")])
    try value.apply(delta); try value.apply(delta)
    #expect(value.outputText == "回答")
    #expect(value.lastSeq == 1)
}
@Test func missingEventRequiresReplay() {
    var value = run()
    #expect(throws: AIContractError.self) { try value.apply(event(2, "text.delta", ["text": .string("欠落")])) }
}
@Test func toolCallsAndResultsKeepTheirIdentity() {
    let trace = AITrace(events: [
        event(1, "tool.call", ["id": .string("c1"), "name": .string("execute_code"), "arguments": .string("")]),
        event(2, "tool.call", ["id": .string("c1"), "name": .string("execute_code"), "arguments": .string("print(385)")]),
        event(3, "tool.result", ["id": .string("c1"), "output": .string("385")]),
    ])
    #expect(trace.tools.count == 1)
    #expect(trace.tools[0].arguments == "print(385)")
    #expect(trace.tools[0].output == "385")
    #expect(trace.tools[0].completed)
}
@Test func invalidSettingsAreNotSentToTheModel() {
    let settings = AISettings(contextLength: 65536, maxOutputTokens: 4096, reasoningEffort: "medium")
    let model = AIModel(id: "id", hostId: "host", hostName: "PC", model: "qwen", name: "Qwen", online: true, contextLengths: [65536,262144], maxOutputTokens: 32768, reasoningEfforts: ["medium","max"], reasoningBudgets: ["medium":1024,"max":16384], initialSettings: settings)
    #expect(model.accepts(settings))
    #expect(!model.accepts(AISettings(contextLength: 65536, maxOutputTokens: 4096, reasoningEffort: "max")))
}

@Test func rendersCodeAndWrappedToolOutputReadably() {
    let tool = AITool(id: "call", name: "execute_code", arguments: #"{"code":"print(7 * 8)\n"}"#,
        output: #"[{"type":"input_text","text":"{\"status\":\"success\",\"output\":\"56\\n\"}"}]"#, completed: true)
    #expect(tool.displayArguments == "print(7 * 8)\n")
    #expect(tool.displayOutput.hasPrefix("{\n"))
    #expect(tool.displayOutput.contains("success"))
    #expect(tool.displayOutput.contains("56"))
    #expect(!tool.displayOutput.contains("input_text"))
}

@Test func preservesPlainToolOutput() {
    let tool = AITool(id: "call", name: "terminal", arguments: "echo hi", output: "hi\n", completed: true)
    #expect(tool.displayArguments == "echo hi")
    #expect(tool.displayOutput == "hi\n")
}

@Test func sharingCapacityKeepsEightRunsInsideThePool() throws {
    var sharing = AISharing(enabled: true, modelId: "model", contextLength: 32768, maxConcurrentRuns: 8, revision: 1)
    #expect(sharing.capacityIsValid)
    #expect(try JSONDecoder().decode(AISharing.self, from: JSONEncoder().encode(sharing)) == sharing)
    sharing.contextLength = 65536
    #expect(!sharing.capacityIsValid)
    sharing.maxConcurrentRuns = 4
    #expect(sharing.capacityIsValid)
    sharing.maxConcurrentRuns = 5; sharing.contextLength = 32768
    #expect(sharing.capacityIsValid)
    sharing.contextLength = 65536
    #expect(!sharing.capacityIsValid)
    sharing.maxConcurrentRuns = 0
    #expect(!sharing.capacityIsValid)
}

@Test func codingContextUsesTheFlatServerContract() throws {
    let context = AIContext.opencode(AICodingContext(repositoryId: "repo", repository: "owner/repo", hostId: "host", baseBranch: "main", workBranch: "agent/conversation"))
    let encoded = try JSONEncoder().encode(context)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: String])
    #expect(json["harness"] == "opencode")
    #expect(json["repository"] == "owner/repo")
    #expect(try JSONDecoder().decode(AIContext.self, from: encoded) == context)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(AIContext.self, from: Data(#"{"harness":"unknown"}"#.utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(AIContext.self, from: Data(#"{"harness":"opencode"}"#.utf8)) }
}
