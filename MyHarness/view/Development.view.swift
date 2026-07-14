import SwiftUI

@MainActor
struct DevelopmentView: View {
    let state: ProductOpsState
    let actionInboxState: ActionInboxState
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .environment(\.editMode, $editMode)
        .navigationTitle("開発")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canReorder {
                    EditButton()
                }
            }
        }
        .refreshable {
            await state.loadDevelopmentTasksIfPossible()
        }
        .task {
            await state.loadDevelopmentTasksIfPossible()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let configurationErrorMessage = state.configurationErrorMessage {
            ProductOpsAccessPlaceholder(
                title: "API設定が未完了",
                systemImage: "gearshape.2",
                message: configurationErrorMessage
            )
            .listRowSeparator(.hidden)
        } else if !state.isSignedIn {
            ProductOpsAccessPlaceholder(
                title: "ログインが必要です",
                systemImage: "person.crop.circle",
                message: "おすすめタブのメニューからログインしてください。"
            )
            .listRowSeparator(.hidden)
        } else {
            Section {
                switch state.developmentTasksState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("バックログを読み込めません", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                    .listRowSeparator(.hidden)
                case .loaded(let tasks):
                    if tasks.isEmpty {
                        Text("開発バックログはありません")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tasks) { task in
                            DevelopmentTaskRow(
                                task: task,
                                isUpdating: state.isUpdatingDevelopmentTask(id: task.id),
                                isStartingCodex: state.isStartingCodex(taskId: task.id),
                                onStatus: { status in
                                    Task { await state.updateDevelopmentTask(task, status: status) }
                                },
                                onPriority: { priority in
                                    Task { await state.updateDevelopmentTask(task, priority: priority) }
                                },
                                onExecutor: { executor in
                                    Task { await state.updateDevelopmentTask(task, assignedExecutor: executor) }
                                },
                                onStartCodex: {
                                    Task {
                                        if await state.startCodex(task: task) != nil {
                                            await actionInboxState.loadIfPossible()
                                        }
                                    }
                                }
                            )
                        }
                        .onMove { offsets, destination in
                            Task { await state.reorderDevelopmentTasks(fromOffsets: offsets, toOffset: destination) }
                        }
                    }
                }
            } header: {
                Text("バックログ")
            }
        }
    }

    private var canReorder: Bool {
        state.developmentTasks.count > 1
    }
}

private struct DevelopmentTaskRow: View {
    let task: DevelopmentTask
    let isUpdating: Bool
    let isStartingCodex: Bool
    let onStatus: (String) -> Void
    let onPriority: (String) -> Void
    let onExecutor: (String) -> Void
    let onStartCodex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(task.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("#\(task.rank)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            HStack(spacing: 6) {
                ProductOpsTokenView(ProductOpsDisplay.statusLabel(task.status), systemImage: "circle.dashed")
                ProductOpsTokenView(ProductOpsDisplay.priorityLabel(task.priority), systemImage: "flag")
                ProductOpsTokenView(task.assignedExecutor ?? "未割当", systemImage: "person")
            }

            Text(repositoryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                statusMenu
                priorityMenu
                executorMenu

                Spacer(minLength: 0)

                Button(action: onStartCodex) {
                    if isStartingCodex {
                        Label("開始中", systemImage: "hourglass")
                    } else {
                        Label("Codex実装", systemImage: "terminal")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStartingCodex || isUpdating)
            }
            .font(.caption.weight(.semibold))
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .disabled(isUpdating)
    }

    private var repositoryText: String {
        task.repositoryIds.isEmpty ? "repository未設定" : task.repositoryIds.joined(separator: ", ")
    }

    private var statusMenu: some View {
        Menu {
            ForEach(ProductOpsDisplay.statusOptions, id: \.self) { status in
                Button(ProductOpsDisplay.statusLabel(status)) {
                    onStatus(status)
                }
            }
        } label: {
            Label("状態", systemImage: "circle.dashed")
        }
        .buttonStyle(.bordered)
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(ProductOpsDisplay.priorityOptions, id: \.self) { priority in
                Button(ProductOpsDisplay.priorityLabel(priority)) {
                    onPriority(priority)
                }
            }
        } label: {
            Label("優先度", systemImage: "flag")
        }
        .buttonStyle(.bordered)
    }

    private var executorMenu: some View {
        Menu {
            ForEach(ProductOpsDisplay.executorOptions, id: \.self) { executor in
                Button(executor) {
                    onExecutor(executor)
                }
            }
        } label: {
            Label("担当", systemImage: "person")
        }
        .buttonStyle(.bordered)
    }
}
