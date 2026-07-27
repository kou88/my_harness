import Foundation

struct BlogPostInline: Codable, Hashable {
    var text: String
    var bold: Bool
    var italic: Bool
    var strikethrough: Bool
    var href: String?
}

enum BlogPostBlock: Codable, Hashable {
    case heading(level: Int, children: [BlogPostInline])
    case paragraph(children: [BlogPostInline])
    case blockquote(children: [BlogPostInline])
    case list(ordered: Bool, items: [[BlogPostInline]])
    case image(url: String, alt: String, caption: String?)
    case divider

    private enum CodingKeys: String, CodingKey {
        case type
        case level
        case children
        case ordered
        case items
        case url
        case alt
        case caption
    }

    private enum BlockType: String, Codable {
        case heading
        case paragraph
        case blockquote
        case list
        case image
        case divider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BlockType.self, forKey: .type) {
        case .heading:
            self = .heading(
                level: try container.decode(Int.self, forKey: .level),
                children: try container.decode([BlogPostInline].self, forKey: .children)
            )
        case .paragraph:
            self = .paragraph(
                children: try container.decode([BlogPostInline].self, forKey: .children)
            )
        case .blockquote:
            self = .blockquote(
                children: try container.decode([BlogPostInline].self, forKey: .children)
            )
        case .list:
            self = .list(
                ordered: try container.decode(Bool.self, forKey: .ordered),
                items: try container.decode([[BlogPostInline]].self, forKey: .items)
            )
        case .image:
            self = .image(
                url: try container.decode(String.self, forKey: .url),
                alt: try container.decode(String.self, forKey: .alt),
                caption: try container.decodeIfPresent(String.self, forKey: .caption)
            )
        case .divider:
            self = .divider
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let children):
            try container.encode(BlockType.heading, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(children, forKey: .children)
        case .paragraph(let children):
            try container.encode(BlockType.paragraph, forKey: .type)
            try container.encode(children, forKey: .children)
        case .blockquote(let children):
            try container.encode(BlockType.blockquote, forKey: .type)
            try container.encode(children, forKey: .children)
        case .list(let ordered, let items):
            try container.encode(BlockType.list, forKey: .type)
            try container.encode(ordered, forKey: .ordered)
            try container.encode(items, forKey: .items)
        case .image(let url, let alt, let caption):
            try container.encode(BlockType.image, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(alt, forKey: .alt)
            try container.encode(caption, forKey: .caption)
        case .divider:
            try container.encode(BlockType.divider, forKey: .type)
        }
    }
}

struct BlogPostTranslation: Codable, Hashable {
    var id: String
    var language: String
    var title: String
    var body: [BlogPostBlock]
    var plainText: String
    var provider: String
    var model: String
    var sourceContentHash: String
    var createdAt: Date
    var updatedAt: Date
}

enum BlogPostTranslationState: String, Codable, Hashable {
    case missing
    case fresh
    case stale
}

struct BlogPost: Codable, Hashable, Identifiable {
    var id: String
    var sourceType: String
    var sourceId: String
    var originalUrl: String
    var canonicalUrl: String
    var title: String
    var authorName: String
    var authorHandle: String?
    var language: String
    var publishedAt: Date?
    var coverImageUrl: String?
    var body: [BlogPostBlock]
    var plainText: String
    var contentHash: String
    var importedAt: Date
    var translation: BlogPostTranslation?
    var translationState: BlogPostTranslationState
    var createdAt: Date
    var updatedAt: Date

    var preferredTitle: String {
        translation?.title ?? title
    }

    var preferredPlainText: String {
        translation?.plainText ?? plainText
    }
}

enum XArticleTranslationMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case originalOnly = "none"
    case japanese = "ja"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .originalOnly:
            return "原文のみ"
        case .japanese:
            return "日本語訳も作成"
        }
    }
}

enum XArticleImportHostStatus: String, Codable, Hashable {
    case pending
    case online
    case offline
    case disabled

    var label: String {
        switch self {
        case .pending:
            return "未接続"
        case .online:
            return "オンライン"
        case .offline:
            return "オフライン"
        case .disabled:
            return "無効"
        }
    }
}

