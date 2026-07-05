import Foundation

@MainActor
struct PublishWidgetSnapshotUseCase {
    let repository: WidgetSnapshotRepository
    let calendar: CalendarProviding

    func execute(rows: [WidgetItemSnapshot], date: Date = Date()) async throws {
        let snapshot = WidgetTodaySnapshot(
            dateKey: calendar.dateKey(for: date),
            updatedAt: Date(),
            items: rows.sorted { first, second in
                first.sortOrder < second.sortOrder
            }
        )
        try await repository.publish(snapshot)
    }
}

@MainActor
struct SyncWidgetUpdatesUseCase {
    let widgetRepository: WidgetSnapshotRepository
    let entryRepository: DayEntryRepository

    func execute() async throws {
        let updates = try await widgetRepository.consumePendingEntryUpdates()
        for update in updates {
            let existing = try await entryRepository.entry(
                dateKey: update.dateKey,
                itemId: update.itemId
            )
            let entry = DayEntry(
                id: existing?.id ?? UUID(),
                dateKey: update.dateKey,
                itemId: update.itemId,
                isCompleted: update.isCompleted,
                logText: "",
                completedAt: update.isCompleted ? (existing?.completedAt ?? update.updatedAt) : nil,
                updatedAt: update.updatedAt
            )
            try await entryRepository.upsert(entry)
        }
    }
}

@MainActor
struct LoadWidgetDisplaySettingsUseCase {
    let repository: WidgetSettingsRepository

    func execute() async throws -> WidgetDisplaySettings {
        try await repository.loadDisplaySettings()
    }
}

@MainActor
struct SaveWidgetDisplaySettingsUseCase {
    let repository: WidgetSettingsRepository

    func execute(_ settings: WidgetDisplaySettings) async throws {
        try await repository.saveDisplaySettings(settings)
    }
}
