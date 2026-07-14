import Foundation
import Observation

enum RoutineRepeatPreset: String, CaseIterable, Hashable, Identifiable {
    case everyDay
    case weekdays
    case weekends
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDay:
            return "毎日"
        case .weekdays:
            return "平日"
        case .weekends:
            return "土日"
        case .custom:
            return "カスタム"
        }
    }
}

@MainActor
@Observable
final class ItemEditorState {
    var title: String
    var scheduleKind: RoutineScheduleKind
    var repeatPreset: RoutineRepeatPreset
    var customRepeatWeekdays: Set<RoutineWeekday>
    var errorMessage: String?
    var isSaving = false

    private var editingItem: RoutineItem?
    private var lastSavedTitle: String
    private var lastSavedScheduleKind: RoutineScheduleKind
    private var lastSavedRepeatWeekdays: Set<RoutineWeekday>
    private let useCases: AppUseCases

    init(useCases: AppUseCases, editingItem: RoutineItem? = nil) {
        self.useCases = useCases
        self.editingItem = editingItem
        title = editingItem?.title ?? ""
        lastSavedTitle = editingItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scheduleKind = editingItem?.scheduleKind ?? .routine
        lastSavedScheduleKind = editingItem?.scheduleKind ?? .routine
        let savedWeekdays = editingItem?.repeatWeekdays ?? RoutineWeekday.weekends
        lastSavedRepeatWeekdays = savedWeekdays

        if savedWeekdays == RoutineWeekday.everyDay {
            repeatPreset = .everyDay
            customRepeatWeekdays = RoutineWeekday.everyDay
        } else if savedWeekdays == RoutineWeekday.weekdays {
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (scheduleKind == .oneShot || !selectedRepeatWeekdays.isEmpty)
    }

    var canSubmitWithoutSaving: Bool {
        isValid && editingItem != nil && !hasUnsavedChanges
    }

    private var hasUnsavedChanges: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle != lastSavedTitle
            || scheduleKind != lastSavedScheduleKind
            || selectedRepeatWeekdays != lastSavedRepeatWeekdays
    }

    var selectedRepeatWeekdays: Set<RoutineWeekday> {
        guard scheduleKind == .routine else {
            return RoutineWeekday.everyDay
        }

        switch repeatPreset {
        case .everyDay:
            return RoutineWeekday.everyDay
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
                try await useCases.updateRoutineItem.execute(
                    id: editingItem.id,
                    title: trimmedTitle,
                    scheduleKind: scheduleKind,
                    repeatWeekdays: repeatWeekdays
                )
                editingItem.title = trimmedTitle
                editingItem.scheduleKind = scheduleKind
                editingItem.repeatWeekdays = repeatWeekdays
                self.editingItem = editingItem
            } else {
                editingItem = try await useCases.createRoutineItem.execute(
                    title: trimmedTitle,
                    scheduleKind: scheduleKind,
                    repeatWeekdays: repeatWeekdays
                )
            }
            lastSavedTitle = trimmedTitle
            lastSavedScheduleKind = scheduleKind
            lastSavedRepeatWeekdays = repeatWeekdays
            errorMessage = nil
            return true
        } catch {
            errorMessage = "自動保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }
}
