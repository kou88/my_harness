import Foundation
import Observation

@MainActor
@Observable
final class ItemEditorState {
    var title: String
    var type: RoutineItemType
    var errorMessage: String?
    var isSaving = false

    private let editingItem: RoutineItem?
    private let useCases: AppUseCases

    init(useCases: AppUseCases, editingItem: RoutineItem? = nil) {
        self.useCases = useCases
        self.editingItem = editingItem
        title = editingItem?.title ?? ""
        type = editingItem?.type ?? .check
    }

    var navigationTitle: String {
        editingItem == nil ? "項目を追加" : "項目を編集"
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() async -> Bool {
        guard isValid else {
            errorMessage = "項目名を入力してください"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let editingItem {
                try await useCases.updateRoutineItem.execute(id: editingItem.id, title: title, type: type)
            } else {
                try await useCases.createRoutineItem.execute(title: title, type: type)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}

