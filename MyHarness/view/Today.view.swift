import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    let state: TodayState

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
                Task { await state.moveRows(from: offsets, to: destination) }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    router.presentedSheet = .settings
                } label: {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("通知設定")
            }
        }
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
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.green, in: Circle())
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
    }

    private var floatingButtonBottomPadding: CGFloat {
        state.errorMessage == nil && state.copiedMessage == nil ? 20 : 64
    }
}

private struct TodayItemRow: View {
    let row: TodayItemRowState
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

                if row.item.repeatWeekdays != RoutineWeekday.everyDay {
                    Text(row.item.repeatWeekdaysLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .draggable(row.id.uuidString)
                .accessibilityLabel("移動")
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
