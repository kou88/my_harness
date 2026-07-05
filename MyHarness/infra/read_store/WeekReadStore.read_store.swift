import Foundation

@MainActor
protocol WeekReadStore {
    func weekdaySnapshots(containing date: Date) async throws -> [WeekDaySnapshot]
}

@MainActor
final class SwiftDataWeekReadStore: WeekReadStore {
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

    func weekdaySnapshots(containing date: Date) async throws -> [WeekDaySnapshot] {
        let dates = calendar.weekdayDates(containing: date)
        let dateKeys = dates.map { calendar.dateKey(for: $0) }
        let items = try await itemRepository.listActive()
        let entries = try await dayEntryRepository.entries(dateKeys: dateKeys)

        var entryByDateKeyAndItemId: [String: [UUID: DayEntry]] = [:]
        for entry in entries {
            entryByDateKeyAndItemId[entry.dateKey, default: [:]][entry.itemId] = entry
        }

        return zip(dates, dateKeys).map { date, dateKey in
            let entriesForDay = entryByDateKeyAndItemId[dateKey] ?? [:]
            let snapshots = items.map { item in
                TodayItemSnapshot(item: item, entry: entriesForDay[item.id])
            }
            return WeekDaySnapshot(date: date, dateKey: dateKey, items: snapshots)
        }
    }
}

