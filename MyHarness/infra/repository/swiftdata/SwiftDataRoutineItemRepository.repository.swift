import Foundation
import SwiftData

@MainActor
final class SwiftDataRoutineItemRepository: RoutineItemRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func listActive() async throws -> [RoutineItem] {
        let descriptor = FetchDescriptor<RoutineItemModel>(
            predicate: #Predicate { model in
                model.isArchived == false
            },
            sortBy: [
                SortDescriptor(\RoutineItemModel.sortOrder, order: .forward),
                SortDescriptor(\RoutineItemModel.createdAt, order: .forward)
            ]
        )
        return RoutineItem.displayOrdered(try context.fetch(descriptor).map(\.domain))
    }

    func item(id: UUID) async throws -> RoutineItem? {
        try fetchModel(id: id)?.domain
    }

    func upsert(_ item: RoutineItem) async throws {
        if let model = try fetchModel(id: item.id) {
            model.update(from: item)
        } else {
            context.insert(RoutineItemModel(item: item))
        }
        try context.save()
    }

    func archive(id: UUID) async throws {
        guard let model = try fetchModel(id: id) else { return }
        model.isArchived = true
        model.updatedAt = Date()
        try context.save()
    }

    func reorder(ids: [UUID]) async throws {
        let models = try activeModels()
        let orderById = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })

        for model in models {
            if let order = orderById[model.id] {
                model.sortOrder = order
                model.updatedAt = Date()
            }
        }

        try context.save()
    }

    private func activeModels() throws -> [RoutineItemModel] {
        let descriptor = FetchDescriptor<RoutineItemModel>(
            predicate: #Predicate { model in
                model.isArchived == false
            }
        )
        return try context.fetch(descriptor)
    }

    private func fetchModel(id: UUID) throws -> RoutineItemModel? {
        var descriptor = FetchDescriptor<RoutineItemModel>(
            predicate: #Predicate { model in
                model.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
