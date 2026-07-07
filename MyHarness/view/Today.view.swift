import SwiftUI
import UIKit

@MainActor
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    let state: TodayState
    @State private var showsWeekOverview = false

    var body: some View {
        List {
            DateNavigatorView(
                title: state.selectedDateTitle,
                detail: state.selectedDateDetail,
                isWeekOverviewVisible: showsWeekOverview,
                oneShotCount: state.oneShotCount,
                onSettings: {
                    router.presentedSheet = .settings
                },
                onOneShotTasks: {
                    router.push(.oneShotTasks)
                },
                onPrevious: {
                    Task { await state.moveSelectedDate(by: -1) }
                },
                onToday: {
                    Task { await state.selectToday() }
                },
                onNext: {
                    Task { await state.moveSelectedDate(by: 1) }
                },
                onToggleWeekOverview: {
                    showsWeekOverview.toggle()
                }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 4, trailing: 14))

            if showsWeekOverview {
                WeekdayTaskOverviewView(groups: state.weekdayTaskGroups)
                    .listRowSeparator(.hidden)
            }

            if state.routineRows.isEmpty, !state.isLoading {
                ContentUnavailableView(
                    state.oneShotCount > 0 ? "ルーチン項目がありません" : "項目がありません",
                    systemImage: "checklist",
                    description: Text("右下の追加ボタンから作成します。")
                )
                .listRowSeparator(.hidden)
            }

            ForEach(state.routineRows) { row in
                TodayItemRow(
                    row: row,
                    showsMoveHandle: true,
                    onToggle: {
                        Task { await state.toggleCompletion(for: row.id) }
                    }
                )
                .dropDestination(for: String.self) { itemIds, _ in
                    guard
                        let itemId = itemIds.first,
                        let sourceId = UUID(uuidString: itemId)
                    else {
                        return false
                    }
                    Task { await state.moveRow(id: sourceId, before: row.id) }
                    return true
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await state.deleteItem(id: row.id) }
                    } label: {
                        Label("削除", systemImage: "trash")
                    }

                    Button {
                        router.presentedSheet = .editItem(row.item)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onMove { offsets, destination in
                Task { await state.moveRoutineRows(from: offsets, to: destination) }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, 0, for: .scrollContent)
        .overlay {
            if state.isLoading {
                ProgressView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                router.presentedSheet = .addItem
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(.white, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("項目を追加")
            .padding(.trailing, 20)
            .padding(.bottom, floatingButtonBottomPadding)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = state.errorMessage {
                MessageBar(text: error, systemImage: "exclamationmark.triangle")
            } else if let message = state.copiedMessage {
                MessageBar(text: message, systemImage: "checkmark.circle")
            }
        }
        .task {
            await state.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await state.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await state.load() }
        }
    }

    private var floatingButtonBottomPadding: CGFloat {
        state.errorMessage == nil && state.copiedMessage == nil ? 20 : 64
    }
}

private struct TodayItemRow: View {
    let row: TodayItemRowState
    let showsMoveHandle: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(row.isCompleted ? .green : .secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.item.title)
                    .font(.body)
                    .strikethrough(row.isCompleted)
                    .foregroundStyle(row.isCompleted ? .secondary : .primary)
                    .lineLimit(1)

                ScheduleKindMetaView(item: row.item)
            }

            Spacer(minLength: 0)

            if showsMoveHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
                    .draggable(row.id.uuidString)
                    .accessibilityLabel("移動")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.item.title)
        .accessibilityHint("タップして完了状態を切り替え")
        .accessibilityAction {
            onToggle()
        }
    }
}

@MainActor
struct OneShotTasksView: View {
    @Environment(AppRouter.self) private var router
    let state: TodayState

    var body: some View {
        List {
            HStack(spacing: 8) {
                Text(state.selectedDateTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.selectedDateDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)

            if state.oneShotRows.isEmpty, !state.isLoading {
                ContentUnavailableView(
                    "単発タスクはありません",
                    systemImage: "target",
                    description: Text("新規作成で単発を選ぶとここに表示されます。")
                )
                .listRowSeparator(.hidden)
            }

            ForEach(state.oneShotRows) { row in
                TodayItemRow(
                    row: row,
                    showsMoveHandle: false,
                    onToggle: {
                        Task { await state.toggleCompletion(for: row.id) }
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await state.deleteItem(id: row.id) }
                    } label: {
                        Label("削除", systemImage: "trash")
                    }

                    Button {
                        router.presentedSheet = .editItem(row.item)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("単発")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if state.isLoading {
                ProgressView()
            }
        }
        .task {
            await state.load()
        }
    }
}

private struct ScheduleKindMetaView: View {
    let item: RoutineItem

    var body: some View {
        HStack(spacing: 6) {
            if item.scheduleKind == .oneShot {
                Text("単発")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("単発")
            } else {
                Text(item.repeatWeekdaysLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct WeekdayTaskOverviewView: View {
    let groups: [WeekdayTaskGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups) { group in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(group.weekday.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .center)

                    Text(taskSummary(for: group))
                        .font(.caption)
                        .foregroundStyle(group.items.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 20)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("曜日ごとの項目")
    }

    private func taskSummary(for group: WeekdayTaskGroup) -> String {
        let titles = group.items.map(\.title)
        return titles.isEmpty ? "なし" : titles.joined(separator: "、")
    }
}

private struct DateNavigatorView: View {
    let title: String
    let detail: String
    let isWeekOverviewVisible: Bool
    let oneShotCount: Int
    let onSettings: () -> Void
    let onOneShotTasks: () -> Void
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void
    let onToggleWeekOverview: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定")

            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("前の日")

            Button(action: onToday) {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今日へ移動")

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("次の日")

            Button(action: onOneShotTasks) {
                HStack(spacing: 4) {
                    Text("単発")
                    Text("\(oneShotCount)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(oneShotCount > 0 ? .white : .primary)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(
                    oneShotCount > 0 ? Color.black : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(.black.opacity(0.16), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("単発タスク \(oneShotCount)件")

            Button(action: onToggleWeekOverview) {
                Image(systemName: "calendar")
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isWeekOverviewVisible ? .white : .primary)
                    .background(
                        isWeekOverviewVisible ? Color.black : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWeekOverviewVisible ? "週表示を閉じる" : "週表示を開く")
        }
        .padding(.vertical, 4)
    }
}

private struct MessageBar: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }
}

#Preview {
    NavigationStack {
        TodayView(state: TodayState(useCases: try! AppDependencies.preview().useCases))
            .environment(AppRouter())
    }
}
