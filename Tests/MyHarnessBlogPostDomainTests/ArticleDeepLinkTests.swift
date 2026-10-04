import Foundation
import Testing
@testable import MyHarnessBlogPostDomain

@Test func acceptsOnlyOwnedArticleURLShapes() throws {
    let id = "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90"
    #expect(ArticleDeepLink.articleID(for: URL(string: "https://kou88.dev/articles/\(id)")!) == id)
    #expect(ArticleDeepLink.articleID(for: URL(string: "myharness://articles/\(id)")!) == id)
    #expect(ArticleDeepLink.articleID(for: URL(string: "https://kou88.dev/articles/\(id)?from=chat")!) == id)
    for value in [
        "http://kou88.dev/articles/\(id)",
        "https://evil.example/articles/\(id)",
        "https://kou88.dev.evil.example/articles/\(id)",
        "https://kou88.dev:8443/articles/\(id)",
        "https://user@kou88.dev/articles/\(id)",
        "https://kou88.dev/articles/\(id)/extra",
        "https://kou88.dev/articles/not-an-id",
        "myharness://articles/not-an-id",
        "myharness://articles/\(id)/extra",
    ] {
        #expect(ArticleDeepLink.articleID(for: URL(string: value)!) == nil)
    }
}
