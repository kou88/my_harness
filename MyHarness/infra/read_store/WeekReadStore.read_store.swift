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
        let completedDateKeyByItemId = try await completedDateKeysByItemId()

        var entryByDateKeyAndItemId: [String: [UUID: DayEntry]] = [:]
        for entry in entries {
            entryByDateKeyAndItemId[entry.dateKey, default: [:]][entry.itemId] = entry
        }

        return zip(dates, dateKeys).map { date, dateKey in
            let entriesForDay = entryByDateKeyAndItemId[dateKey] ?? [:]
            let snapshots = items
                .filter { item in
                    item.isVisible(
                        on: date,
                        dateKey: dateKey,
                        createdDateKey: calendar.dateKey(for: item.createdAt),
                        completedDateKey: completedDateKeyByItemId[item.id],
                        calendar: calendar.calendar
                    )
                }
                .map { item in
                    TodayItemSnapshot(item: item, entry: entriesForDay[item.id])
                }
            return WeekDaySnapshot(date: date, dateKey: dateKey, items: snapshots)
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
