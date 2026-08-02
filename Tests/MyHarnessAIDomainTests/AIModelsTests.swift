import Foundation
import Testing
@testable import MyHarnessAIDomain

@Test func decodesReplayableRunEvent() throws {
    let json = """
    {
      "id": "01c633c5-4a9b-4d35-a0b3-2f3285c5577e",
      "seq": 31,
      "runId": "28747265-1250-42ad-80d9-0d20c4d53b80",
      "conversationId": "4037e551-2d12-4f17-86f0-8f7e8f20545c",
      "type": "command.output",
      "payload": { "text": "Tests passed", "exitCode": 0 },
      "createdAt": "2026-08-02T10:54:00+09:00"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let event = try decoder.decode(AIEvent.self, from: Data(json.utf8))

    #expect(event.seq == 31)
    #expect(event.type == .commandOutput)
    #expect(event.displayText == "Tests passed")
}

@Test func activeAndTerminalStatusesAreExplicit() {
    #expect(AIConversationStatus.running.isActive)
    #expect(AIConversationStatus.awaitingApproval.isActive)
    #expect(!AIConversationStatus.failed.isActive)
    #expect(AIRunStatus.completed.isTerminal)
    #expect(AIRunStatus.cancelled.isTerminal)
    #expect(!AIRunStatus.running.isTerminal)
}

@Test func providerAndModeLabelsRemainUserFacing() {
    #expect(AIProvider.openai.label == "OpenAI")
    #expect(AIProvider.openrouter.label == "OpenRouter")
    #expect(AIConversationMode.consultation.label == "相談")
    #expect(AIConversationMode.work.label == "作業")
}

@Test func decodesPublishedModelAndMessageContracts() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let modelJSON = """
    {
      "id": "host:runtime:gpt-5.6",
      "model": "gpt-5.6",
      "name": "GPT-5.6",
      "displayName": "GPT-5.6",
      "provider": "openai",
      "runtimeId": "d188be25-7634-47bf-ba27-6b5eb05b07a3",
      "hostId": "4037e551-2d12-4f17-86f0-8f7e8f20545c",
      "hostName": "Mac",
      "status": "online",
      "isAvailable": true,
      "reasoningEfforts": ["medium", "high"],
      "supportsImages": true,
      "supportsFiles": true,
      "supportsTools": true
    }
    """
    let messageJSON = """
    {
      "id": "01c633c5-4a9b-4d35-a0b3-2f3285c5577e",
      "conversationId": "4037e551-2d12-4f17-86f0-8f7e8f20545c",
      "runtimeSessionId": "28747265-1250-42ad-80d9-0d20c4d53b80",
      "runId": "75d89055-0200-4897-807a-603ac76f3c46",
      "role": "assistant",
      "status": "completed",
      "parentMessageId": null,
      "createdAt": "2026-08-02T10:54:00Z",
      "updatedAt": "2026-08-02T10:54:00Z",
      "contents": [{
        "id": "4feabdc4-122d-4aa2-84c1-2648c462e050",
        "contentType": "markdown",
        "text": "完了しました。",
        "attachmentId": null,
        "ordinal": 0
      }]
    }
    """

    let model = try decoder.decode(AIModelCatalogItem.self, from: Data(modelJSON.utf8))
    let message = try decoder.decode(AIMessage.self, from: Data(messageJSON.utf8))

    #expect(model.id != model.model)
    #expect(model.model == "gpt-5.6")
    #expect(model.isAvailable)
    #expect(message.text == "完了しました。")
    #expect(message.parentMessageId == nil)
}
