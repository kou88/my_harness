import Foundation
import Observation

enum RoutineRepeatPreset: String, CaseIterable, Hashable, Identifiable {
    case weekdays
    case weekends
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekdays:
            return "平日のみ"
        case .weekends:
            return "土日のみ"
        case .custom:
            return "カスタム"
        }
    }
}

@MainActor
@Observable
final class ItemEditorState {
    var title: String
    var repeatPreset: RoutineRepeatPreset
    var customRepeatWeekdays: Set<RoutineWeekday>
    var errorMessage: String?
    var isSaving = false

    private var editingItem: RoutineItem?
    private var lastSavedTitle: String
    private var lastSavedRepeatWeekdays: Set<RoutineWeekday>
    private let useCases: AppUseCases

    init(useCases: AppUseCases, editingItem: RoutineItem? = nil) {
        self.useCases = useCases
        self.editingItem = editingItem
        title = editingItem?.title ?? ""
        lastSavedTitle = editingItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let savedWeekdays = editingItem?.repeatWeekdays ?? RoutineWeekday.weekends
        lastSavedRepeatWeekdays = savedWeekdays

        if savedWeekdays == RoutineWeekday.weekdays {
            repeatPreset = .weekdays
            customRepeatWeekdays = RoutineWeekday.everyDay
        } else if savedWeekdays == RoutineWeekday.weekends {
            repeatPreset = .weekends
            customRepeatWeekdays = RoutineWeekday.everyDay
        } else {
            repeatPreset = .custom
            customRepeatWeekdays = savedWeekdays
        }
    }

    var navigationTitle: String {
        editingItem == nil ? "項目を追加" : "項目を編集"
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedRepeatWeekdays.isEmpty
    }

    var canSubmitWithoutSaving: Bool {
        isValid && editingItem != nil && !hasUnsavedChanges
    }

    private var hasUnsavedChanges: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle != lastSavedTitle || selectedRepeatWeekdays != lastSavedRepeatWeekdays
    }

    var selectedRepeatWeekdays: Set<RoutineWeekday> {
        switch repeatPreset {
        case .weekdays:
            return RoutineWeekday.weekdays
        case .weekends:
            return RoutineWeekday.weekends
        case .custom:
            return customRepeatWeekdays
        }
    }

    func toggleWeekday(_ weekday: RoutineWeekday) {
        repeatPreset = .custom
        if customRepeatWeekdays.contains(weekday) {
            customRepeatWeekdays.remove(weekday)
        } else {
            customRepeatWeekdays.insert(weekday)
        }
    }

    func autosaveIfNeeded() async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatWeekdays = selectedRepeatWeekdays
        guard !trimmedTitle.isEmpty, !repeatWeekdays.isEmpty else {
            return false
        }
        guard hasUnsavedChanges else {
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if var editingItem {
                try await useCases.updateRoutineItem.execute(id: editingItem.id, title: trimmedTitle, repeatWeekdays: repeatWeekdays)
                editingItem.title = trimmedTitle
                editingItem.repeatWeekdays = repeatWeekdays
                self.editingItem = editingItem
            } else {
                editingItem = try await useCases.createRoutineItem.execute(title: trimmedTitle, repeatWeekdays: repeatWeekdays)
            }
            lastSavedTitle = trimmedTitle
            lastSavedRepeatWeekdays = repeatWeekdays
            errorMessage = nil
            return true
        } catch {
            errorMessage = "自動保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}
