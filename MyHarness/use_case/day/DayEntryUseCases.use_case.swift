import Foundation

@MainActor
struct LoadTodayUseCase {
    let readStore: TodayReadStore

    func execute(date: Date = Date()) async throws -> [TodayItemSnapshot] {
        try await readStore.snapshots(for: date)
    }
}

@MainActor
struct UpdateDayEntryUseCase {
    let repository: DayEntryRepository
    let calendar: CalendarProviding

    func execute(
        itemId: UUID,
        date: Date = Date(),
        isCompleted: Bool
    ) async throws {
        let dateKey = calendar.dateKey(for: date)
        let existing = try await repository.entry(dateKey: dateKey, itemId: itemId)
        let entry = DayEntry(
            id: existing?.id ?? UUID(),
            dateKey: dateKey,
            itemId: itemId,
            isCompleted: isCompleted,
            logText: "",
            completedAt: isCompleted ? (existing?.completedAt ?? Date()) : nil,
            updatedAt: Date()
        )
        try await repository.upsert(entry)
    }

    func execute(
        item: RoutineItem,
        date: Date = Date(),
        isCompleted: Bool
    ) async throws {
        if item.scheduleKind == .oneShot && !isCompleted {
            let completedEntries = try await repository.completedEntries(itemId: item.id)
            for entry in completedEntries {
                var nextEntry = entry
                nextEntry.isCompleted = false
                nextEntry.completedAt = nil
                nextEntry.updatedAt = Date()
                try await repository.upsert(nextEntry)
            }
            return
        }

        try await execute(itemId: item.id, date: date, isCompleted: isCompleted)
    }
}
