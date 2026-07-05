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
        let items = try await itemRepository.listActive()
        let entries = try await dayEntryRepository.entries(dateKey: dateKey)
        let entryByItemId = Dictionary(uniqueKeysWithValues: entries.map { ($0.itemId, $0) })

        return items.map { item in
            TodayItemSnapshot(item: item, entry: entryByItemId[item.id])
        }
    }
}

