@MainActor
protocol WidgetSnapshotRepository {
    func publish(_ snapshot: WidgetTodaySnapshot) async throws
    func consumePendingEntryUpdates() async throws -> [WidgetPendingEntryUpdate]
}

