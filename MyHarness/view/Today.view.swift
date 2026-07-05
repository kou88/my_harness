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
                    },
                    onLogChange: { text in
                        Task { await state.setLogText(text, for: row.id) }
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
        .navigationTitle("my harness")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
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
    let onToggle: () -> Void
    let onLogChange: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isCompleted ? .green : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isCompleted ? "未完了にする" : "完了にする")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.item.title)
                        .font(.body)
                        .strikethrough(row.isCompleted)
                        .foregroundStyle(row.isCompleted ? .secondary : .primary)
                        .lineLimit(1)

                    if row.item.type == .checkLog {
                        Text("log")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if row.item.type == .checkLog {
                    TextField(
                        "1行ログ",
                        text: Binding(
                            get: { row.logText },
                            set: onLogChange
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

