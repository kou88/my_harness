import Foundation
import Observation

@MainActor
@Observable
final class ItemEditorState {
    var title: String
    var repeatWeekdays: Set<RoutineWeekday>
    var errorMessage: String?
    var isSaving = false

    private let editingItem: RoutineItem?
    private let useCases: AppUseCases

    init(useCases: AppUseCases, editingItem: RoutineItem? = nil) {
        self.useCases = useCases
        self.editingItem = editingItem
        title = editingItem?.title ?? ""
        repeatWeekdays = editingItem?.repeatWeekdays ?? RoutineWeekday.everyDay
    }

    var navigationTitle: String {
        editingItem == nil ? "項目を追加" : "項目を編集"
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !repeatWeekdays.isEmpty
    }

    func toggleWeekday(_ weekday: RoutineWeekday) {
        if repeatWeekdays.contains(weekday) {
            repeatWeekdays.remove(weekday)
        } else {
            repeatWeekdays.insert(weekday)
        }
    }

    func save() async -> Bool {
        guard isValid else {
            errorMessage = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "項目名を入力してください"
                : "繰り返す曜日を1つ以上選んでください"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let editingItem {
                try await useCases.updateRoutineItem.execute(
                    id: editingItem.id,
                    title: title,
                    repeatWeekdays: repeatWeekdays
                )
            } else {
                try await useCases.createRoutineItem.execute(
                    title: title,
                    repeatWeekdays: repeatWeekdays
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}
