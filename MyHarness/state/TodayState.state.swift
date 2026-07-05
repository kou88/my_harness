import Foundation
import Observation

struct TodayItemRowState: Identifiable, Hashable {
    var item: RoutineItem
    var isCompleted: Bool

    var id: UUID { item.id }
}

@MainActor
@Observable
final class TodayState {
    var rows: [TodayItemRowState] = []
    var isLoading = false
    var errorMessage: String?
    var copiedMessage: String?

    private let useCases: AppUseCases

    init(useCases: AppUseCases) {
        self.useCases = useCases
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await useCases.syncWidgetUpdates.execute()
            rows = try await useCases.loadToday.execute().map { snapshot in
                TodayItemRowState(
                    item: snapshot.item,
                    isCompleted: snapshot.entry?.isCompleted ?? false
                )
            }
            try await publishWidgetSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func item(id: UUID) -> RoutineItem? {
        rows.first { $0.id == id }?.item
    }

    func toggleCompletion(for id: UUID) async {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isCompleted.toggle()
        await persistRow(rows[index])
    }

    func deleteItem(id: UUID) async {
        do {
            try await useCases.deleteRoutineItem.execute(id: id)
            await load()
        } catch {
            errorMessage = "削除に失敗しました: \(error.localizedDescription)"
        }
    }

    func moveRows(from offsets: IndexSet, to destination: Int) async {
        rows = reordered(rows, from: offsets, to: destination)

        do {
            try await useCases.reorderRoutineItems.execute(ids: rows.map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = "並べ替えに失敗しました: \(error.localizedDescription)"
            await load()
        }
    }

    func buildAndCopyWeeklyExport() async -> String? {
        do {
            let text = try await useCases.buildWeeklyExport.execute()
            useCases.copyText.execute(text)
            copiedMessage = "今週分をコピーしました"
            errorMessage = nil
            return text
        } catch {
            errorMessage = "コピーに失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    private func persistRow(_ row: TodayItemRowState) async {
        do {
            try await useCases.updateDayEntry.execute(
                itemId: row.id,
                isCompleted: row.isCompleted
            )
            try await publishWidgetSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func publishWidgetSnapshot() async throws {
        try await useCases.publishWidgetSnapshot.execute(rows: rows.map { row in
            WidgetItemSnapshot(
                id: row.item.id,
                title: row.item.title,
                sortOrder: row.item.sortOrder,
                isCompleted: row.isCompleted
            )
        })
    }

    private func reordered<T>(_ values: [T], from offsets: IndexSet, to destination: Int) -> [T] {
        var result = values
        let moving = offsets.map { result[$0] }
        for index in offsets.sorted(by: >) {
            result.remove(at: index)
        }
        let insertionIndex = max(0, min(destination - offsets.filter { $0 < destination }.count, result.count))
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }
}
