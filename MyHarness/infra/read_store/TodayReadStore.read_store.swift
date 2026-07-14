import Foundation

@MainActor
protocol TodayReadStore {
    func snapshots(for date: Date) async throws -> [TodayItemSnapshot]
}

@MainActor
final class SwiftDataTodayReadStore: TodayReadStore {
    private let itemRepository: RoutineItemRepository
    private let dayEntryRepository: DayEntryRepository
    private let calendar: CalendarProviding

    init(
        itemRepository: RoutineItemRepository,
        dayEntryRepository: DayEntryRepository,
        calendar: CalendarProviding
    ) {
        self.itemRepository = itemRepository
        self.dayEntryRepository = dayEntryRepository
        self.calendar = calendar
    }

    func snapshots(for date: Date) async throws -> [TodayItemSnapshot] {
        let dateKey = calendar.dateKey(for: date)
        let completedEntryByItemId = try await earliestCompletedEntriesByItemId()
        let completedDateKeyByItemId = completedEntryByItemId.mapValues(\.dateKey)
        let items = try await itemRepository.listActive()
            .filter { item in
                isVisibleInTodayFeature(
                    item: item,
                    on: date,
                    dateKey: dateKey,
                    createdDateKey: calendar.dateKey(for: item.createdAt),
                    completedDateKey: completedDateKeyByItemId[item.id]
                )
            }
        let entries = try await dayEntryRepository.entries(dateKey: dateKey)
        let entryByItemId = Dictionary(uniqueKeysWithValues: entries.map { ($0.itemId, $0) })

        return items.map { item in
            let entry: DayEntry?
            if item.scheduleKind == .oneShot {
                entry = entryByItemId[item.id] ?? completedEntryByItemId[item.id]
            } else {
                entry = entryByItemId[item.id]
            }
            return TodayItemSnapshot(item: item, entry: entry)
        }
    }

    private func isVisibleInTodayFeature(
        item: RoutineItem,
        on date: Date,
        dateKey: String,
        createdDateKey: String,
        completedDateKey: String?
    ) -> Bool {
        if item.scheduleKind == .oneShot && item.isPinned {
            return dateKey >= createdDateKey
        }

        return item.isVisible(
            on: date,
            dateKey: dateKey,
            createdDateKey: createdDateKey,
            completedDateKey: completedDateKey,
            calendar: calendar.calendar
        )
    }

    private func earliestCompletedEntriesByItemId() async throws -> [UUID: DayEntry] {
        let completedEntries = try await dayEntryRepository.completedEntries()
        var result: [UUID: DayEntry] = [:]
        for entry in completedEntries {
            if let existingEntry = result[entry.itemId] {
                result[entry.itemId] = existingEntry.dateKey <= entry.dateKey ? existingEntry : entry
            } else {
                result[entry.itemId] = entry
            }
        }
        return result
    }
}
