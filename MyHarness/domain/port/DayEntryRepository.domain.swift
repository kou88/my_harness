import Foundation

@MainActor
protocol DayEntryRepository {
    func entries(dateKey: String) async throws -> [DayEntry]
    func entries(dateKeys: [String]) async throws -> [DayEntry]
    func completedEntries() async throws -> [DayEntry]
    func completedEntries(itemId: UUID) async throws -> [DayEntry]
    func entry(dateKey: String, itemId: UUID) async throws -> DayEntry?
    func upsert(_ entry: DayEntry) async throws
}
