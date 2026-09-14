import Foundation
import Testing
@testable import MyHarnessAIDomain

@Suite struct AICronModelsTests {
    @Test func safeCreateOperationUsesTheExactServerDiscriminator() throws {
        let request = AICronOperationRequest.create(.init(
            name: "朝の確認", prompt: "公式サイトを確認", schedule: "0 9 * * *",
            model: "", reasoningEffort: "medium", enabledToolsets: [.web, .browser]
        ))
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["kind"] as? String == "create")
        #expect(json["enabledToolsets"] as? [String] == ["web", "browser"])
        #expect(try JSONDecoder().decode(AICronOperationRequest.self, from: data) == request)
    }

    @Test func suggestionOperationsRoundTripWithoutJobFields() throws {
        let request = AICronOperationRequest.dismissSuggestion(suggestionId: "suggestion-1")
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["kind":"dismiss_suggestion", "suggestionId":"suggestion-1"])
        #expect(try JSONDecoder().decode(AICronOperationRequest.self, from: data) == request)
    }
}
