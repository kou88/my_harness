import Foundation

enum RoutineItemType: String, CaseIterable, Codable, Hashable, Identifiable {
    case check
    case checkLog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .check:
            return "チェック"
        case .checkLog:
            return "チェック + 1行ログ"
        }
    }
}

struct RoutineItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var type: RoutineItemType
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        type: RoutineItemType,
        sortOrder: Int,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
