import SwiftUI

@MainActor
struct NextActionsView: View {
    @Environment(AppRouter.self) private var router
    let actionInboxState: ActionInboxState
    let productOpsState: ProductOpsState
    @State private var presentedSheet: NextActionsSheet?

    private enum NextActionsSheet: Identifiable {
        case needMemo

        var id: String {
            switch self {
            case .needMemo:
                return "needMemo"
            }
        }
    }

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 46)
        .navigationTitle("次にやる")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menu
            }
        }
        .refreshable {
            await loadAllIfPossible()
        }
        .task {
            await loadAllIfPossible()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = actionInboxState.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            } else if let message = productOpsState.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .needMemo:
                NavigationStack {
                    NextActionNeedMemoSheet(state: productOpsState)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let configurationErrorMessage = productOpsState.configurationErrorMessage ?? actionInboxState.configurationErrorMessage {
            ProductOpsAccessPlaceholder(
                title: "API設定が未完了",
                systemImage: "gearshape.2",
                message: configurationErrorMessage
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        } else if !actionInboxState.isSignedIn {
            ProductOpsAccessPlaceholder(
                title: "ログインが必要です",
                systemImage: "person.crop.circle",
                message: "AIの次の操作を確認するにはログインしてください。"
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            ActionInboxLoginButton(
                isSigningIn: actionInboxState.isSigningIn,
                action: {
                    Task { await signIn() }
                }
            )
            .listRowSeparator(.hidden)
        } else {
            switch productOpsState.nextActionsState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            case .failed(let message):
                ContentUnavailableView {
                    Label("次にやることを読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let payload):
                nextActionsContent(payload)
            }
        }
    }

    @ViewBuilder
    private func nextActionsContent(_ payload: NextActionsPayload) -> some View {
        let recommended = payload.items.first { $0.status == "todo" || $0.status == "blocked" }
        let remaining = payload.items.filter { $0.id != recommended?.id }
        let todoItems = remaining.filter { $0.status == "todo" || $0.status == "blocked" }
        let runningItems = remaining.filter { $0.status == "running" }
        let laterItems = remaining.filter { $0.status == "later" }

        if let recommended {
            Section("おすすめ") {
                RecommendedNextActionCard(
                    item: recommended,
                    isWorking: isWorking(recommended),
                    onOpen: { open(recommended) },
                    onPrimary: { perform(recommended.primaryAction, item: recommended) },
                    onSecondary: { command in perform(command, item: recommended) }
                )
                .listRowSeparator(.hidden)
            }
        }

        Section("やること") {
            if todoItems.isEmpty {
                emptyRow("判断待ちはありません")
            } else {
                ForEach(todoItems) { item in
                    NextActionRow(
                        item: item,
                        isWorking: isWorking(item),
                        onOpen: { open(item) },
                        onPrimary: { perform(item.primaryAction, item: item) },
                        onSecondary: { command in perform(command, item: item) }
                    )
                }
            }
        }

        Section("進行中") {
            if runningItems.isEmpty {
                emptyRow("進行中はありません")
            } else {
                ForEach(runningItems) { item in
                    NextActionRow(
                        item: item,
                        isWorking: isWorking(item),
                        onOpen: { open(item) },
                        onPrimary: { perform(item.primaryAction, item: item) },
                        onSecondary: { command in perform(command, item: item) }
                    )
                }
            }
        }

        Section("あとで") {
            if laterItems.isEmpty {
                emptyRow("あとで見る項目はありません")
            } else {
                ForEach(laterItems) { item in
                    NextActionRow(
                        item: item,
                        isWorking: isWorking(item),
                        onOpen: { open(item) },
                        onPrimary: { perform(item.primaryAction, item: item) },
                        onSecondary: { command in perform(command, item: item) }
                    )
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                presentedSheet = .needMemo
            } label: {
                Label("ニーズ候補をメモ", systemImage: "square.and.pencil")
            }

            Button {
                router.push(.needList)
            } label: {
                Label("ニーズ一覧", systemImage: "lightbulb")
            }

            Button {
                router.push(.developmentBacklog)
            } label: {
                Label("開発バックログ", systemImage: "hammer")
            }

            Button {
                router.push(.projectPolicy)
            } label: {
                Label("プロダクト方針", systemImage: "scope")
            }

            Button {
                router.push(.actionHistory)
            } label: {
                Label("実行履歴", systemImage: "clock.arrow.circlepath")
            }

            Button {
                router.push(.completedActions)
            } label: {
                Label("完了した項目", systemImage: "checkmark.seal")
            }

            Divider()

            if actionInboxState.isSignedIn {
                Button {
                    Task { await actionInboxState.registerForPushNotifications() }
                } label: {
                    Label("通知を有効化", systemImage: "bell.badge")
                }
                .disabled(actionInboxState.isRegisteringPush)

                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    Label("ログイン", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!actionInboxState.isConfigured || actionInboxState.isSigningIn)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("操作メニュー")
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func loadAllIfPossible() async {
        await productOpsState.loadNextActionsIfPossible()
        await actionInboxState.loadIfPossible()
    }

    private func signIn() async {
        await actionInboxState.signIn()
        await productOpsState.loadNextActionsIfPossible()
    }

    private func signOut() async {
        await actionInboxState.signOut()
        productOpsState.reset()
    }

    private func isWorking(_ item: NextActionItem) -> Bool {
        actionInboxState.isPostingDecision ||
            productOpsState.isMutatingNeed(id: item.sourceId) ||
            productOpsState.isStartingCodex(taskId: item.sourceId)
    }

    private func open(_ item: NextActionItem) {
        switch item.sourceType {
        case "action_suggestion":
            router.push(.actionSuggestionDetail(id: item.sourceId))
        case "need":
            router.push(.need(id: item.sourceId))
        case "development_task":
            router.push(.developmentBacklog)
        default:
            break
        }
    }

    private func perform(_ command: NextActionCommand, item: NextActionItem) {
        switch command.action {
        case "open_detail":
            open(item)
        case "pursue_need":
            Task {
                if await productOpsState.pursueNeed(id: item.sourceId) != nil {
                    await actionInboxState.loadIfPossible()
                }
            }
        case "hold_need":
            Task { await productOpsState.holdNeed(id: item.sourceId, decisionNote: nil) }
        case "reject_need":
            Task { await productOpsState.rejectNeed(id: item.sourceId, decisionNote: nil) }
        case "approve_suggestion":
            Task {
                await actionInboxState.decideItem(
                    id: item.sourceId,
                    version: item.sourceVersion,
                    hostId: item.hostId,
                    decision: .approved,
                    decisionNote: nil
                )
                await productOpsState.loadNextActionsIfPossible()
            }
        case "later_suggestion":
            Task {
                await actionInboxState.decideItem(
                    id: item.sourceId,
                    version: item.sourceVersion,
                    hostId: item.hostId,
                    decision: .later,
                    decisionNote: nil
                )
                await productOpsState.loadNextActionsIfPossible()
            }
        case "reject_suggestion":
            Task {
                await actionInboxState.decideItem(
                    id: item.sourceId,
                    version: item.sourceVersion,
                    hostId: item.hostId,
                    decision: .rejected,
                    decisionNote: nil
                )
                await productOpsState.loadNextActionsIfPossible()
            }
        case "start_development":
            Task {
                if await productOpsState.startCodex(taskId: item.sourceId) != nil {
                    await actionInboxState.loadIfPossible()
                }
            }
        default:
            open(item)
        }
    }
}

private struct RecommendedNextActionCard: View {
    let item: NextActionItem
    let isWorking: Bool
    let onOpen: () -> Void
    let onPrimary: () -> Void
    let onSecondary: (NextActionCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ProductOpsTokenView(NextActionDisplay.kindLabel(item.kind), systemImage: NextActionDisplay.kindIcon(item.kind))
                        ProductOpsTokenView(NextActionDisplay.statusLabel(item.status), systemImage: NextActionDisplay.statusIcon(item.status))
                    }
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onPrimary) {
                    Label(item.primaryAction.label, systemImage: NextActionDisplay.commandIcon(item.primaryAction.action))
                }
                .buttonStyle(.borderedProminent)

                ForEach(item.secondaryActions.prefix(2), id: \.action) { command in
                    Button {
                        onSecondary(command)
                    } label: {
                        Text(command.label)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption.weight(.semibold))
            .controlSize(.small)
            .disabled(isWorking)
        }
        .padding(.vertical, 8)
    }
}

private struct NextActionRow: View {
    let item: NextActionItem
    let isWorking: Bool
    let onOpen: () -> Void
    let onPrimary: () -> Void
    let onSecondary: (NextActionCommand) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: NextActionDisplay.statusIcon(item.status))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NextActionDisplay.statusTint(item.status))
                .frame(width: 22)
                .padding(.top, 4)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ProductOpsTokenView(NextActionDisplay.kindLabel(item.kind))
                        ProductOpsTokenView(NextActionDisplay.statusLabel(item.status))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Button(action: onPrimary) {
                    Text(item.primaryAction.label)
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if !item.secondaryActions.isEmpty {
                    Menu {
                        ForEach(item.secondaryActions, id: \.action) { command in
                            Button(command.label) {
                                onSecondary(command)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .disabled(isWorking)
        }
        .padding(.vertical, 6)
    }
}

private struct NextActionNeedMemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var memo = ""

    var body: some View {
        Form {
            Section("メモ") {
                TextEditor(text: $memo)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if memo.isEmpty {
                            Text("拾った困りごと、仮説、会話メモ")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                    }
            }
        }
        .navigationTitle("ニーズ候補をメモ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if state.isPostingMemo {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(state.isPostingMemo || memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() async {
        if await state.createNeedFromMemo(memo) != nil {
            dismiss()
        }
    }
}

private enum NextActionDisplay {
    static func kindLabel(_ value: String) -> String {
        switch value {
        case "need_decision":
            return "ニーズ"
        case "action_approval":
            return "実行"
        case "result_review":
            return "結果"
        case "development_start":
            return "開発"
        case "development_review":
            return "開発確認"
        default:
            return value
        }
    }

    static func kindIcon(_ value: String) -> String {
        switch value {
        case "need_decision":
            return "lightbulb"
        case "development_start", "development_review":
            return "hammer"
        case "result_review":
            return "doc.text.magnifyingglass"
        default:
            return "checkmark.circle"
        }
    }

    static func statusLabel(_ value: String) -> String {
        switch value {
        case "todo":
            return "やること"
        case "running":
            return "進行中"
        case "later":
            return "あとで"
        case "blocked":
            return "要確認"
        default:
            return value
        }
    }

    static func statusIcon(_ value: String) -> String {
        switch value {
        case "running":
            return "circle.dashed"
        case "later":
            return "clock"
        case "blocked":
            return "exclamationmark.circle"
        default:
            return "circle"
        }
    }

    static func statusTint(_ value: String) -> Color {
        switch value {
        case "running":
            return .blue
        case "later":
            return .secondary
        case "blocked":
            return .orange
        default:
            return .accentColor
        }
    }

    static func commandIcon(_ value: String) -> String {
        switch value {
        case "pursue_need", "approve_suggestion":
            return "checkmark.circle"
        case "start_development":
            return "terminal"
        case "hold_need", "later_suggestion":
            return "clock"
        case "reject_need", "reject_suggestion":
            return "xmark.circle"
        default:
            return "arrow.right.circle"
        }
    }
}
