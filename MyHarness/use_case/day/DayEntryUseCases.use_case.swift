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
        isCompleted: Bool,
        logText: String
    ) async throws {
        let dateKey = calendar.dateKey(for: date)
        let existing = try await repository.entry(dateKey: dateKey, itemId: itemId)
        let trimmedLog = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DayEntry(
            id: existing?.id ?? UUID(),
            dateKey: dateKey,
            itemId: itemId,
            isCompleted: isCompleted,
            logText: trimmedLog,
            completedAt: isCompleted ? (existing?.completedAt ?? Date()) : nil,
            updatedAt: Date()
        )
        try await repository.upsert(entry)
    }
}

