import Foundation
import SwiftData

@MainActor
final class SwiftDataDayEntryRepository: DayEntryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func entries(dateKey: String) async throws -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { model in
                model.dateKey == dateKey
            },
            sortBy: [
                SortDescriptor(\DayEntryModel.updatedAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func entries(dateKeys: [String]) async throws -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { model in
                dateKeys.contains(model.dateKey)
            },
            sortBy: [
                SortDescriptor(\DayEntryModel.dateKey, order: .forward),
                SortDescriptor(\DayEntryModel.updatedAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func completedEntries() async throws -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { model in
                model.isCompleted == true
            },
            sortBy: [
                SortDescriptor(\DayEntryModel.dateKey, order: .forward),
                SortDescriptor(\DayEntryModel.updatedAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func completedEntries(itemId: UUID) async throws -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { model in
                model.itemId == itemId && model.isCompleted == true
            },
            sortBy: [
                SortDescriptor(\DayEntryModel.dateKey, order: .forward),
                SortDescriptor(\DayEntryModel.updatedAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func entry(dateKey: String, itemId: UUID) async throws -> DayEntry? {
        try fetchModel(dateKey: dateKey, itemId: itemId)?.domain
    }

    func upsert(_ entry: DayEntry) async throws {
        if let model = try fetchModel(dateKey: entry.dateKey, itemId: entry.itemId) {
            model.update(from: entry)
        } else {
            context.insert(DayEntryModel(entry: entry))
        }
        try context.save()
    }

    private func fetchModel(dateKey: String, itemId: UUID) throws -> DayEntryModel? {
        var descriptor = FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { model in
                model.dateKey == dateKey && model.itemId == itemId
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
