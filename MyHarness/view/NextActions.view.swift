import SwiftUI

private struct PendingVentureProposalFeedback: Identifiable, Hashable {
    var item: VentureDecisionInboxItem
    var decision: VentureDecision

    var id: String {
        "\(item.proposalId)-\(decision.rawValue)"
    }
}

@MainActor
struct NextActionsView: View {
    @Environment(AppRouter.self) private var router
    let actionInboxState: ActionInboxState
    let productOpsState: ProductOpsState
    @State private var presentedSheet: NextActionsSheet?
    @State private var deferredSheet: NextActionsSheet?

    private enum NextActionsSheet: Identifiable {
        case directMissionRequest
        case needMemo
        case proposalFeedback(PendingVentureProposalFeedback)
        case proposalDetail(proposalId: String, decisionItem: VentureDecisionInboxItem?)
        case missionDetail(missionId: String, kindLabel: String, requestedAction: String?)
        case policyRevision(missionId: String)
        case alertDetail(VentureMonitoringAlertItem)

        var id: String {
            switch self {
            case .directMissionRequest:
                return "directMissionRequest"
            case .needMemo:
                return "needMemo"
            case .proposalFeedback(let feedback):
                return feedback.id
            case .proposalDetail(let proposalId, _):
                return "proposal-\(proposalId)"
            case .missionDetail(let missionId, _, let requestedAction):
                return "mission-\(missionId)-\(requestedAction ?? "detail")"
            case .policyRevision(let missionId):
                return "policy-revision-\(missionId)"
            case .alertDetail(let item):
                return "alert-\(item.id)"
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
            await presentPendingDeepLink(refreshBeforePresentation: false)
        }
        .onChange(of: router.pendingProductOpsDeepLink) { _, destination in
            guard destination != nil else { return }
            Task {
                await presentPendingDeepLink(refreshBeforePresentation: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = actionInboxState.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            } else if let message = productOpsState.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
        .sheet(item: $presentedSheet, onDismiss: presentDeferredSheetIfNeeded) { sheet in
            switch sheet {
            case .directMissionRequest:
                DirectMissionRequestSheet(state: productOpsState)
            case .needMemo:
                NavigationStack {
                    NextActionNeedMemoSheet(state: productOpsState)
                }
            case .proposalFeedback(let feedback):
                VentureProposalFeedbackSheet(
                    state: productOpsState,
                    pending: feedback
                )
            case .proposalDetail(let proposalId, let decisionItem):
                VentureProposalDetailSheet(
                    state: productOpsState,
                    proposalId: proposalId,
                    decisionItem: decisionItem,
                    onApprove: { item in decide(item, .approved) },
                    onLater: { item in presentProposalFeedback(item, decision: .deferred) },
                    onReject: { item in presentProposalFeedback(item, decision: .rejected) }
                )
            case .missionDetail(let missionId, let kindLabel, let requestedAction):
                VentureMissionDetailSheet(
                    state: productOpsState,
                    missionId: missionId,
                    kindLabel: kindLabel,
                    requestedAction: requestedAction
                )
            case .policyRevision(let missionId):
                VenturePolicyRevisionLoaderView(state: productOpsState, missionId: missionId)
            case .alertDetail(let item):
                VentureMonitoringAlertDetailSheet(
                    state: productOpsState,
                    item: item
                )
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
            switch productOpsState.decisionInboxState {
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
                ventureDecisionContent(payload)
            }
        }
    }

    @ViewBuilder
    private func ventureDecisionContent(_ payload: VentureDecisionInboxPayload) -> some View {
        let recommendations = payload.items
        let missionItems = productOpsState.missionSummaryItems
        let monitoringAlertItems = productOpsState.monitoringAlertItems
        let reviewMissions = missionItems.filter { $0.status == "awaiting_review" || $0.status == "failed" }
        let todoMissions = missionItems.filter { $0.status == "queued" }
        let runningMissions = missionItems.filter { ["dispatching", "running"].contains($0.status) }

        if let message = payload.recommendationStatusMessage {
            Section {
                ProductOpsMessageBar(
                    text: message,
                    systemImage: payload.recommendationStatus == "failed" ? "exclamationmark.triangle" : "clock"
                )
                .listRowSeparator(.hidden)
            }
        }

        if let recommendation = recommendations.first {
            Section("今決めること") {
                if let agenda = payload.agenda {
                    decisionAgendaSummary(agenda, item: recommendation)
                } else {
                    ProductOpsMessageBar(
                        text: "提案に判断論点がありません。データを再生成してください。",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }

            Section("次の一手") {
                proposalCompactRow(recommendation)
            }
        } else if payload.recommendationStatus == "idle" {
            Section("今決めること") {
                ContentUnavailableView {
                    Label("新しい判断材料を待っています", systemImage: "hourglass")
                } description: {
                    Text(payload.idleStatusMessage)
                }
                .listRowSeparator(.hidden)
            }
        }

        Section("やること  \(todoMissions.count)") {
            if todoMissions.isEmpty {
                emptyRow("開始待ちはありません")
            } else {
                ForEach(todoMissions) { item in
                    missionCompactRow(item)
                }
            }
        }

        Section("進行中  \(runningMissions.count)") {
            if runningMissions.isEmpty {
                emptyRow("進行中はありません")
            } else {
                ForEach(runningMissions) { item in
                    missionCompactRow(item)
                }
            }
        }

        let reviewCount = monitoringAlertItems.count + reviewMissions.count
        Section("確認待ち  \(reviewCount)") {
            if reviewCount == 0 {
                emptyRow("確認待ちはありません")
            } else {
                ForEach(monitoringAlertItems) { item in
                    CompactNextActionRow(
                        title: item.alert.detectedIssue,
                        contextLabel: "確認待ち",
                        isWorking: productOpsState.isMutatingMission(id: item.alert.missionId),
                        onOpen: { presentedSheet = .alertDetail(item) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await productOpsState.dismissMonitoringAlert(item) }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .disabled(productOpsState.isMutatingMission(id: item.alert.missionId))
                    }
                }
                ForEach(reviewMissions) { item in
                    missionCompactRow(item)
                }
            }
        }

        if productOpsState.nextMissionCursor != nil {
            Section {
                Button {
                    Task { await productOpsState.loadMoreMissionItems() }
                } label: {
                    HStack {
                        Spacer()
                        if productOpsState.isLoadingMoreMissionItems {
                            ProgressView()
                        } else {
                            Label("さらに表示", systemImage: "chevron.down")
                        }
                        Spacer()
                    }
                }
                .disabled(productOpsState.isLoadingMoreMissionItems)
            }
        }

        if case .failed(let message) = productOpsState.monitoringAlertsState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

        if case .failed(let message) = productOpsState.missionProgressState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

    }

    private func proposalCompactRow(_ item: VentureDecisionInboxItem) -> some View {
        let isWorking = productOpsState.isMutatingVentureProposal(id: item.id)
        return CompactNextActionRow(
            title: item.title,
            contextLabel: "次の一手",
            isWorking: isWorking,
            onOpen: { presentedSheet = .proposalDetail(proposalId: item.proposalId, decisionItem: item) }
        )
        .swipeActions(
            edge: .leading,
            allowsFullSwipe: item.availableDecisions.contains("approve") &&
                item.approvalRisk == "low" &&
                item.actionKind != "build_experiment"
        ) {
            if item.availableDecisions.contains("approve") &&
                item.approvalRisk == "low" &&
                item.actionKind != "build_experiment" {
                Button {
                    decide(item, .approved)
                } label: {
                    Label(item.approvalLabel, systemImage: "checkmark")
                }
                .tint(.green)
                .disabled(isWorking)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.availableDecisions.contains("reject") {
                Button(role: .destructive) {
                    decide(item, .rejected)
                } label: {
                    Label("却下", systemImage: "xmark")
                }
                .disabled(isWorking)
            }

            if item.availableDecisions.contains("defer") {
                Button {
                    decide(item, .deferred)
                } label: {
                    Label("あとで", systemImage: "clock")
                }
                .tint(.orange)
                .disabled(isWorking)
            }
        }
        .modifier(ConditionalAccessibilityAction(
            isAvailable: item.availableDecisions.contains("approve"),
            label: item.approvalLabel,
            action: { decide(item, .approved) }
        ))
        .modifier(ConditionalAccessibilityAction(
            isAvailable: item.availableDecisions.contains("defer"),
            label: "あとで",
            action: { decide(item, .deferred) }
        ))
        .modifier(ConditionalAccessibilityAction(
            isAvailable: item.availableDecisions.contains("reject"),
            label: "却下",
            action: { decide(item, .rejected) }
        ))
    }

    @ViewBuilder
    private func decisionAgendaSummary(
        _ agenda: VentureDecisionAgendaSummary,
        item: VentureDecisionInboxItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(agenda.question)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("現在の見立て")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(agenda.currentPosition)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("足りない事実")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(agenda.primaryUnknown)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("判断基準")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.decisionRuleSummary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func missionCompactRow(_ item: VentureMissionSummaryItem) -> some View {
        let isWorking = productOpsState.isMutatingMission(id: item.id)
        return CompactNextActionRow(
            title: item.title,
            contextLabel: missionSectionLabel(item.status),
            isWorking: isWorking,
            onOpen: {
                presentedSheet = item.deliverableKind == "knowledge_change"
                    ? .policyRevision(missionId: item.id)
                    : .missionDetail(
                        missionId: item.id,
                        kindLabel: item.kindLabel,
                        requestedAction: nil
                    )
            }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if item.availableActions.contains("adopt") && item.deliverableKind != "knowledge_change" {
                Button {
                    Task { await productOpsState.adoptMissionFromList(item) }
                } label: {
                    Label("採用", systemImage: "checkmark")
                }
                .tint(.green)
                .disabled(isWorking)
            }
            if item.availableActions.contains("retry") {
                Button {
                    presentedSheet = .missionDetail(
                        missionId: item.id,
                        kindLabel: item.kindLabel,
                        requestedAction: "retry"
                    )
                } label: {
                    Label("再実行", systemImage: "arrow.clockwise")
                }
                .tint(.green)
                .disabled(isWorking)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.availableActions.contains("dismiss") {
                Button(role: .destructive) {
                    Task { await productOpsState.dismissMissionFromList(item) }
                } label: {
                    Label("削除", systemImage: "trash")
                }
                .disabled(isWorking)
            }
            if item.availableActions.contains("cancel") {
                Button(role: .destructive) {
                    Task { await productOpsState.cancelMissionFromList(item) }
                } label: {
                    Label("キャンセル", systemImage: "stop")
                }
                .disabled(isWorking)
            }
            if item.availableActions.contains("reject") {
                Button(role: .destructive) {
                    presentedSheet = item.deliverableKind == "knowledge_change"
                        ? .policyRevision(missionId: item.id)
                        : .missionDetail(
                            missionId: item.id,
                            kindLabel: item.kindLabel,
                            requestedAction: "reject"
                        )
                } label: {
                    Label("却下", systemImage: "xmark")
                }
                .disabled(isWorking)
            }
            if item.availableActions.contains("request_revision") {
                Button {
                    presentedSheet = item.deliverableKind == "knowledge_change"
                        ? .policyRevision(missionId: item.id)
                        : .missionDetail(
                            missionId: item.id,
                            kindLabel: item.kindLabel,
                            requestedAction: "request_revision"
                        )
                } label: {
                    Label("修正", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(.orange)
                .disabled(isWorking)
            }
        }
    }

    private func missionSectionLabel(_ status: String) -> String {
        switch status {
        case "queued": return "やること"
        case "dispatching", "running": return "進行中"
        case "awaiting_external_input": return "やること"
        default: return "確認待ち"
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
                        showsMoveHandle: true,
                        onOpen: { open(item) },
                        onPrimary: { perform(item.primaryAction, item: item) },
                        onSecondary: { command in perform(command, item: item) }
                    )
                    .dropDestination(for: String.self) { itemIds, _ in
                        guard let sourceId = itemIds.first else { return false }
                        productOpsState.moveNextActionTodoRow(id: sourceId, before: item.id)
                        return true
                    }
                }
                .onMove { offsets, destination in
                    productOpsState.moveNextActionTodoRows(from: offsets, to: destination)
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
                        showsMoveHandle: false,
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
                        showsMoveHandle: false,
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
                presentedSheet = .directMissionRequest
            } label: {
                Label("エージェントに依頼", systemImage: "sparkles")
            }

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
                router.push(.venturePolicy)
            } label: {
                Label("プロダクト方針", systemImage: "scope")
            }

            Button {
                router.push(.actionHistory)
            } label: {
                Label("実行履歴", systemImage: "clock.arrow.circlepath")
            }

            Button {
                Task { await productOpsState.scanMonitoringAlerts() }
            } label: {
                Label("監視スキャン", systemImage: "waveform.path.ecg")
            }
            .disabled(productOpsState.isScanningMonitoringAlerts)

            Button {
                Task { await productOpsState.requestRecommendationHeartbeat() }
            } label: {
                Label("提案を今すぐ準備", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!actionInboxState.isSignedIn || productOpsState.isRequestingRecommendationHeartbeat)

            Button {
                router.push(.completedActions)
            } label: {
                Label("完了した項目", systemImage: "checkmark.seal")
            }

            Divider()

            if actionInboxState.isSignedIn {
                Button {
                    router.presentedSheet = .settings
                } label: {
                    Label("通知設定", systemImage: "bell.badge")
                }

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
    }

    private func presentPendingDeepLink(refreshBeforePresentation: Bool) async {
        guard actionInboxState.isSignedIn else { return }
        guard let destination = router.consumePendingProductOpsDeepLink() else { return }
        if refreshBeforePresentation {
            switch destination {
            case .proposal:
                await productOpsState.loadRecommendationsIfPossible()
            case .mission:
                break
            case .monitoringAlert:
                await productOpsState.loadNextActionsIfPossible()
            }
        }

        switch destination {
        case .proposal(let proposalId):
            do {
                _ = try await productOpsState.fetchProposalDetail(proposalId: proposalId)
                let decisionItem = productOpsState.decisionItems.first { $0.proposalId == proposalId }
                presentedSheet = .proposalDetail(proposalId: proposalId, decisionItem: decisionItem)
            } catch {
                fallBackToNextActions(message: "このおすすめは削除済みか、現在は表示できません。")
            }
        case .mission(let missionId, let kind):
            do {
                let detail = try await productOpsState.fetchMissionDetail(missionId: missionId)
                presentedSheet = detail.currentDeliverable?.kind == "knowledge_change"
                    ? .policyRevision(missionId: missionId)
                    : .missionDetail(
                        missionId: missionId,
                        kindLabel: kind.label,
                        requestedAction: nil
                    )
            } catch {
                fallBackToNextActions(message: "このMissionは削除済みか、現在は表示できません。")
            }
        case .monitoringAlert(let alertId):
            guard let item = productOpsState.monitoringAlertItems.first(where: { $0.id == alertId }) else {
                fallBackToNextActions(message: "監視アラートはすでに解決済みか、表示対象外です。")
                return
            }
            presentedSheet = .alertDetail(item)
        }
        ActionPushNotificationCoordinator.shared.clearPendingDeepLink()
    }

    private func signIn() async {
        await actionInboxState.signIn()
        await productOpsState.loadNextActionsIfPossible()
        await presentPendingDeepLink(refreshBeforePresentation: true)
        ActionPushNotificationCoordinator.shared.clearPendingDeepLink()
    }

    private func fallBackToNextActions(message: String) {
        router.handleDeepLink(PushNotificationRouting.nextActionsURL)
        presentedSheet = nil
        productOpsState.message = message
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

    private func decide(_ item: VentureDecisionInboxItem, _ decision: VentureDecision) {
        let command = switch decision {
        case .approved: "approve"
        case .deferred: "defer"
        case .rejected: "reject"
        }
        guard item.availableDecisions.contains(command) else { return }
        if decision == .approved {
            Task {
                await productOpsState.decideVentureProposal(
                    item,
                    decision: decision,
                    reasonCodes: approvedReasonCodes(for: item)
                )
            }
        } else {
            presentProposalFeedback(item, decision: decision)
        }
    }

    private func presentProposalFeedback(_ item: VentureDecisionInboxItem, decision: VentureDecision) {
        let nextSheet = NextActionsSheet.proposalFeedback(
            PendingVentureProposalFeedback(item: item, decision: decision)
        )
        if let currentSheet = presentedSheet,
           case .proposalDetail = currentSheet {
            deferredSheet = nextSheet
            presentedSheet = nil
        } else {
            presentedSheet = nextSheet
        }
    }

    private func presentDeferredSheetIfNeeded() {
        guard let nextSheet = deferredSheet else { return }
        deferredSheet = nil
        Task { @MainActor in
            await Task.yield()
            guard presentedSheet == nil else { return }
            presentedSheet = nextSheet
        }
    }

    private func approvedReasonCodes(for item: VentureDecisionInboxItem) -> [String] {
        switch item.actionKind {
        case "research", "analyze":
            return ["high_learning_value"]
        case "build_experiment":
            return ["high_business_impact"]
        default:
            return ["good_next_step"]
        }
    }
}

private struct ConditionalAccessibilityAction: ViewModifier {
    let isAvailable: Bool
    let label: String
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAvailable {
            content.accessibilityAction(named: Text(label), action)
        } else {
            content
        }
    }
}

private struct CompactNextActionRow: View {
    let title: String
    let contextLabel: String
    let isWorking: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(contextLabel)")
        .accessibilityHint("ダブルタップで詳細を表示。上下にスワイプすると利用可能な操作を選べます。")
    }
}

@MainActor
private struct VentureProposalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let proposalId: String
    let decisionItem: VentureDecisionInboxItem?
    let onApprove: (VentureDecisionInboxItem) -> Void
    let onLater: (VentureDecisionInboxItem) -> Void
    let onReject: (VentureDecisionInboxItem) -> Void
    @State private var detail: VentureProposalDetail?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    List {
                        proposalContent(detail)
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .bottom) {
                        if hasAvailableActions {
                            actionBar
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("提案の詳細を読み込めません", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("再試行") { Task { await load() } }
                    }
                } else {
                    ProgressView("詳細を読み込んでいます")
                }
            }
            .navigationTitle("おすすめ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let detail {
                        ProductOpsMarkdownCopyButton {
                            state.copyMarkdown(ProductOpsMarkdownFormatter.proposal(detail))
                        }
                    }
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func proposalContent(_ detail: VentureProposalDetail) -> some View {
        Section("今決めること") {
            Text(detail.proposal.decisionAgenda.question)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail.proposal.decisionAgenda.currentPosition)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let alternative = detail.proposal.decisionAgenda.alternativeExplanation {
            detailSection("反対の可能性", text: alternative)
        }

        detailSection("判断を止めている未知", text: detail.proposal.decisionAgenda.primaryUnknown)

        Section("今回の行動") {
            Text(detail.proposal.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("対象", value: detail.proposal.actionSpec.target)
            LabeledContent("方法", value: detail.proposal.actionSpec.method)
            LabeledContent("量", value: detail.proposal.actionSpec.quantity)
            LabeledContent("期限", value: detail.proposal.actionSpec.timebox)
            Text(detail.proposal.contextSpecificReason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        detailSection("期待する観測", text: detail.proposal.expectedObservation)

        Section("結果別の判断") {
            LabeledContent("進む", value: detail.proposal.decisionRule.proceedWhen)
            LabeledContent("止める", value: detail.proposal.decisionRule.stopWhen)
            LabeledContent("見直す", value: detail.proposal.decisionRule.reconsiderWhen)
        }

        Section("Opportunity") {
            Text(detail.opportunity.problemStatement)
            Text(detail.opportunity.desiredOutcomeStatement)
                .foregroundStyle(.secondary)
            if !detail.opportunity.evidenceSummary.isEmpty {
                Text(detail.opportunity.evidenceSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        detailSection("検証する仮説", text: detail.hypothesis.statement)

        Section("根拠") {
            ForEach(detail.proposal.groundingRefs, id: \.stableId) { reference in
                LabeledContent(reference.kind, value: reference.relation)
                    .accessibilityLabel("\(reference.kind)、\(reference.relation)、\(reference.id)")
            }
        }

        if let change = detail.proposal.decisionFrameChange {
            Section("判断軸の変更") {
                Text(change.rationale)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(changedLenses(change)) { lens in
                    LabeledContent(lens.label) {
                        Text("\(weightText(lens.current)) → \(weightText(lens.proposed))")
                            .monospacedDigit()
                    }
                }
            }
        }

        Section("方針との関連") {
            Text(detail.strategy.mission)
            if !detail.strategy.targetSegments.isEmpty {
                LabeledContent("対象", value: detail.strategy.targetSegments.map(\.label).joined(separator: "、"))
            }
            if !detail.strategy.focusAreas.isEmpty {
                Text(detail.strategy.focusAreas.map { "・\($0)" }.joined(separator: "\n"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if !detail.learnings.isEmpty {
            Section("過去のLearning") {
                ForEach(detail.learnings) { learning in
                    Text(learning.summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        Section {
            DisclosureGroup("詳細情報を表示") {
                LabeledContent("順位", value: String(detail.assessment.rank))
                LabeledContent("最終評価", value: String(format: "%.2f", detail.assessment.finalScore))
                LabeledContent("事業評価", value: String(format: "%.2f", detail.assessment.businessScore))
                LabeledContent("内容評価", value: String(format: "%.2f", detail.assessment.substanceScore))
                ForEach(detail.assessment.scores.keys.sorted(), id: \.self) { key in
                    if let score = detail.assessment.scores[key] {
                        LabeledContent(key, value: String(format: "%.2f", score))
                    }
                }
                LabeledContent("評価方式", value: detail.assessment.algorithmKey)
                LabeledContent("生成モデル", value: detail.recommendation.metadata.draftingModel)
                LabeledContent("Prompt", value: detail.recommendation.metadata.draftingPromptVersion)
                LabeledContent("Rating", value: detail.recommendation.metadata.ratingAlgorithmVersion)
            }
        }
    }

    private struct LensChange: Identifiable {
        var id: String
        var label: String
        var current: Double
        var proposed: Double
    }

    private func changedLenses(_ change: VentureProposalDecisionFrameChange) -> [LensChange] {
        let currentByKey = Dictionary(uniqueKeysWithValues: change.currentLenses.map { ($0.key, $0) })
        return change.proposedLenses.compactMap { proposed in
            guard let current = currentByKey[proposed.key], current.weight != proposed.weight else { return nil }
            return LensChange(id: proposed.key, label: proposed.label, current: current.weight, proposed: proposed.weight)
        }
    }

    private func weightText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func detailSection(_ title: String, text: String) -> some View {
        Section(title) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func listSection(_ title: String, items: [String]) -> some View {
        Section(title) {
            ForEach(items, id: \.self) { value in
                Label(value, systemImage: "circle.fill")
                    .labelStyle(ProductOpsBulletLabelStyle())
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let decisionItem, decisionItem.availableDecisions.contains("reject") {
                proposalActionButton("却下", tint: .red, role: .destructive) {
                    onReject(decisionItem)
                }
            } else {
                proposalActionPlaceholder
            }

            if let decisionItem, decisionItem.availableDecisions.contains("defer") {
                proposalActionButton("あとで", tint: .orange) {
                    onLater(decisionItem)
                }
            } else {
                proposalActionPlaceholder
            }

            if let decisionItem, decisionItem.availableDecisions.contains("approve") {
                proposalActionButton(decisionItem.approvalLabel, tint: .accentColor) {
                    onApprove(decisionItem)
                    dismiss()
                }
            } else {
                proposalActionPlaceholder
            }
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var hasAvailableActions: Bool {
        guard let decisionItem else { return false }
        return ["approve", "defer", "reject"].contains { decisionItem.availableDecisions.contains($0) }
    }

    private func proposalActionButton(
        _ title: String,
        tint: Color,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ProductOpsTranslucentActionButtonStyle(tint: tint))
    }

    private var proposalActionPlaceholder: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .accessibilityHidden(true)
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await state.fetchProposalDetail(proposalId: proposalId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductOpsBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

private struct ProductOpsMarkdownCopyButton: View {
    let action: () -> Void
    @State private var didCopy = false

    var body: some View {
        Button {
            action()
            didCopy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
        }
        .accessibilityLabel(didCopy ? "Markdownをコピーしました" : "Markdownをコピー")
        .help("タイトルと詳細をMarkdown形式でコピー")
    }
}

private struct ProductOpsExternalLinkButton<Label: View>: View {
    @Environment(\.openURL) private var openURL
    let destination: URL
    let label: Label

    init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        Button {
            openURL(destination)
        } label: {
            label
        }
        // A List row can otherwise combine multiple automatic button actions.
        .buttonStyle(.borderless)
        .accessibilityHint("外部アプリで開きます")
    }
}

private struct VentureMonitoringAlertDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let item: VentureMonitoringAlertItem
    @State private var isDismissing = false
    @State private var confirmsDismissal = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("検知した問題") {
                    Text(item.alert.detectedIssue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("推奨対応") {
                    Text(item.alert.recommendedAction)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("状態") {
                    LabeledContent("重要度", value: item.alert.severity)
                    LabeledContent("状態", value: item.alert.status)
                }
            }
            .navigationTitle("監視アラート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDismissal = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isDismissing)
                    .accessibilityLabel("監視アラートを削除")
                    ProductOpsMarkdownCopyButton {
                        state.copyMarkdown(ProductOpsMarkdownFormatter.monitoringAlert(item))
                    }
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("この確認待ちを削除しますか？", isPresented: $confirmsDismissal) {
                Button("削除", role: .destructive) {
                    isDismissing = true
                    Task {
                        do {
                            try await state.dismissMission(missionId: item.alert.missionId)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isDismissing = false
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("履歴は保持したまま、次にやる画面から非表示にします。")
            }
            .alert("削除できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct VentureProposalFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let pending: PendingVentureProposalFeedback

    private var title: String {
        pending.decision == .deferred ? "あとでにする理由" : "却下する理由"
    }

    private var options: [(label: String, code: String)] {
        [
            ("根拠不足", "insufficient_evidence"),
            ("当たり前すぎる", "too_obvious"),
            ("判断に効かない", "not_decision_relevant"),
            ("新しい情報がない", "no_new_information"),
            ("判断基準がない", "missing_decision_rule"),
            ("今じゃない", "wrong_timing"),
            ("効果が弱い", "low_impact"),
            ("重複", "duplicate"),
            ("方針と違う", "out_of_scope"),
            ("具体性不足", "too_vague"),
            ("別の行動がよい", "wrong_action"),
            ("ブロック中", "blocked"),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pending.item.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("理由を選ぶとすぐ保存します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(title) {
                    ForEach(options, id: \.code) { option in
                        Button {
                            Task {
                                await state.decideVentureProposal(
                                    pending.item,
                                    decision: pending.decision,
                                    reasonCodes: [option.code]
                                )
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(state.isPostingVentureDecision)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct RecommendedVentureProposalCard: View {
    let item: VentureDecisionInboxItem
    let isWorking: Bool
    let onApprove: () -> Void
    let onLater: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ProductOpsTokenView(item.actionLabel, systemImage: "sparkles")
                ProductOpsTokenView("score \(String(format: "%.2f", item.totalScore))", systemImage: "gauge")
                ProductOpsTokenView("v\(item.version)", systemImage: "number")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.whyNow)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("承認後")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.approvalEffect)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("期待する結果")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.expectedOutcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let firstCriterion = item.suggestedSuccessCriteria.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("承認時の成功条件")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(firstCriterion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: onApprove) {
                    Label(item.approvalLabel, systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button("あとで", action: onLater)
                    .buttonStyle(.bordered)

                Button("却下", role: .destructive, action: onReject)
                    .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
            .controlSize(.small)
            .disabled(isWorking)
        }
        .padding(.vertical, 8)
    }
}

private struct VentureProposalRow: View {
    let item: VentureDecisionInboxItem
    let isWorking: Bool
    let onApprove: () -> Void
    let onLater: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.whyNow)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ProductOpsTokenView(item.actionLabel)
                    ProductOpsTokenView("rank \(item.rank)")
                    ProductOpsTokenView("score \(String(format: "%.2f", item.totalScore))")
                }
                Text(item.approvalEffect)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Menu {
                Button(item.approvalLabel) { onApprove() }
                Button("あとで") { onLater() }
                Button("却下", role: .destructive) { onReject() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
        }
        .padding(.vertical, 6)
    }
}

private struct MissionProgressSummaryRow: View {
    let progress: VentureMissionProgressPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProductOpsTokenView("判断待ち \(progress.totals.waitingForHuman)", systemImage: "person.crop.circle.badge.questionmark")
                ProductOpsTokenView("進行中 \(progress.totals.running)", systemImage: "clock")
                if progress.totals.failed > 0 {
                    ProductOpsTokenView("失敗 \(progress.totals.failed)", systemImage: "exclamationmark.triangle")
                }
            }
            let activeCapabilities = progress.capabilities.filter { $0.total > 0 }
            if !activeCapabilities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeCapabilities) { item in
                            ProductOpsTokenView("\(item.label) \(item.total)")
                        }
                    }
                }
            }
            Text("外部送信・PRマージ・本番変更は別確認です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct VentureMissionSummaryRow: View {
    let item: VentureMissionSummaryItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProductOpsTokenView(item.kindLabel)
                        ProductOpsTokenView(statusLabel)
                    }
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(item.status == "failed" ? .red : .secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusLabel: String {
        switch item.status {
        case "queued": return "待機中"
        case "dispatching": return "配送中"
        case "running": return "実行中"
        case "awaiting_external_input": return "Mac Codexの修正版待ち"
        case "awaiting_review": return "結果確認"
        case "failed": return "失敗"
        default: return item.status
        }
    }

    private var iconName: String {
        switch item.missionKind {
        case "development": return "hammer"
        case "research": return "magnifyingglass"
        case "message": return "text.bubble"
        case "verification": return "checkmark.seal"
        case "knowledge_change": return "books.vertical"
        default: return "circle.dotted"
        }
    }

    private var tint: Color {
        switch item.status {
        case "failed": return .red
        case "awaiting_review": return .orange
        default: return .blue
        }
    }
}

@MainActor
private struct VentureMissionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let missionId: String
    let kindLabel: String
    let requestedAction: String?
    @State private var detail: VentureMissionDetail?
    @State private var errorMessage: String?
    @State private var operationErrorMessage: String?
    @State private var feedbackRequest: MissionFeedbackRequest?
    @State private var feedbackText = ""
    @State private var isSubmitting = false
    @State private var didHandleRequestedAction = false
    @State private var confirmsDismissal = false
    @State private var dismissAfterFeedback = false

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    List {
                        missionContent(detail)
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .bottom) {
                        if !detail.availableActions.isEmpty {
                            missionActionBar(detail)
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("詳細を読み込めません", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("再試行") {
                            Task { await load() }
                        }
                    }
                } else {
                    ProgressView("詳細を読み込んでいます")
                }
            }
            .navigationTitle(kindLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let detail {
                        if detail.availableActions.contains("dismiss") {
                            Button(role: .destructive) {
                                confirmsDismissal = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isSubmitting)
                            .accessibilityLabel("確認待ちから削除")
                        }
                        ProductOpsMarkdownCopyButton {
                            state.copyMarkdown(ProductOpsMarkdownFormatter.mission(detail))
                        }
                    }
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("この確認待ちを削除しますか？", isPresented: $confirmsDismissal) {
                Button("削除", role: .destructive) {
                    startSubmission { await dismissMission() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("履歴は保持したまま、次にやる画面から非表示にします。")
            }
            .task {
                await load()
                handleRequestedActionIfNeeded()
            }
            .sheet(item: $feedbackRequest, onDismiss: dismissAfterTerminalFeedback) { request in
                MissionFeedbackSheet(
                    request: request,
                    feedback: $feedbackText,
                    isSubmitting: isSubmitting,
                    onSubmit: { startSubmission { await submitFeedback(request) } }
                )
            }
            .alert("操作できませんでした", isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { if !$0 { operationErrorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(operationErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func missionContent(_ detail: VentureMissionDetail) -> some View {
        Section("目的") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel(detail.mission.status))
                    ProductOpsTokenView(detail.mission.primaryDeliverableSpec.kind)
                    if detail.mission.origin.kind == "direct_request" {
                        ProductOpsTokenView("直接依頼")
                    }
                    if let attempt = detail.currentAttempt {
                        ProductOpsTokenView("Attempt \(attempt.attemptNumber)")
                    }
                }
                Text(detail.mission.primaryDeliverableSpec.title)
                    .font(.headline)
                if detail.displayObjective != detail.mission.primaryDeliverableSpec.title {
                    Text(detail.displayObjective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }

        if let approvedInstruction = detail.approvedInstruction {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("承認済み依頼")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            state.copyMarkdown(approvedInstruction)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("承認済み依頼をコピー")
                    }
                    ProductOpsMarkdownView(markdown: approvedInstruction)
                }
                .padding(.vertical, 4)
            }
        }

        if !detail.mission.primaryDeliverableSpec.acceptanceCriteria.isEmpty {
            Section("合格条件") {
                ForEach(detail.mission.primaryDeliverableSpec.acceptanceCriteria, id: \.self) { criterion in
                    Label(criterion, systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
            }
        }

        Section("実行結果") {
            if let deliverable = detail.currentDeliverable {
                deliverableContent(deliverable)
            } else if let attempt = detail.currentAttempt, let error = attempt.error, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(detail.mission.status == "failed" ? "成果物は作成されませんでした。" : "現在の実行結果を待っています。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if let verification = detail.verification {
            Section("AIレビュー") {
                if let report = verification.report {
                    VentureVerificationReportSummaryView(
                        summary: verification.summary,
                        report: report,
                        isCompact: false
                    )
                } else if let error = verification.reportDecodingError {
                    VentureDeliverableDecodingErrorView(
                        title: "検証レポート",
                        message: error
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: verificationStatusIcon(verification.status))
                            .foregroundStyle(verificationStatusTint(verification.status))
                        Text(verificationStatusText(verification.status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !detail.revisionReviews.isEmpty {
            Section("修正指示") {
                ForEach(detail.revisionReviews) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        if let feedback = review.feedback {
                            Text(feedback)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(Self.dateFormatter.string(from: review.reviewedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !detail.availableActions.isEmpty {
            Section("操作の境界") {
                Text(actionBoundary(detail.mission.primaryDeliverableSpec.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if detail.currentAttempt?.instructionSnapshot.schemaKey == "legacy_mission_attempt" {
                    Text("旧形式のMissionでは成果物の修正・再実行を利用できません。必要な場合は新しいMissionを作成してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if detail.currentAttempt?.instructionSnapshot.schemaKey == "legacy_mission_attempt"
                    && detail.mission.status == "failed" {
            Section("操作") {
                Text("このMissionは旧形式のため、修正・再実行には新しいMissionの作成が必要です。成果物の採用または却下は行えます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if !detail.attempts.isEmpty {
            Section("実行履歴") {
                ForEach(detail.attempts.sorted { $0.attemptNumber > $1.attemptNumber }) { attempt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Attempt \(attempt.attemptNumber)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            ProductOpsTokenView(attemptStatusLabel(attempt.status))
                        }
                        Text(Self.dateFormatter.string(from: attempt.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let error = attempt.error, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let executorSessionId = attempt.executorSessionId {
                            LabeledContent("Session") {
                                Text(executorSessionId)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        if let executorTurnId = attempt.executorTurnId {
                            LabeledContent("Turn") {
                                Text(executorTurnId)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        ForEach(detail.reviews.filter { $0.attemptId == attempt.id }) { review in
                            Text(review.decision == "revision_requested" ? "修正依頼（内容は「修正指示」に表示）" : reviewSummary(review))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private func deliverableContent(_ deliverable: VentureDeliverable) -> some View {
        let result = Result { try deliverable.decodePayload() }
        switch result {
        case .success(let payload):
            switch payload {
            case .decisionBrief(let value):
                VentureDecisionBriefSummaryView(summary: deliverable.displaySummary, brief: value)
            case .productChange(let value):
                VentureProductChangeSummaryView(
                    summary: deliverable.displaySummary,
                    productChange: value,
                    supportingPullRequests: []
                )
            case .researchReport(let value):
                VentureResearchReportDetailView(
                    summary: deliverable.displaySummary,
                    report: value,
                    copyMarkdown: { markdown in state.copyMarkdown(markdown) }
                )
            case .message(let value):
                VentureMessageDraftView(summary: deliverable.displaySummary, message: value)
            case .verificationReport(let value):
                VentureVerificationReportSummaryView(
                    summary: deliverable.displaySummary,
                    report: value,
                    isCompact: false
                )
            case .knowledgeChange(let value):
                VentureKnowledgeChangeSummaryView(
                    summary: deliverable.displaySummary,
                    knowledgeChange: value,
                    currentPolicy: state.policy
                )
            case .alert(let value):
                VStack(alignment: .leading, spacing: 6) {
                    Text(deliverable.displaySummary).font(.subheadline)
                    ProductChangeSection(title: "検知", items: [value.detectedIssue])
                    ProductChangeSection(title: "推奨対応", items: [value.recommendedAction])
                }
            }
        case .failure(let error):
            VentureDeliverableDecodingErrorView(
                title: deliverable.title,
                message: error.localizedDescription
            )
        }
    }

    private func missionActionBar(_ detail: VentureMissionDetail) -> some View {
        HStack(spacing: 10) {
            if detail.availableActions.contains("reject") {
                missionActionButton("却下して終了", tint: .red, role: .destructive) {
                    feedbackText = ""
                    feedbackRequest = MissionFeedbackRequest(kind: .reject)
                }
            } else if detail.availableActions.contains("cancel") {
                missionActionButton("キャンセル", tint: .red, role: .destructive) {
                    startSubmission { await cancel(detail) }
                }
            } else {
                missionActionPlaceholder
            }

            if detail.availableActions.contains("request_revision") {
                missionActionButton("修正して再実行", tint: .orange) {
                    feedbackText = ""
                    feedbackRequest = MissionFeedbackRequest(kind: .revision)
                }
            } else {
                missionActionPlaceholder
            }

            if detail.availableActions.contains("adopt") {
                missionActionButton("採用する", tint: .accentColor) {
                    startSubmission { await adopt(detail) }
                }
            } else if detail.availableActions.contains("retry") {
                missionActionButton("再実行", tint: .accentColor) {
                    feedbackText = ""
                    feedbackRequest = MissionFeedbackRequest(kind: .retry)
                }
            } else {
                missionActionPlaceholder
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .font(.subheadline.weight(.semibold))
        .controlSize(.large)
        .background(.ultraThinMaterial)
    }

    private func missionActionButton(
        _ title: String,
        tint: Color,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ProductOpsTranslucentActionButtonStyle(tint: tint))
        .disabled(isSubmitting)
    }

    private var missionActionPlaceholder: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .accessibilityHidden(true)
    }

    private func load() async {
        errorMessage = nil
        do {
            let loadedDetail = try await state.fetchMissionDetail(missionId: missionId)
            detail = loadedDetail
            if loadedDetail.currentDeliverable?.kind == "knowledge_change" {
                await state.loadPolicyIfPossible()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRequestedActionIfNeeded() {
        guard !didHandleRequestedAction, let requestedAction, let detail else { return }
        didHandleRequestedAction = true
        switch requestedAction {
        case "request_revision" where detail.availableActions.contains("request_revision"):
            feedbackText = ""
            feedbackRequest = MissionFeedbackRequest(kind: .revision)
        case "reject" where detail.availableActions.contains("reject"):
            feedbackText = ""
            feedbackRequest = MissionFeedbackRequest(kind: .reject)
        case "retry" where detail.availableActions.contains("retry"):
            feedbackText = ""
            feedbackRequest = MissionFeedbackRequest(kind: .retry)
        case "adopt" where detail.availableActions.contains("adopt"):
            startSubmission { await adopt(detail) }
        case "cancel" where detail.availableActions.contains("cancel"):
            startSubmission { await cancel(detail) }
        default:
            break
        }
    }

    private func adopt(_ detail: VentureMissionDetail) async {
        defer { isSubmitting = false }
        do {
            self.detail = try await state.reviewMissionDeliverable(
                detail: detail,
                decision: "adopted",
                feedback: "成果物を確認し採用"
            )
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func submitFeedback(_ request: MissionFeedbackRequest) async {
        guard let detail else { return }
        let feedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }
        defer { isSubmitting = false }
        do {
            switch request.kind {
            case .revision:
                self.detail = try await state.reviewMissionDeliverable(
                    detail: detail,
                    decision: "revision_requested",
                    feedback: feedback
                )
            case .reject:
                try await state.rejectMissionDeliverable(
                    detail: detail,
                    feedback: feedback
                )
                dismissAfterFeedback = true
            case .retry:
                self.detail = try await state.retryMission(detail: detail, feedback: feedback)
            }
            feedbackRequest = nil
            feedbackText = ""
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func cancel(_ detail: VentureMissionDetail) async {
        defer { isSubmitting = false }
        do {
            self.detail = try await state.cancelMission(detail: detail)
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func dismissMission() async {
        defer { isSubmitting = false }
        do {
            try await state.dismissMission(missionId: missionId)
            dismiss()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func startSubmission(_ operation: @escaping @MainActor () async -> Void) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { await operation() }
    }

    private func dismissAfterTerminalFeedback() {
        guard dismissAfterFeedback else { return }
        dismissAfterFeedback = false
        dismiss()
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
        case "awaiting_external_input": return "Mac Codexの修正版待ち"
        case "awaiting_review": return "結果確認"
        case "completed": return "採用済み"
        case "failed": return "失敗"
        case "canceled": return "キャンセル"
        case "rejected": return "却下"
        default: return status
        }
    }

    private func verificationStatusText(_ status: String) -> String {
        switch status {
        case "queued", "dispatching": return "AIレビューを準備しています"
        case "running": return "AIレビューを実行しています"
        case "failed": return "AIレビューに失敗しました"
        case "canceled": return "元成果物の判断に伴いAIレビューを終了しました"
        default: return "AIレビュー結果を待っています"
        }
    }

    private func verificationStatusIcon(_ status: String) -> String {
        switch status {
        case "failed": return "exclamationmark.triangle"
        case "canceled": return "xmark.circle"
        default: return "checkmark.seal"
        }
    }

    private func verificationStatusTint(_ status: String) -> Color {
        switch status {
        case "failed": return .red
        case "canceled": return .secondary
        default: return .accentColor
        }
    }

    private func attemptStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
        case "awaiting_external_input": return "修正版待ち"
        case "succeeded": return "実行成功"
        case "failed": return "失敗"
        case "canceled": return "中断"
        default: return status
        }
    }

    private func reviewSummary(_ review: VentureDeliverableReview) -> String {
        let label = review.decision == "adopted" ? "採用" : review.decision == "revision_requested" ? "修正依頼" : "却下"
        return review.feedback.map { "\(label): \($0)" } ?? label
    }

    private func actionBoundary(_ kind: String) -> String {
        switch kind {
        case "message": return "採用しても外部へ送信しません。送信には別の承認が必要です。"
        case "product_change": return "採用してもPRマージや本番反映は行いません。"
        case "knowledge_change": return "採用すると事業方針の新しいVersionを作成します。外部送信や本番変更は行いません。"
        default: return "採用後の副作用はMissionの承認境界に従います。"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
}

private struct MissionFeedbackRequest: Identifiable {
    enum Kind {
        case revision
        case reject
        case retry
    }

    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
        case .revision: return "修正内容"
        case .reject: return "却下理由"
        case .retry: return "再実行の指示"
        }
    }

    var actionLabel: String {
        switch kind {
        case .revision: return "修正を依頼"
        case .reject: return "却下して終了"
        case .retry: return "再実行"
        }
    }
}

private struct MissionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: MissionFeedbackRequest
    @Binding var feedback: String
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(request.title) {
                    TextEditor(text: $feedback)
                        .frame(minHeight: 150)
                }
                if request.kind == .revision {
                    Section("再実行について") {
                        Label("元の依頼と前回の成果物を引き継ぎます。", systemImage: "arrow.triangle.2.circlepath")
                        Label("外部への投稿、返信、DM、メール送信は行いません。", systemImage: "hand.raised")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.actionLabel) { onSubmit() }
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct VentureDevelopmentMissionRow: View {
    let item: VentureDevelopmentMissionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel)
                    if !item.mission.repositories.isEmpty {
                        ProductOpsTokenView(item.mission.repositories.joined(separator: " / "))
                    }
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let productChange = item.productChangeDeliverable {
                    VentureProductChangeSummaryView(
                        summary: item.deliverables.first { $0.kind == "product_change" }?.summary ?? item.result?.summary ?? "",
                        productChange: productChange,
                        supportingPullRequests: item.result?.pullRequests ?? []
                    )
                } else if let result = item.result {
                    Text(result.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pullRequest = result.pullRequests.first, let url = URL(string: pullRequest.url) {
                        ProductOpsExternalLinkButton(destination: url) {
                            Label("Draft PR", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                    }
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("MacのCodex app serverで実行中です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        switch item.mission.status {
        case "queued":
            return "待機中"
        case "dispatching":
            return "Codexへ依頼済み"
        case "running":
            return "実行中"
        case "awaiting_review":
            return "結果確認"
        case "failed":
            return "失敗"
        case "completed":
            return "完了"
        case "canceled":
            return "キャンセル"
        default:
            return item.mission.status
        }
    }

    private var iconName: String {
        switch item.mission.status {
        case "awaiting_review":
            return "doc.text.magnifyingglass"
        case "failed":
            return "exclamationmark.triangle"
        case "completed":
            return "checkmark.circle"
        case "canceled":
            return "xmark.circle"
        default:
            return "terminal"
        }
    }

    private var tint: Color {
        switch item.mission.status {
        case "failed":
            return .red
        case "awaiting_review":
            return .orange
        case "completed":
            return .green
        default:
            return .accentColor
        }
    }
}

private struct VentureMonitoringAlertRow: View {
    let item: VentureMonitoringAlertItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(severityLabel)
                    ProductOpsTokenView(item.alert.status)
                }
                Text(alertPayload.detectedIssue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                ProductChangeSection(title: "推奨対応", items: [alertPayload.recommendedAction].filter { !$0.isEmpty })
                if let summary = item.alertDeliverable?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !alertPayload.entityRefs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(alertPayload.entityRefs.prefix(3), id: \.self) { ref in
                            ProductOpsTokenView(ref)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var alertPayload: VentureAlertDeliverable {
        item.alertPayload ?? VentureAlertDeliverable(
            severity: item.alert.severity,
            detectedIssue: item.alert.detectedIssue,
            recommendedAction: item.alert.recommendedAction,
            entityRefs: item.alert.entityRefs
        )
    }

    private var severityLabel: String {
        switch alertPayload.severity {
        case "critical":
            return "重大"
        case "info":
            return "情報"
        default:
            return "警告"
        }
    }

    private var iconName: String {
        switch alertPayload.severity {
        case "critical":
            return "exclamationmark.octagon"
        case "info":
            return "info.circle"
        default:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch alertPayload.severity {
        case "critical":
            return .red
        case "info":
            return .accentColor
        default:
            return .orange
        }
    }
}

private struct VentureResearchMissionRow: View {
    let item: VentureResearchMissionItem
    let onAdopt: (VentureDeliverable) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel)
                    ProductOpsTokenView(channelLabel)
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let report = item.researchReport {
                    VentureResearchReportSummaryView(
                        summary: item.researchReportDeliverable?.summary ?? item.result?.summary ?? "",
                        report: report
                    )
                    if item.mission.status == "awaiting_review", let deliverable = item.researchReportDeliverable {
                        Button {
                            onAdopt(deliverable)
                        } label: {
                            Label("Learningとして採用", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if let result = item.result {
                    VentureResearchReportSummaryView(summary: result.summary, report: result.report)
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("X/TikTokの追加調査を実行中です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        switch item.mission.status {
        case "queued":
            return "待機中"
        case "dispatching":
            return "調査依頼済み"
        case "running":
            return "調査中"
        case "awaiting_review":
            return "結果確認"
        case "failed":
            return "失敗"
        case "completed":
            return "完了"
        case "canceled":
            return "キャンセル"
        default:
            return item.mission.status
        }
    }

    private var channelLabel: String {
        switch item.mission.channel {
        case "tiktok":
            return "TikTok"
        case "x":
            return "X"
        default:
            return item.mission.channel
        }
    }

    private var iconName: String {
        switch item.mission.status {
        case "awaiting_review":
            return "doc.text.magnifyingglass"
        case "failed":
            return "exclamationmark.triangle"
        case "completed":
            return "checkmark.circle"
        case "canceled":
            return "xmark.circle"
        default:
            return "magnifyingglass"
        }
    }

    private var tint: Color {
        switch item.mission.status {
        case "failed":
            return .red
        case "awaiting_review":
            return .orange
        case "completed":
            return .green
        default:
            return .accentColor
        }
    }
}

private struct VentureDecisionBriefSummaryView: View {
    let summary: String
    let brief: VentureDecisionBriefDeliverable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProductChangeSection(title: "決めたいこと", items: [brief.decisionQuestion])
            ProductChangeSection(title: "おすすめ", items: [brief.recommendation], tint: .primary)
            ProductChangeSection(title: "根拠", items: brief.reasons)
            ProductChangeSection(title: "反対材料", items: brief.contraryEvidence, tint: .orange)
            ProductChangeSection(title: "リスク", items: brief.risks, tint: .orange)
            ProductChangeSection(title: "未知", items: brief.unknowns)
            ProductChangeSection(title: "次の操作", items: brief.nextOperations, tint: .accentColor)
        }
    }
}

private struct VentureDeliverableDecodingErrorView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("成果物を表示できません", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Text(title)
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct VentureResearchReportSummaryView: View {
    let summary: String
    let report: VentureResearchReportDeliverable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProductChangeSection(title: "結論", items: [report.conclusion].filter { !$0.isEmpty })
            ProductChangeSection(title: "重要な発見", items: report.findings.prefixArray(3))
            ProductChangeSection(title: "支持", items: report.supportingEvidence.prefixArray(2), tint: .green)
            ProductChangeSection(title: "反例", items: report.contradictingEvidence.prefixArray(2), tint: .orange)
            ProductChangeSection(title: "未確認", items: (report.unknowns + report.nextQuestions).prefixArray(3))

            if !report.sources.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(report.sources.prefix(2)), id: \.self) { source in
                        if let url = URL(string: source), url.scheme != nil {
                            ProductOpsExternalLinkButton(destination: url) {
                                Label("Source", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                            }
                        } else {
                            ProductOpsTokenView(source)
                        }
                    }
                }
            }
        }
    }
}

private struct VentureResearchReportDetailView: View {
    let summary: String
    let report: VentureResearchReportDeliverable
    let copyMarkdown: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let artifactMarkdown = report.artifactMarkdown {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("成果物本文")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            copyMarkdown(artifactMarkdown)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("成果物本文をコピー")
                    }
                    ProductOpsMarkdownView(markdown: artifactMarkdown)
                }
            } else if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProductChangeSection(title: "調査テーマ", items: [report.researchQuestion].filter { !$0.isEmpty })
            ProductChangeSection(title: "結論", items: [report.conclusion].filter { !$0.isEmpty })
            ProductChangeSection(title: "重要な発見", items: report.findings)
            ProductChangeSection(title: "支持する根拠", items: report.supportingEvidence, tint: .green)
            ProductChangeSection(title: "反例", items: report.contradictingEvidence, tint: .orange)
            ProductChangeSection(title: "まだ分からないこと", items: report.unknowns)
            ProductChangeSection(title: "次に確認すること", items: report.nextQuestions)

            if !report.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("情報源")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(report.sources.enumerated()), id: \.offset) { _, source in
                        if let url = researchSourceURL(source) {
                            ProductOpsExternalLinkButton(destination: url) {
                                Label(researchSourceLabel(source, url: url), systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        } else {
                            Text(source)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let executionLog = report.executionLog {
                DisclosureGroup("実行ログ") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let grokExecution = report.grokExecution {
                            LabeledContent(
                                "要求設定",
                                value: "\(grokExecution.requested.surface) / \(grokExecution.requested.mode) / \(grokExecution.requested.model) / \(grokExecution.requested.reasoning)"
                            )
                            LabeledContent(
                                "適用設定",
                                value: appliedGrokExecutionLabel(grokExecution.applied)
                            )
                            if let url = URL(string: grokExecution.applied.pageURL) {
                                ProductOpsExternalLinkButton(destination: url) {
                                    Label("Grok.comの会話を開く", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                        LabeledContent("確認件数", value: String(executionLog.checkedCount))
                        LabeledContent("採用件数", value: String(executionLog.selectedCount))
                        LabeledContent("除外件数", value: String(executionLog.excludedCount))
                        ProductChangeSection(title: "検索語", items: executionLog.queries)
                        ProductChangeSection(title: "制約・不足", items: executionLog.limitations)
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
            }

            if let rawResult = report.rawResult {
                DisclosureGroup("Raw result") {
                    Text(rawResult.prettyPrintedJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func researchSourceURL(_ source: String) -> URL? {
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private func appliedGrokExecutionLabel(_ execution: VentureGrokExecution.Applied) -> String {
        let model = execution.modelLabel ?? "モデル表示なし"
        let reasoning = execution.reasoningLabel ?? execution.reasoningAppliedBy
        return "\(execution.surface) / \(execution.modeLabel) / \(model) / \(reasoning)"
    }

    private func researchSourceLabel(_ source: String, url: URL) -> String {
        guard let host = url.host else { return source }
        let location = host + url.path
        return location.isEmpty ? source : location
    }
}

private struct VentureMessageMissionRow: View {
    let item: VentureMessageMissionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel)
                    ProductOpsTokenView(channelLabel)
                    ProductOpsTokenView("送信なし")
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = item.message {
                    VentureMessageDraftView(
                        summary: item.messageDeliverable?.summary ?? item.result?.summary ?? "",
                        message: message
                    )
                } else if let result = item.result {
                    VentureMessageDraftView(summary: result.summary, message: result.message)
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Codex app serverでメッセージ下書きを作成中です。外部送信は行いません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        switch item.mission.status {
        case "queued":
            return "待機中"
        case "dispatching":
            return "文案依頼済み"
        case "running":
            return "作成中"
        case "awaiting_review":
            return "文案確認"
        case "failed":
            return "失敗"
        case "completed":
            return "完了"
        case "canceled":
            return "キャンセル"
        default:
            return item.mission.status
        }
    }

    private var channelLabel: String {
        switch item.mission.channel {
        case "x_post":
            return "X投稿"
        case "x_reply":
            return "X返信"
        case "direct_message":
            return "DM"
        case "email":
            return "メール"
        default:
            return item.mission.channel
        }
    }

    private var iconName: String {
        switch item.mission.status {
        case "awaiting_review":
            return "text.bubble"
        case "failed":
            return "exclamationmark.triangle"
        case "completed":
            return "checkmark.circle"
        case "canceled":
            return "xmark.circle"
        default:
            return "square.and.pencil"
        }
    }

    private var tint: Color {
        switch item.mission.status {
        case "failed":
            return .red
        case "awaiting_review":
            return .orange
        case "completed":
            return .green
        default:
            return .accentColor
        }
    }
}

private struct VentureMessageDraftView: View {
    let summary: String
    let message: VentureMessageDeliverable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subject = message.subject, !subject.isEmpty {
                ProductChangeSection(title: "件名", items: [subject])
            }

            ProductChangeSection(title: "候補", items: message.candidateRecipients.prefixArray(3))

            VStack(alignment: .leading, spacing: 4) {
                Text("本文")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("この画面では送信しません。送信は別Proposalの承認後に扱います。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VentureVerificationMissionRow: View {
    let item: VentureVerificationMissionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel)
                    ProductOpsTokenView(sourceKindLabel)
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let report = item.verificationReport {
                    VentureVerificationReportSummaryView(
                        summary: item.verificationReportDeliverable?.summary ?? item.result?.summary ?? "",
                        report: report
                    )
                } else if let result = item.result {
                    VentureVerificationReportSummaryView(summary: result.summary, report: result.report)
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Codex app serverで成果物を検証中です。外部送信や本番操作は行いません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        switch item.mission.status {
        case "queued":
            return "待機中"
        case "dispatching":
            return "検証依頼済み"
        case "running":
            return "検証中"
        case "awaiting_review":
            return "検証結果"
        case "failed":
            return "失敗"
        case "completed":
            return "完了"
        case "canceled":
            return "キャンセル"
        default:
            return item.mission.status
        }
    }

    private var sourceKindLabel: String {
        switch item.mission.sourceDeliverableKind {
        case "product_change":
            return "プロダクト変更"
        case "research_report":
            return "調査結果"
        case "message":
            return "文案"
        default:
            return item.mission.sourceDeliverableKind
        }
    }

    private var iconName: String {
        switch item.mission.status {
        case "awaiting_review":
            return "checkmark.seal"
        case "failed":
            return "exclamationmark.triangle"
        case "completed":
            return "checkmark.circle"
        case "canceled":
            return "xmark.circle"
        default:
            return "checkmark.shield"
        }
    }

    private var tint: Color {
        switch item.mission.status {
        case "failed":
            return .red
        case "awaiting_review":
            return .orange
        case "completed":
            return .green
        default:
            return .accentColor
        }
    }
}

private struct ProductOpsTranslucentActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.2 : 0.1))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct VentureVerificationReportSummaryView: View {
    let summary: String
    let report: VentureVerificationReportDeliverable
    var isCompact = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ProductOpsTokenView(verdictLabel, systemImage: verdictIcon)
            }

            if !report.checkedCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("検証項目")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(visibleCriteria, id: \.criterion) { criterion in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: checkIcon(criterion.status))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(checkTint(criterion.status))
                                .frame(width: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(criterion.criterion)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if !criterion.detail.isEmpty {
                                    Text(criterion.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            ProductChangeSection(title: "リスク", items: visibleRisks, tint: .orange)
            ProductChangeSection(title: "次対応", items: visibleFollowUps)
        }
    }

    private var visibleCriteria: [VentureVerificationReportDeliverable.CheckedCriterion] {
        isCompact ? Array(report.checkedCriteria.prefix(4)) : report.checkedCriteria
    }

    private var visibleRisks: [String] {
        isCompact ? Array(report.risks.prefix(3)) : report.risks
    }

    private var visibleFollowUps: [String] {
        isCompact ? Array(report.requiredFollowUps.prefix(3)) : report.requiredFollowUps
    }

    private var verdictLabel: String {
        switch report.verdict {
        case "passed":
            return "合格"
        case "failed":
            return "不合格"
        default:
            return "要確認"
        }
    }

    private var verdictIcon: String {
        switch report.verdict {
        case "passed":
            return "checkmark.seal"
        case "failed":
            return "xmark.seal"
        default:
            return "questionmark.circle"
        }
    }

    private func checkIcon(_ status: String) -> String {
        switch status {
        case "passed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.circle.fill"
        default:
            return "minus.circle"
        }
    }

    private func checkTint(_ status: String) -> Color {
        switch status {
        case "passed":
            return .green
        case "failed":
            return .red
        default:
            return .secondary
        }
    }
}

private struct VentureKnowledgeChangeMissionRow: View {
    let item: VentureKnowledgeChangeMissionItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel)
                    ProductOpsTokenView("方針変更")
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let knowledgeChange = item.knowledgeChange {
                    VentureKnowledgeChangeSummaryView(
                        summary: item.knowledgeChangeDeliverable?.summary ?? item.result?.summary ?? "",
                        knowledgeChange: knowledgeChange,
                        currentPolicy: nil
                    )
                } else if let result = item.result {
                    VentureKnowledgeChangeSummaryView(
                        summary: result.summary,
                        knowledgeChange: result.knowledgeChange,
                        currentPolicy: nil
                    )
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("事業認識の変化から、方針へ反映すべき差分を確認しています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        switch item.mission.status {
        case "queued":
            return "待機中"
        case "dispatching":
            return "整理依頼済み"
        case "running":
            return "整理中"
        case "awaiting_review":
            return "更新候補"
        case "failed":
            return "失敗"
        case "completed":
            return "完了"
        case "canceled":
            return "キャンセル"
        default:
            return item.mission.status
        }
    }

    private var iconName: String {
        switch item.mission.status {
        case "awaiting_review":
            return "lightbulb"
        case "failed":
            return "exclamationmark.triangle"
        case "completed":
            return "checkmark.circle"
        case "canceled":
            return "xmark.circle"
        default:
            return "books.vertical"
        }
    }

    private var tint: Color {
        switch item.mission.status {
        case "failed":
            return .red
        case "awaiting_review":
            return .orange
        case "completed":
            return .green
        default:
            return .accentColor
        }
    }
}

private struct VentureKnowledgeChangeSummaryView: View {
    let summary: String
    let knowledgeChange: VentureKnowledgeChangeDeliverable
    let currentPolicy: VenturePolicy?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isStale {
                Label("現在の方針Versionと候補の基準Versionが異なります。採用前に再生成が必要です。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(fieldChanges) { change in
                VStack(alignment: .leading, spacing: 6) {
                    Text(change.label)
                        .font(.caption.weight(.semibold))
                    ProductChangeSection(title: "変更前", items: change.before)
                    ProductChangeSection(title: "変更後", items: change.after, tint: .primary)
                }
                .padding(.vertical, 2)
            }

            ProductChangeSection(title: "変更理由", items: [knowledgeChange.rationale], tint: .primary)
            ProductChangeSection(title: "今後の影響", items: [knowledgeChange.expectedImpact], tint: .primary)
            ProductChangeSection(title: "反対材料", items: knowledgeChange.contraryEvidence)
            ProductChangeSection(title: "根拠", items: knowledgeChange.sourceRefs.map(referenceLabel))

            HStack(spacing: 6) {
                ProductOpsTokenView(riskLabel)
                ProductOpsTokenView("Strategy: \(shortId(knowledgeChange.baseStrategyVersionId))")
                ProductOpsTokenView("Frame: \(shortId(knowledgeChange.baseDecisionFrameVersionId))")
            }
        }
    }

    private var isStale: Bool {
        guard let currentPolicy else { return false }
        return currentPolicy.strategyVersionId != knowledgeChange.baseStrategyVersionId
            || currentPolicy.decisionFrameVersionId != knowledgeChange.baseDecisionFrameVersionId
    }

    private var fieldChanges: [VenturePolicyFieldChange] {
        var changes: [VenturePolicyFieldChange] = []

        if let next = knowledgeChange.nextStrategy {
            appendChange("目的", currentPolicy.map { [$0.mission] }, [next.mission], to: &changes)
            appendChange("対象顧客", currentPolicy.map { segmentLines($0.targetSegments) }, segmentLines(next.targetSegments), to: &changes)
            appendChange("期待する成果", currentPolicy?.desiredOutcomes, next.desiredOutcomes, to: &changes)
            appendChange("商業仮説", currentPolicy?.commercialHypotheses, next.commercialHypotheses, to: &changes)
            appendChange("Focus", currentPolicy?.focusAreas, next.focusAreas, to: &changes)
            appendChange("除外事項", currentPolicy?.exclusions, next.exclusions, to: &changes)
            appendChange("研究制約", currentPolicy?.researchGuardrails, next.researchGuardrails, to: &changes)
            appendChange("実装・提供制約", currentPolicy?.deliveryGuardrails, next.deliveryGuardrails, to: &changes)
        }

        if let next = knowledgeChange.nextDecisionFrame {
            appendChange("事業段階", currentPolicy.map { [$0.stage] }, [next.stage], to: &changes)
            appendChange("現在の目的", currentPolicy?.objectives, next.objectiveIds, to: &changes)
            appendChange("評価基準", currentPolicy.map { lensLines($0.lenses) }, lensLines(next.lenses), to: &changes)
            appendChange("Hard Gate", currentPolicy.map { gateLines($0.hardGates) }, gateLines(next.hardGates), to: &changes)
            appendChange("最大推薦数", nil, [String(next.maxRecommendations)], to: &changes)
        }

        return changes
    }

    private var riskLabel: String {
        switch knowledgeChange.risk {
        case "medium": return "中リスク"
        case "high": return "高リスク"
        case "critical": return "重大"
        default: return knowledgeChange.risk
        }
    }

    private func appendChange(
        _ label: String,
        _ before: [String]?,
        _ after: [String],
        to changes: inout [VenturePolicyFieldChange]
    ) {
        let previous = before ?? ["基準Versionの方針"]
        guard previous != after else { return }
        changes.append(VenturePolicyFieldChange(label: label, before: previous, after: after))
    }

    private func segmentLines(_ segments: [VenturePolicyTargetSegment]) -> [String] {
        segments.map { "\($0.label): \($0.description)" }
    }

    private func lensLines(_ lenses: [VenturePolicyDecisionLens]) -> [String] {
        lenses.map { "\($0.label)（\($0.weight.formatted())）" }
    }

    private func gateLines(_ gates: [VenturePolicyHardGate]) -> [String] {
        gates.map { "\($0.label): \($0.description)" }
    }

    private func referenceLabel(_ reference: VentureKnowledgeReference) -> String {
        let relation: String
        switch reference.relation {
        case "supports": relation = "支持"
        case "contradicts": relation = "反例"
        default: relation = "文脈"
        }
        return "\(reference.kind) / \(shortId(reference.id)) / \(relation)"
    }

    private func shortId(_ id: String) -> String {
        id.count > 12 ? "\(id.prefix(12))…" : id
    }
}

private struct VenturePolicyFieldChange: Identifiable {
    let label: String
    let before: [String]
    let after: [String]

    var id: String { label }
}

private struct VentureProductChangeSummaryView: View {
    let summary: String
    let productChange: VentureProductChangeDeliverable
    let supportingPullRequests: [VentureDevelopmentMissionResult.PullRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !productChange.userVisibleImpact.isEmpty {
                ProductChangeSection(title: "ユーザーへの影響", items: [productChange.userVisibleImpact])
            }

            ProductChangeSection(title: "変わったこと", items: productChange.changedBehavior.prefixArray(3))

            if !productChange.changedRepositories.isEmpty {
                HStack(spacing: 6) {
                    ForEach(productChange.changedRepositories.prefix(3), id: \.self) { repository in
                        ProductOpsTokenView(repository)
                    }
                }
            }

            if !pullRequestURLs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(pullRequestURLs.prefix(2)), id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            ProductOpsExternalLinkButton(destination: url) {
                                Label("Draft PR", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }

            if !productChange.checks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("検証")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(productChange.checks.prefix(3), id: \.name) { check in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: checkIcon(check.status))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(checkTint(check.status))
                                .frame(width: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(check.name)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if !check.detail.isEmpty {
                                    Text(check.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }

            ProductChangeSection(title: "未解決", items: productChange.unresolvedIssues.prefixArray(3), tint: .orange)
        }
    }

    private var pullRequestURLs: [String] {
        var seen: Set<String> = []
        return (productChange.pullRequests + supportingPullRequests.map(\.url)).filter { url in
            guard !url.isEmpty, !seen.contains(url) else {
                return false
            }
            seen.insert(url)
            return true
        }
    }

    private func checkIcon(_ status: String) -> String {
        switch status {
        case "passed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.circle.fill"
        default:
            return "minus.circle"
        }
    }

    private func checkTint(_ status: String) -> Color {
        switch status {
        case "passed":
            return .green
        case "failed":
            return .red
        default:
            return .secondary
        }
    }
}

private struct ProductChangeSection: View {
    let title: String
    let items: [String]
    var tint: Color = .secondary

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 5) {
                        Text("・")
                            .font(.caption2)
                            .foregroundStyle(tint)
                        Text(item)
                            .font(.caption2)
                            .foregroundStyle(tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private extension Array where Element == String {
    func prefixArray(_ count: Int) -> [String] {
        Array(prefix(count))
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
    let showsMoveHandle: Bool
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

            if showsMoveHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
                    .accessibilityLabel("移動")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .modifier(ItemRowDragModifier(id: item.id, isEnabled: showsMoveHandle))
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
