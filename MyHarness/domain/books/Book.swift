import Foundation

struct Book: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let sha256: String
    let sizeBytes: Int64
    let pageCount: Int
    let status: String
    let createdAt: Date
}

struct BookPage: Decodable {
    let books: [Book]
    let nextCursor: String
}

struct BookCatalog: Codable {
    var books: [Book]
    var pages: [String: Int]
}

enum BookError: LocalizedError {
    case unavailable(String)
    case invalidFile
    case insufficientSpace
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidFile: return "PDFの容量・チェックサム・ページ数が一致しません。再ダウンロードしてください。"
        case .insufficientSpace: return "端末の空き容量が足りません。保存済みの本などを削除してください。"
        case .http(let code): return "ダウンロードに失敗しました（HTTP \(code)）。再試行してください。"
        }
    }
}
