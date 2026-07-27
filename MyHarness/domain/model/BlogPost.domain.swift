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
