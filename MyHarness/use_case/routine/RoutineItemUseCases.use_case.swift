import Foundation

@MainActor
struct CreateRoutineItemUseCase {
    let repository: RoutineItemRepository

    func execute(title: String, type: RoutineItemType) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let items = try await repository.listActive()
        let nextOrder = (items.map(\.sortOrder).max() ?? -1) + 1
        let item = RoutineItem(title: trimmed, type: type, sortOrder: nextOrder)
        try await repository.upsert(item)
    }
}

@MainActor
struct UpdateRoutineItemUseCase {
    let repository: RoutineItemRepository

    func execute(id: UUID, title: String, type: RoutineItemType) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var item = try await repository.item(id: id) else { return }
        item.title = trimmed
        item.type = type
        item.updatedAt = Date()
        try await repository.upsert(item)
    }
}

@MainActor
struct DeleteRoutineItemUseCase {
    let repository: RoutineItemRepository

    func execute(id: UUID) async throws {
        try await repository.archive(id: id)
    }
}

@MainActor
struct ReorderRoutineItemsUseCase {
    let repository: RoutineItemRepository

    func execute(ids: [UUID]) async throws {
        try await repository.reorder(ids: ids)
    }
}

