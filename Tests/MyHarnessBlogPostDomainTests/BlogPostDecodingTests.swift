import Foundation
import Testing
@testable import MyHarnessBlogPostDomain

@Test func decodesBlogPostWithFlatInlineBlocksAndTranslation() throws {
    let json = """
    {
      "id": "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
      "sourceType": "x_article",
      "sourceId": "2081415714636996844",
      "originalUrl": "https://x.com/thedankoe/status/2081415714636996844",
      "canonicalUrl": "https://x.com/thedankoe/article/2081415714636996844",
      "title": "Original title",
      "authorName": "Dan Koe",
      "authorHandle": "thedankoe",
      "language": "en",
      "publishedAt": "2026-07-27T00:00:00Z",
      "coverImageUrl": null,
      "body": [
        {
          "type": "paragraph",
          "children": [
            {
              "text": "Read this",
              "bold": true,
              "italic": false,
              "strikethrough": false,
              "href": "https://example.com"
            }
          ]
        },
        {
          "type": "image",
          "url": "https://pbs.twimg.com/image.jpg",
          "alt": "cover",
          "caption": null
        }
      ],
      "plainText": "Read this",
      "contentHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "importedAt": "2026-07-27T00:01:00Z",
      "translation": {
        "id": "e6d9036a-653b-42d6-9ed3-d7b2b989ea99",
        "language": "ja",
        "title": "日本語タイトル",
        "body": [
          {
            "type": "paragraph",
            "children": [
              {
                "text": "この記事を読む",
                "bold": true,
                "italic": false,
                "strikethrough": false,
                "href": "https://example.com"
              }
            ]
          }
        ],
        "plainText": "この記事を読む",
        "provider": "codex-app-server",
        "model": "gpt-5",
        "sourceContentHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "createdAt": "2026-07-27T00:02:00Z",
        "updatedAt": "2026-07-27T00:02:00Z"
      },
      "translationState": "fresh",
      "createdAt": "2026-07-27T00:01:00Z",
      "updatedAt": "2026-07-27T00:02:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let post = try decoder.decode(BlogPost.self, from: Data(json.utf8))

    #expect(post.preferredTitle == "日本語タイトル")
    #expect(post.translationState == .fresh)
    #expect(post.body.count == 2)
    guard case .paragraph(let children) = post.body[0] else {
        Issue.record("paragraph blockをdecodeできていません")
        return
    }
    #expect(children[0].bold)
    #expect(children[0].href == "https://example.com")
}

@Test func normalizesSupportedXArticleStatusURLs() throws {
    #expect(
        try XArticleImportRequest.normalizedSourceURL(
            "https://x.com/thedankoe/status/2081415714636996844?s=46"
        ) == "https://x.com/thedankoe/status/2081415714636996844"
    )
    #expect(
        try XArticleImportRequest.normalizedSourceURL(
            "https://mobile.twitter.com/thedankoe/status/2081415714636996844/"
        ) == "https://x.com/thedankoe/status/2081415714636996844"
    )
}

@Test func rejectsURLsThatCannotBeImportedByXAgent() {
    #expect(throws: XArticleImportValidationError.self) {
        try XArticleImportRequest.normalizedSourceURL("https://example.com/article")
    }
    #expect(throws: XArticleImportValidationError.self) {
        try XArticleImportRequest.normalizedSourceURL("https://x.com/thedankoe/article/2081415714636996844")
    }
}

@Test func normalizesSharedXStatusURLsAndUsesTheCanonicalURLAsItsDeduplicationKey() throws {
    let createdAt = Date(timeIntervalSince1970: 1_785_196_800)
    let candidate = try SharedXImportCandidate.make(
        id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
        sharedURL: "https://twitter.com/thedankoe/status/2081415714636996844?s=46&t=tracking",
        sharedText: "  入金照合について参考になる投稿です。  ",
        createdAt: createdAt
    )

    #expect(candidate.id == "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90")
    #expect(candidate.sourceURL == "https://x.com/thedankoe/status/2081415714636996844")
    #expect(candidate.canonicalKey == candidate.sourceURL)
    #expect(candidate.sourceText == "入金照合について参考になる投稿です。")
    #expect(candidate.createdAt == createdAt)
}

@Test func createsASharedXImportCandidateFromAURLOnlyShare() throws {
    let candidate = try SharedXImportCandidate.make(
        id: "e6d9036a-653b-42d6-9ed3-d7b2b989ea99",
        sharedURL: "https://x.com/thedankoe/status/2081415714636996844?ref_src=twsrc%5Etfw",
        sharedText: nil,
        createdAt: Date(timeIntervalSince1970: 1_785_196_800)
    )

    #expect(candidate.sourceURL == "https://x.com/thedankoe/status/2081415714636996844")
    #expect(candidate.sourceText == nil)
    #expect(candidate.canonicalKey == "https://x.com/thedankoe/status/2081415714636996844")
}

@Test func treatsWhitespaceOnlySharedTextAsAbsent() throws {
    let candidate = try SharedXImportCandidate.make(
        id: "a15515e2-b5b3-489d-a5a4-769143db2d88",
        sharedURL: "https://x.com/thedankoe/status/2081415714636996844",
        sharedText: " \n\t ",
        createdAt: Date(timeIntervalSince1970: 1_785_196_800)
    )

    #expect(candidate.sourceText == nil)
}

@Test func rejectsNonXAndMalformedSharedURLs() {
    do {
        _ = try SharedXImportCandidate.make(
            id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
            sharedURL: "https://example.com/thedankoe/status/2081415714636996844",
            sharedText: nil,
            createdAt: Date(timeIntervalSince1970: 1_785_196_800)
        )
        Issue.record("X以外のURLから取込候補を作成できてしまいました")
    } catch {
        // URL拒否が契約であり、具体的なエラー型は実装詳細とする。
    }

    do {
        _ = try SharedXImportCandidate.make(
            id: "e6d9036a-653b-42d6-9ed3-d7b2b989ea99",
            sharedURL: "not a URL",
            sharedText: nil,
            createdAt: Date(timeIntervalSince1970: 1_785_196_800)
        )
        Issue.record("壊れたURLから取込候補を作成できてしまいました")
    } catch {
        // URL拒否が契約であり、具体的なエラー型は実装詳細とする。
    }
}

@Test func buildsExplicitXAgentImportTaskForCompatibleHost() throws {
    let host = XArticleImportHost(
        id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
        name: "MacBook Pro",
        hostname: "kou-macbook.local",
        status: .online,
        capabilities: ["has:deno", "network:internet"],
        tags: [
            "browser:cdp",
            "has:my-system",
            "role:codex-app-server",
            "needs-api"
        ]
    )

    #expect(host.canImportXArticle)
    let request = try XArticleImportRequest.make(
        host: host,
        sourceURL: "https://x.com/thedankoe/status/2081415714636996844?s=46",
        translationMode: .japanese
    )

    #expect(request.hostId == host.id)
    #expect(request.taskType == "x_article_import")
    #expect(request.payload.agentId == "x-agent")
    #expect(request.payload.entrypoint == "article-import")
    #expect(request.payload.input.translationMode == .japanese)
    #expect(request.payload.input.sourceUrl == "https://x.com/thedankoe/status/2081415714636996844")
    #expect(request.requiredTags == XArticleImportRequest.requiredTags)
}

@Test func rejectsOfflineOrMissingCapabilityHost() {
    let host = XArticleImportHost(
        id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
        name: "MacBook Pro",
        hostname: nil,
        status: .offline,
        capabilities: ["has:deno"],
        tags: []
    )

    #expect(!host.canImportXArticle)
    #expect(host.missingImportTags == Array(XArticleImportRequest.requiredTags.dropFirst()))
    #expect(throws: XArticleImportValidationError.self) {
        try XArticleImportRequest.make(
            host: host,
            sourceURL: "https://x.com/thedankoe/status/2081415714636996844",
            translationMode: .originalOnly
        )
    }
}

@Test func encodesTheXAgentTaskContractWithoutImplicitValues() throws {
    let host = XArticleImportHost(
        id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
        name: "MacBook Pro",
        hostname: "kou-macbook.local",
        status: .online,
        capabilities: XArticleImportRequest.requiredTags,
        tags: []
    )
    let request = try XArticleImportRequest.make(
        host: host,
        sourceURL: "https://x.com/thedankoe/status/2081415714636996844",
        translationMode: .originalOnly
    )
    let root = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    let payload = try #require(root["payload"] as? [String: Any])
    let input = try #require(payload["input"] as? [String: Any])

    #expect(root["hostId"] as? String == host.id)
    #expect(root["taskType"] as? String == "x_article_import")
    #expect(root["title"] as? String == "X記事を取り込む")
    #expect(root["requiredTags"] as? [String] == XArticleImportRequest.requiredTags)
    #expect(payload["agentId"] as? String == "x-agent")
    #expect(payload["entrypoint"] as? String == "article-import")
    #expect(payload["command"] as? String == "deno")
    #expect(payload["args"] as? [String] == ["task", "article-import"])
    #expect(payload["cwd"] as? String == "/Users/kou888/apps/x-agent")
    #expect(input["sourceUrl"] as? String == "https://x.com/thedankoe/status/2081415714636996844")
    #expect(input["translationMode"] as? String == "none")
}

@Test func decodesAgentHostAndQueuedTaskFromCurrentAPIResponses() throws {
    let hostJSON = """
    {
      "id": "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
      "authKeyId": null,
      "deviceKey": null,
      "name": "MacBook Pro",
      "hostname": "kou-macbook.local",
      "os": "macos",
      "arch": "aarch64",
      "agentVersion": "0.1.0",
      "status": "online",
      "capabilities": ["has:deno"],
      "tags": ["browser:cdp"],
      "createdAt": "2026-07-27T00:00:00Z",
      "updatedAt": "2026-07-27T00:00:00Z"
    }
    """
    let taskJSON = """
    {
      "id": "a15515e2-b5b3-489d-a5a4-769143db2d88",
      "hostId": "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
      "taskType": "x_article_import",
      "title": "X記事を取り込む",
      "payload": {},
      "requiredTags": [],
      "status": "queued",
      "resultText": null,
      "result": null,
      "error": null,
      "queuedAt": "2026-07-27T00:01:00Z",
      "startedAt": null,
      "finishedAt": null,
      "createdAt": "2026-07-27T00:01:00Z",
      "updatedAt": "2026-07-27T00:01:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let host = try decoder.decode(XArticleImportHost.self, from: Data(hostJSON.utf8))
    let task = try decoder.decode(XArticleImportTask.self, from: Data(taskJSON.utf8))

    #expect(host.displayName == "MacBook Pro（kou-macbook.local）")
    #expect(task.status == .queued)
}
