import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    let state: TodayState
    @State private var editMode: EditMode = .inactive

    private var isEditing: Bool {
        editMode.isEditing
    }

    var body: some View {
        List {
            if state.rows.isEmpty, !state.isLoading {
                ContentUnavailableView(
                    "項目がありません",
                    systemImage: "checklist",
                    description: Text("右上の追加ボタンから作成します。")
                )
                .listRowSeparator(.hidden)
            }

            ForEach(state.rows) { row in
                TodayItemRow(
                    row: row,
                    isEditing: isEditing,
                    onToggle: {
                        Task { await state.toggleCompletion(for: row.id) }
                    },
                    onEdit: {
                        router.presentedSheet = .editItem(row.item)
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
            .onMove { offsets, destination in
                Task { await state.moveRows(from: offsets, to: destination) }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .environment(\.editMode, $editMode)
        .navigationTitle("my harness")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isEditing ? "完了" : "編集") {
                    withAnimation(.snappy) {
                        editMode = isEditing ? .inactive : .active
                    }
                }
                .disabled(state.rows.isEmpty)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        if let text = await state.buildAndCopyWeeklyExport() {
                            router.presentedSheet = .weeklyExport(text)
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("今週分をコピー")

                Button {
                    router.presentedSheet = .settings
                } label: {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("通知設定")

                Button {
                    router.presentedSheet = .addItem
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("項目を追加")
            }
        }
        .overlay {
            if state.isLoading {
                ProgressView()
            }
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
    }
}

private struct TodayItemRow: View {
    let row: TodayItemRowState
    let isEditing: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

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

                if row.item.repeatWeekdays != RoutineWeekday.everyDay {
                    Text(row.item.repeatWeekdaysLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                onEdit()
            } else {
                onToggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.item.title)
        .accessibilityHint(isEditing ? "タップして編集" : "タップして完了状態を切り替え")
        .accessibilityAction {
            if isEditing {
                onEdit()
            } else {
                onToggle()
            }
        }
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
