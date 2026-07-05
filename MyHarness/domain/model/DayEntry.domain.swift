import Foundation

struct DayEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let dateKey: String
    let itemId: UUID
    var isCompleted: Bool
    var logText: String
    var completedAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dateKey: String,
        itemId: UUID,
        isCompleted: Bool,
        logText: String = "",
        completedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.itemId = itemId
        self.isCompleted = isCompleted
        self.logText = logText
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }
}

struct TodayItemSnapshot: Identifiable, Hashable {
    let item: RoutineItem
    let entry: DayEntry?

    var id: UUID { item.id }
}

struct WeekDaySnapshot: Identifiable, Hashable {
    let date: Date
    let dateKey: String
    let items: [TodayItemSnapshot]

    var id: String { dateKey }
}

