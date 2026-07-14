import Foundation
import SwiftData

@Model
final class RoutineItemModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRawValue: String
    var scheduleKindRawValue: String = RoutineScheduleKind.routine.rawValue
    var sortOrder: Int
    var repeatWeekdaysRawValue: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(item: RoutineItem) {
        id = item.id
        title = item.title
        typeRawValue = item.type.rawValue
        scheduleKindRawValue = item.scheduleKind.rawValue
        sortOrder = item.sortOrder
        repeatWeekdaysRawValue = RoutineWeekday.storageValue(for: item.repeatWeekdays)
        isArchived = item.isArchived
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    func update(from item: RoutineItem) {
        title = item.title
        typeRawValue = item.type.rawValue
        scheduleKindRawValue = item.scheduleKind.rawValue
        sortOrder = item.sortOrder
        repeatWeekdaysRawValue = RoutineWeekday.storageValue(for: item.repeatWeekdays)
        isArchived = item.isArchived
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    func domain(isPinned: Bool) -> RoutineItem {
        RoutineItem(
            id: id,
            title: title,
            type: RoutineItemType(rawValue: typeRawValue) ?? .check,
            scheduleKind: resolvedScheduleKind,
            isPinned: isPinned,
            sortOrder: sortOrder,
            repeatWeekdays: RoutineWeekday.set(fromStorageValue: repeatWeekdaysRawValue),
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private var resolvedScheduleKind: RoutineScheduleKind {
        guard let scheduleKind = RoutineScheduleKind(rawValue: scheduleKindRawValue) else {
            preconditionFailure("Invalid RoutineItemModel schedule kind: \(scheduleKindRawValue)")
        }
        return scheduleKind
    }
}

@Model
final class OneShotPinModel {
    @Attribute(.unique) var itemId: UUID
    var createdAt: Date

    init(itemId: UUID, createdAt: Date) {
        self.itemId = itemId
        self.createdAt = createdAt
    }
}

@Model
final class DayEntryModel {
    @Attribute(.unique) var id: UUID
    var dateKey: String
    var itemId: UUID
    var isCompleted: Bool
    var logText: String
    var completedAt: Date?
    var updatedAt: Date

    init(entry: DayEntry) {
        id = entry.id
        dateKey = entry.dateKey
        itemId = entry.itemId
        isCompleted = entry.isCompleted
        logText = entry.logText
        completedAt = entry.completedAt
        updatedAt = entry.updatedAt
    }

    func update(from entry: DayEntry) {
        dateKey = entry.dateKey
        itemId = entry.itemId
        isCompleted = entry.isCompleted
        logText = entry.logText
        completedAt = entry.completedAt
        updatedAt = entry.updatedAt
    }

    var domain: DayEntry {
        DayEntry(
            id: id,
            dateKey: dateKey,
            itemId: itemId,
            isCompleted: isCompleted,
            logText: logText,
            completedAt: completedAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class HarnessSettingsModel {
    @Attribute(.unique) var key: String
    var notificationHour: Int
    var notificationMinute: Int

    init(key: String, notificationHour: Int, notificationMinute: Int) {
        self.key = key
        self.notificationHour = notificationHour
        self.notificationMinute = notificationMinute
    }
}
