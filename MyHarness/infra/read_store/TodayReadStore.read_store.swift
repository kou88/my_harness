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
        let completedDateKeyByItemId = try await completedDateKeysByItemId()
        let items = try await itemRepository.listActive()
            .filter { item in
                item.isVisible(
                    on: date,
                    dateKey: dateKey,
                    createdDateKey: calendar.dateKey(for: item.createdAt),
                    completedDateKey: completedDateKeyByItemId[item.id],
                    calendar: calendar.calendar
                )
            }
        let entries = try await dayEntryRepository.entries(dateKey: dateKey)
        let entryByItemId = Dictionary(uniqueKeysWithValues: entries.map { ($0.itemId, $0) })

        return items.map { item in
            TodayItemSnapshot(item: item, entry: entryByItemId[item.id])
        }
    }

    private func completedDateKeysByItemId() async throws -> [UUID: String] {
        let completedEntries = try await dayEntryRepository.completedEntries()
        var result: [UUID: String] = [:]
        for entry in completedEntries {
            if let existingDateKey = result[entry.itemId] {
                result[entry.itemId] = min(existingDateKey, entry.dateKey)
            } else {
                result[entry.itemId] = entry.dateKey
            }
        }
        return result
    }
}
