import Foundation

@MainActor
struct CreateRoutineItemUseCase {
    let repository: RoutineItemRepository

    func execute(
        title: String,
        scheduleKind: RoutineScheduleKind,
        repeatWeekdays: Set<RoutineWeekday>
    ) async throws -> RoutineItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let items = try await repository.listActive()
        let nextOrder = (items.map(\.sortOrder).max() ?? -1) + 1
        let item = RoutineItem(
            title: trimmed,
            scheduleKind: scheduleKind,
            isPinned: false,
            sortOrder: nextOrder,
            repeatWeekdays: repeatWeekdays
        )
        try await repository.upsert(item)
        return item
    }
}

@MainActor
struct UpdateRoutineItemUseCase {
    let repository: RoutineItemRepository

    func execute(
        id: UUID,
        title: String,
        scheduleKind: RoutineScheduleKind,
        repeatWeekdays: Set<RoutineWeekday>
    ) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var item = try await repository.item(id: id) else { return }
        item.title = trimmed
        item.type = .check
        item.scheduleKind = scheduleKind
        item.repeatWeekdays = repeatWeekdays.isEmpty ? RoutineWeekday.everyDay : repeatWeekdays
        item.updatedAt = Date()
        try await repository.upsert(item)
    }
}

@MainActor
struct UpdateOneShotPinUseCase {
    let repository: RoutineItemRepository

    func execute(id: UUID, isPinned: Bool) async throws {
        guard var item = try await repository.item(id: id), item.scheduleKind == .oneShot else {
            return
        }
        item.isPinned = isPinned
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

@MainActor
struct LoadWeekdayTaskGroupsUseCase {
    let repository: RoutineItemRepository

    func execute() async throws -> [WeekdayTaskGroup] {
        let items = try await repository.listActive()
        return RoutineWeekday.allCases.map { weekday in
            WeekdayTaskGroup(
                weekday: weekday,
                items: items.filter { $0.scheduleKind == .routine && $0.repeatWeekdays.contains(weekday) }
            )
        }
    }
}
