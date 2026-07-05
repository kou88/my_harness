import Foundation

enum HarnessAppGroup {
    static let identifier = "group.com.kou888.myharness"
}

struct WidgetItemSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sortOrder: Int
    var isCompleted: Bool
}

struct WidgetTodaySnapshot: Codable, Hashable {
    var dateKey: String
    var updatedAt: Date
    var items: [WidgetItemSnapshot]

    static func empty(dateKey: String) -> WidgetTodaySnapshot {
        WidgetTodaySnapshot(dateKey: dateKey, updatedAt: Date(), items: [])
    }
}

struct WidgetPendingEntryUpdate: Identifiable, Codable, Hashable {
    let id: UUID
    var dateKey: String
    var itemId: UUID
    var isCompleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dateKey: String,
        itemId: UUID,
        isCompleted: Bool,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.itemId = itemId
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}
