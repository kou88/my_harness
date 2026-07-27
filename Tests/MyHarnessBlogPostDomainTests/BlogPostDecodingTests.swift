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
