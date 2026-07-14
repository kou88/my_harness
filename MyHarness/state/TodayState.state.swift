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
    var weekdayTaskGroups: [WeekdayTaskGroup] = []
    var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    var isLoading = false
    var errorMessage: String?
    var copiedMessage: String?
    var showsCompletedOneShotRows: Bool

    private let useCases: AppUseCases
    private var followsSystemToday = true
    private var calendar: Calendar {
        Calendar.autoupdatingCurrent
    }

    init(useCases: AppUseCases) {
        self.useCases = useCases
        showsCompletedOneShotRows = false
    }

    var routineRows: [TodayItemRowState] {
        rows.filter { $0.item.scheduleKind == .routine }
    }

    var oneShotRows: [TodayItemRowState] {
        rows.filter { $0.item.scheduleKind == .oneShot }
    }

    var visibleOneShotRows: [TodayItemRowState] {
        if showsCompletedOneShotRows {
            return oneShotRows
        }

        return oneShotRows.filter { !$0.isCompleted }
    }

    var oneShotCount: Int {
        oneShotRows.count
    }

    var hiddenCompletedOneShotCount: Int {
        oneShotRows.filter(\.isCompleted).count
    }

    func load() async {
        syncSelectedDateWithSystemTodayIfNeeded()
        isLoading = true
        defer { isLoading = false }

        do {
            try await useCases.syncWidgetUpdates.execute()
            rows = try await rowStates(for: selectedDate)
            weekdayTaskGroups = try await useCases.loadWeekdayTaskGroups.execute()
            try await publishWidgetSnapshotForToday()
            errorMessage = nil
        } catch {
            errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    var selectedDateTitle: String {
        let components = calendar.dateComponents([.month, .day, .weekday], from: selectedDate)
        let weekday = RoutineWeekday(rawValue: components.weekday ?? 1)?.shortLabel ?? "日"
        return "\(components.month ?? 0)/\(components.day ?? 0)(\(weekday))"
    }

    var selectedDateDetail: String {
        if calendar.isDateInToday(selectedDate) {
            return "今日"
        }
        if calendar.isDateInYesterday(selectedDate) {
            return "昨日"
        }
        if calendar.isDateInTomorrow(selectedDate) {
            return "明日"
        }

        let components = calendar.dateComponents([.year], from: selectedDate)
        return "\(components.year ?? 0)"
    }

    func moveSelectedDate(by dayOffset: Int) async {
        followsSystemToday = false
        selectedDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: dayOffset, to: selectedDate) ?? selectedDate
        )
        await load()
    }

    func selectToday() async {
        followsSystemToday = true
        selectedDate = calendar.startOfDay(for: Date())
        await load()
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

    func moveRoutineRows(from offsets: IndexSet, to destination: Int) async {
        let reorderedRoutineRows = reordered(routineRows, from: offsets, to: destination)
        rows = oneShotRows + reorderedRoutineRows

        do {
            try await useCases.reorderRoutineItems.execute(ids: rows.map(\.id))
            weekdayTaskGroups = try await useCases.loadWeekdayTaskGroups.execute()
            errorMessage = nil
        } catch {
            errorMessage = "並べ替えに失敗しました: \(error.localizedDescription)"
            await load()
        }
    }

    func moveRow(id sourceId: UUID, before targetId: UUID) async {
        guard
            sourceId != targetId,
            let sourceIndex = routineRows.firstIndex(where: { $0.id == sourceId })
        else {
            return
        }

        var nextRows = routineRows
        let moving = nextRows.remove(at: sourceIndex)
        let targetIndex = nextRows.firstIndex(where: { $0.id == targetId }) ?? nextRows.count
        nextRows.insert(moving, at: targetIndex)
        rows = oneShotRows + nextRows

        do {
            try await useCases.reorderRoutineItems.execute(ids: rows.map(\.id))
            weekdayTaskGroups = try await useCases.loadWeekdayTaskGroups.execute()
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

    func toggleCompletedOneShotVisibility() {
        showsCompletedOneShotRows.toggle()
    }

    func copyVisibleOneShotTasksMarkdown() {
        let text = oneShotTasksMarkdown(rows: visibleOneShotRows)
        useCases.copyText.execute(text)
        copiedMessage = "単発タスクをコピーしました"
        errorMessage = nil
    }

    private func persistRow(_ row: TodayItemRowState) async {
        do {
            try await useCases.updateDayEntry.execute(
                itemId: row.id,
                date: selectedDate,
                isCompleted: row.isCompleted
            )
            try await publishWidgetSnapshotForToday()
            errorMessage = nil
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func rowStates(for date: Date) async throws -> [TodayItemRowState] {
        pinOneShotRows(try await useCases.loadToday.execute(date: date).map { snapshot in
            TodayItemRowState(
                item: snapshot.item,
                isCompleted: snapshot.entry?.isCompleted ?? false
            )
        })
    }

    private func syncSelectedDateWithSystemTodayIfNeeded() {
        guard followsSystemToday else { return }
        selectedDate = calendar.startOfDay(for: Date())
    }

    private func publishWidgetSnapshotForToday() async throws {
        let today = Date()
        let todayRows = calendar.isDate(selectedDate, inSameDayAs: today) ? rows : try await rowStates(for: today)
        let routineRows = todayRows.filter { $0.item.scheduleKind == .routine }
        let oneShotCount = todayRows.filter { $0.item.scheduleKind == .oneShot }.count
        try await useCases.publishWidgetSnapshot.execute(
            rows: routineRows.map { row in
                WidgetItemSnapshot(
                    id: row.item.id,
                    title: row.item.title,
                    sortOrder: row.item.sortOrder,
                    isCompleted: row.isCompleted
                )
            },
            oneShotCount: oneShotCount
        )
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

    private func pinOneShotRows(_ values: [TodayItemRowState]) -> [TodayItemRowState] {
        values.filter { $0.item.scheduleKind == .oneShot }
            + values.filter { $0.item.scheduleKind == .routine }
    }

    private func oneShotTasksMarkdown(rows: [TodayItemRowState]) -> String {
        let lines = rows.map { row in
            let mark = row.isCompleted ? "x" : " "
            return "- [\(mark)] \(sanitizedMarkdownTitle(row.item.title))"
        }

        let body = lines.isEmpty ? "- なし" : lines.joined(separator: "\n")
        return "# 単発タスク\n\n\(body)"
    }

    private func sanitizedMarkdownTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
