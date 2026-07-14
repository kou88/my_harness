@MainActor
protocol WidgetSnapshotRepository {
    func publish(_ snapshot: WidgetTodaySnapshot) async throws
    func consumePendingEntryUpdates() async throws -> [WidgetPendingEntryUpdate]
}

@MainActor
protocol WidgetSettingsRepository {
    func loadDisplaySettings() async throws -> WidgetDisplaySettings
    func saveDisplaySettings(_ settings: WidgetDisplaySettings) async throws
}