struct XArticleImportHost: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var hostname: String?
    var status: XArticleImportHostStatus
    var capabilities: [String]
    var tags: [String]

    var displayName: String {
        guard let hostname, !hostname.isEmpty, hostname != name else { return name }
        return "\(name)（\(hostname)）"
    }

    var missingImportTags: [String] {
        let availableTags = Set(capabilities + tags)
        return XArticleImportRequest.requiredTags.filter { !availableTags.contains($0) }
    }

    var canImportXArticle: Bool {
        status == .online && missingImportTags.isEmpty
    }
}

enum XArticleImportTaskStatus: String, Codable, Hashable {
    case queued
    case running
    case succeeded
    case failed
    case canceled
}

struct XArticleImportTask: Codable, Hashable, Identifiable {
    var id: String
    var hostId: String
    var status: XArticleImportTaskStatus
    var queuedAt: Date
    var createdAt: Date
    var updatedAt: Date
}

struct SharedXImportCandidate: Codable, Hashable, Identifiable {
    var id: String
    var sourceURL: String
    var sourceText: String?
    var createdAt: Date

    var canonicalKey: String {
        sourceURL
    }

    static func make(
        id: String,
        sharedURL: String,
        sharedText: String?,
        createdAt: Date
    ) throws -> SharedXImportCandidate {
        let normalizedIdentifier = id.lowercased()
        guard UUID(uuidString: normalizedIdentifier)?.uuidString.lowercased() == normalizedIdentifier else {
            throw SharedXImportCandidateValidationError.invalidIdentifier
        }

        let normalizedText = sharedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedXImportCandidate(
            id: normalizedIdentifier,
            sourceURL: try XArticleImportRequest.normalizedSourceURL(sharedURL),
            sourceText: normalizedText?.isEmpty == false ? normalizedText : nil,
            createdAt: createdAt
        )
    }
}

enum SharedXImportCandidateValidationError: LocalizedError {
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return "共有候補のIDがUUIDではありません。"
        }
    }
}

enum XArticleImportValidationError: LocalizedError {
    case invalidURL
    case unsupportedURL
    case hostNotReady

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "有効なX記事URLを入力してください。"
        case .unsupportedURL:
            return "https://x.com/{ユーザー名}/status/{記事ID} 形式のURLを入力してください。"
        case .hostNotReady:
            return "選択したPCではX記事を取り込めません。"
        }
    }
}

struct XArticleImportRequest: Encodable, Hashable {
    struct Payload: Encodable, Hashable {
        struct Input: Encodable, Hashable {
            var sourceUrl: String
            var translationMode: XArticleTranslationMode
        }

        var agentId: String
        var entrypoint: String
        var input: Input
        var command: String
        var args: [String]
        var cwd: String
    }

    static let requiredTags = [
        "has:deno",
        "network:internet",
        "browser:cdp",
        "has:my-system",
        "role:codex-app-server",
        "needs-api"
    ]

    var hostId: String
    var taskType: String
    var title: String
    var payload: Payload
    var requiredTags: [String]

    static func make(
        host: XArticleImportHost,
        sourceURL: String,
        translationMode: XArticleTranslationMode
    ) throws -> XArticleImportRequest {
        guard host.canImportXArticle else {
            throw XArticleImportValidationError.hostNotReady
        }
        return XArticleImportRequest(
            hostId: host.id,
            taskType: "x_article_import",
            title: "X記事を取り込む",
            payload: Payload(
                agentId: "x-agent",
                entrypoint: "article-import",
                input: Payload.Input(
                    sourceUrl: try normalizedSourceURL(sourceURL),
                    translationMode: translationMode
                ),
                command: "deno",
                args: ["task", "article-import"],
                cwd: "/Users/kou888/apps/x-agent"
            ),
            requiredTags: requiredTags
        )
    }

    static func normalizedSourceURL(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let hostname = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") else {
            throw XArticleImportValidationError.invalidURL
        }

        let allowedHosts = Set(["x.com", "twitter.com", "mobile.x.com", "mobile.twitter.com"])
        let components = url.pathComponents.filter { $0 != "/" }
        guard allowedHosts.contains(hostname),
              components.count == 3,
              components[1] == "status",
              !components[0].isEmpty,
              components[2].allSatisfy(\.isNumber) else {
            throw XArticleImportValidationError.unsupportedURL
        }

        return "https://x.com/\(components[0])/status/\(components[2])"
    }
}
