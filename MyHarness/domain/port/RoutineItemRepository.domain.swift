import Foundation

@MainActor
protocol RoutineItemRepository {
    func listActive() async throws -> [RoutineItem]
    func item(id: UUID) async throws -> RoutineItem?
    func upsert(_ item: RoutineItem) async throws
    func archive(id: UUID) async throws
    func reorder(ids: [UUID]) async throws
}

