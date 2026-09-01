import Foundation
import Testing
@testable import MyHarnessAIDomain

private func event(_ seq: Int, _ type: String, _ data: [String: AIJSON]) -> AIEvent {
    AIEvent(seq: seq, type: type, data: data, createdAt: "2026-08-30T00:00:00Z")
}
private func run() -> AIRun {
    AIRun(id: UUID().uuidString.lowercased(), conversationId: UUID().uuidString.lowercased(), hostId: UUID().uuidString.lowercased(), modelId: UUID().uuidString.lowercased(), model: "qwen", settings: AISettings(contextLength: 65536, maxOutputTokens: 4096, reasoningEffort: "medium"), delivery: .changes, inputText: "test", attachments: [], outputText: "", status: "queued", cancelRequested: false, lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "", updatedAt: "")
}
@Test func replayDoesNotDuplicateOutput() throws {
    var value = run()
    let delta = event(1, "text.delta", ["text": .string("回答")])
    try value.apply(delta); try value.apply(delta)
    #expect(value.outputText == "回答")
    #expect(value.lastSeq == 1)
}
@Test func streamingPresentationSmoothsABurstWithinFiveFrames() {
    var presentation = AIStreamingPresentation(text: "")
    presentation.receive(String(repeating: "速", count: 103))
    #expect(presentation.displayed.isEmpty)
    for _ in 0..<4 {
        let needsMore = presentation.advance()
        #expect(needsMore)
    }
    let needsMore = presentation.advance()
    #expect(!needsMore)
    #expect(presentation.displayed == String(repeating: "速", count: 103))
}
@Test func streamingPresentationResetsSafelyWhenTextIsReplaced() {
    var presentation = AIStreamingPresentation(text: "old")
    presentation.receive("unrelated")
    #expect(presentation.displayed == "unrelated")
    #expect(!presentation.needsAdvance)
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

@Test func messagesReasoningAndToolsKeepEventOrder() {
    let trace = AITrace(events: [
        event(1, "reasoning.delta", ["text": .string("調査します")]),
        event(2, "text.delta", ["text": .string("まず公式情報を確認します。")]),
        event(3, "tool.call", ["id": .string("c1"), "name": .string("web_search"), "arguments": .string("気象庁")]),
        event(4, "tool.result", ["id": .string("c1"), "output": .string("404")]),
        event(5, "text.delta", ["text": .string("旧URLは404でした。別経路を探します。")]),
        event(6, "tool.call", ["id": .string("c2"), "name": .string("terminal"), "arguments": .string("fetch")]),
        event(7, "tool.result", ["id": .string("c2"), "output": .string("ok")]),
        event(8, "text.delta", ["text": .string("取得できました。")]),
    ])
    let entries = trace.timeline(displayedOutput: "まず公式情報を確認します。旧URLは404でした。別経路を探します。取得できました。")
    let signature = entries.map { entry in
        switch entry {
        case .reasoning(_, let text): return "reasoning:" + text
        case .message(_, let text): return "message:" + text
        case .tool(_, let tool): return "tool:" + tool.name
        }
    }
    #expect(signature == [
        "reasoning:調査します", "message:まず公式情報を確認します。", "tool:web_search",
        "message:旧URLは404でした。別経路を探します。", "tool:terminal", "message:取得できました。",
    ])
}

@Test func pacedOutputIsSplitAcrossMessageBoundaries() {
    let trace = AITrace(events: [
        event(1, "text.delta", ["text": .string("before")]),
        event(2, "tool.call", ["id": .string("c1"), "name": .string("terminal"), "arguments": .string("run")]),
        event(3, "tool.result", ["id": .string("c1"), "output": .string("ok")]),
        event(4, "text.delta", ["text": .string(" after tool")]),
    ])
    let entries = trace.timeline(displayedOutput: "before after")
    let messages = entries.compactMap { entry -> String? in
        if case .message(_, let text) = entry { return text }
        return nil
    }
    #expect(messages == ["before", " after"])
}

@Test func consecutiveReasoningAndToolsCollapseBetweenVisibleMessages() {
    let trace = AITrace(events: [
        event(1, "text.delta", ["text": .string("確認します。")]),
        event(2, "reasoning.delta", ["text": .string("調査中")]),
        event(3, "tool.call", ["id": .string("c1"), "name": .string("terminal"), "arguments": .string("run")]),
        event(4, "tool.result", ["id": .string("c1"), "output": .string("ok")]),
        event(5, "reasoning.delta", ["text": .string("結果を確認")]),
        event(6, "tool.call", ["id": .string("c2"), "name": .string("search_files"), "arguments": .string("query")]),
        event(7, "tool.result", ["id": .string("c2"), "output": .string("found")]),
        event(8, "text.delta", ["text": .string("完了しました。")]),
    ])

    let sections = trace.groupedTimeline(displayedOutput: "確認します。完了しました。")
    #expect(sections.count == 3)
    guard case .message(_, let firstMessage) = sections[0],
          case .activities(_, let activities) = sections[1],
          case .message(_, let lastMessage) = sections[2] else {
        Issue.record("本文の間に作業グループが必要")
        return
    }
    #expect(firstMessage == "確認します。")
    #expect(activities.count == 4)
    #expect(lastMessage == "完了しました。")
}
@Test func invalidSettingsAreNotSentToTheModel() {
    let settings = AISettings(contextLength: 65536, maxOutputTokens: 4096, reasoningEffort: "medium")
    let model = AIModel(id: "id", hostId: "host", hostName: "PC", model: "qwen", name: "Qwen", online: true, contextLengths: [65536,262144], maxOutputTokens: 32768, reasoningEfforts: ["medium","max"], reasoningBudgets: ["medium":1024,"max":16384], initialSettings: settings, inputModalities: [.text])
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
