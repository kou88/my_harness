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

    private enum NextActionsSheet: Identifiable {
        case needMemo
        case proposalFeedback(PendingVentureProposalFeedback)
        case proposalDetail(VentureDecisionInboxItem)
        case missionDetail(VentureMissionSummaryItem, requestedAction: String?)
        case alertDetail(VentureMonitoringAlertItem)

        var id: String {
            switch self {
            case .needMemo:
                return "needMemo"
            case .proposalFeedback(let feedback):
                return feedback.id
            case .proposalDetail(let item):
                return "proposal-\(item.id)"
            case .missionDetail(let item, let requestedAction):
                return "mission-\(item.id)-\(requestedAction ?? "detail")"
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
            case .proposalFeedback(let feedback):
                VentureProposalFeedbackSheet(
                    state: productOpsState,
                    pending: feedback
                )
            case .proposalDetail(let item):
                VentureProposalDetailSheet(
                    state: productOpsState,
                    item: item,
                    onApprove: { decide(item, .approved) },
                    onLater: { decide(item, .deferred) },
                    onReject: { decide(item, .rejected) }
                )
            case .missionDetail(let item, let requestedAction):
                VentureMissionDetailSheet(
                    state: productOpsState,
                    item: item,
                    requestedAction: requestedAction
                )
            case .alertDetail(let item):
                VentureMonitoringAlertDetailSheet(item: item)
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

        Section("おすすめ  \(recommendations.count)") {
            if recommendations.isEmpty {
                emptyRow("おすすめはありません")
            } else {
                ForEach(recommendations) { item in
                    proposalCompactRow(item)
                }
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
                        isWorking: false,
                        onOpen: { presentedSheet = .alertDetail(item) }
                    )
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
            contextLabel: "おすすめ",
            isWorking: isWorking,
            onOpen: { presentedSheet = .proposalDetail(item) }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: item.approvalRisk == "low" && item.actionKind != "build_experiment") {
            if item.approvalRisk == "low" && item.actionKind != "build_experiment" {
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
            Button(role: .destructive) {
                decide(item, .rejected)
            } label: {
                Label("却下", systemImage: "xmark")
            }
            .disabled(isWorking)

            Button {
                decide(item, .deferred)
            } label: {
                Label("あとで", systemImage: "clock")
            }
            .tint(.orange)
            .disabled(isWorking)
        }
        .accessibilityAction(named: Text(item.approvalLabel)) { decide(item, .approved) }
        .accessibilityAction(named: Text("あとで")) { decide(item, .deferred) }
        .accessibilityAction(named: Text("却下")) { decide(item, .rejected) }
    }

    private func missionCompactRow(_ item: VentureMissionSummaryItem) -> some View {
        let isWorking = productOpsState.isMutatingMission(id: item.id)
        return CompactNextActionRow(
            title: item.title,
            contextLabel: missionSectionLabel(item.status),
            isWorking: isWorking,
            onOpen: { presentedSheet = .missionDetail(item, requestedAction: nil) }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if item.availableActions.contains("adopt") {
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
                    presentedSheet = .missionDetail(item, requestedAction: "retry")
                } label: {
                    Label("再実行", systemImage: "arrow.clockwise")
                }
                .tint(.green)
                .disabled(isWorking)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                    presentedSheet = .missionDetail(item, requestedAction: "reject")
                } label: {
                    Label("却下", systemImage: "xmark")
                }
                .disabled(isWorking)
            }
            if item.availableActions.contains("request_revision") {
                Button {
                    presentedSheet = .missionDetail(item, requestedAction: "request_revision")
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

    private func decide(_ item: VentureDecisionInboxItem, _ decision: VentureDecision) {
        if decision == .approved {
            Task {
                await productOpsState.decideVentureProposal(
                    item,
                    decision: decision,
                    reasonCodes: approvedReasonCodes(for: item)
                )
            }
        } else {
            presentedSheet = .proposalFeedback(PendingVentureProposalFeedback(item: item, decision: decision))
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
    let item: VentureDecisionInboxItem
    let onApprove: () -> Void
    let onLater: () -> Void
    let onReject: () -> Void
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
                        actionBar
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func proposalContent(_ detail: VentureProposalDetail) -> some View {
        Section {
            Text(detail.proposal.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }

        detailSection("なぜ今やるのか", text: detail.proposal.whyNow)
        detailSection("提案内容", text: detail.proposal.summary)
        detailSection("期待する結果", text: detail.proposal.expectedOutcome)

        if !detail.proposal.targetUnknowns.isEmpty {
            listSection("対象の未知", items: detail.proposal.targetUnknowns)
        }
        if !detail.proposal.unblocksDecision.isEmpty {
            detailSection("この結果で可能になる判断", text: detail.proposal.unblocksDecision)
        }
        if let opportunity = detail.opportunity {
            Section("Opportunity") {
                Text(opportunity.problemStatement)
                Text(opportunity.desiredOutcomeStatement)
                    .foregroundStyle(.secondary)
                if !opportunity.evidenceSummary.isEmpty {
                    Text(opportunity.evidenceSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let hypothesis = detail.hypothesis {
            detailSection("検証する仮説", text: hypothesis.statement)
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
                LabeledContent("総合評価", value: String(format: "%.2f", detail.assessment.totalScore))
                ForEach(detail.assessment.scores.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: String(format: "%.2f", detail.assessment.scores[key] ?? 0))
                }
                LabeledContent("評価方式", value: detail.assessment.algorithmKey)
                LabeledContent("生成モデル", value: detail.recommendation.metadata.draftingModel)
                LabeledContent("Prompt", value: detail.recommendation.metadata.draftingPromptVersion)
                LabeledContent("Rating", value: detail.recommendation.metadata.ratingAlgorithmVersion)
                Text("Context: \(detail.recommendation.metadata.contextSnapshotHash)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
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
        HStack(spacing: 8) {
            Button {
                dismiss()
                onApprove()
            } label: {
                Label(item.approvalLabel, systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)

            Button("あとで") {
                dismiss()
                onLater()
            }
            .buttonStyle(.bordered)

            Button("却下", role: .destructive) {
                dismiss()
                onReject()
            }
            .buttonStyle(.bordered)
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await state.fetchProposalDetail(item)
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

private struct VentureMonitoringAlertDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: VentureMonitoringAlertItem

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
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
    let item: VentureMissionSummaryItem
    let requestedAction: String?
    @State private var detail: VentureMissionDetail?
    @State private var errorMessage: String?
    @State private var operationErrorMessage: String?
    @State private var feedbackRequest: MissionFeedbackRequest?
    @State private var feedbackText = ""
    @State private var isSubmitting = false
    @State private var didHandleRequestedAction = false

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
            .navigationTitle(item.kindLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                await load()
                handleRequestedActionIfNeeded()
            }
            .sheet(item: $feedbackRequest) { request in
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
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProductOpsTokenView(statusLabel(detail.mission.status))
                    ProductOpsTokenView(detail.mission.primaryDeliverableSpec.kind)
                    if let attempt = detail.currentAttempt {
                        ProductOpsTokenView("Attempt \(attempt.attemptNumber)")
                    }
                }
                Text(detail.mission.primaryDeliverableSpec.title)
                    .font(.headline)
                Text(detail.currentAttempt?.instructionSnapshot.objective ?? detail.mission.primaryDeliverableSpec.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProductChangeSection(
                    title: "合格条件",
                    items: detail.mission.primaryDeliverableSpec.acceptanceCriteria
                )
            }
            .padding(.vertical, 4)
        }

        Section("最新の成果物") {
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
                        ForEach(detail.reviews.filter { $0.attemptId == attempt.id }) { review in
                            Text(reviewSummary(review))
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
        if let value = deliverable.productChangePayload {
            VentureProductChangeSummaryView(summary: deliverable.displaySummary, productChange: value, supportingPullRequests: [])
        } else if let value = deliverable.researchReportPayload {
            VentureResearchReportSummaryView(summary: deliverable.displaySummary, report: value)
        } else if let value = deliverable.messagePayload {
            VentureMessageDraftView(summary: deliverable.displaySummary, message: value)
        } else if let value = deliverable.verificationReportPayload {
            VentureVerificationReportSummaryView(
                summary: deliverable.displaySummary,
                report: value,
                isCompact: false
            )
        } else if let value = deliverable.knowledgeChangePayload {
            VentureKnowledgeChangeSummaryView(summary: deliverable.displaySummary, knowledgeChange: value)
        } else if let value = deliverable.alertPayload {
            VStack(alignment: .leading, spacing: 6) {
                Text(deliverable.displaySummary).font(.subheadline)
                ProductChangeSection(title: "検知", items: [value.detectedIssue])
                ProductChangeSection(title: "推奨対応", items: [value.recommendedAction])
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(deliverable.title).font(.subheadline.weight(.semibold))
                Text(deliverable.displaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func missionActions(_ detail: VentureMissionDetail) -> some View {
        if detail.availableActions.contains("adopt") {
            Button {
                startSubmission { await adopt(detail) }
            } label: {
                Label("採用する", systemImage: "checkmark.circle")
            }
            .disabled(isSubmitting)
        }
        if detail.availableActions.contains("request_revision") {
            Button {
                feedbackText = ""
                feedbackRequest = MissionFeedbackRequest(kind: .revision)
            } label: {
                Label("修正して再実行", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isSubmitting)
        }
        if detail.availableActions.contains("reject") {
            Button(role: .destructive) {
                feedbackText = ""
                feedbackRequest = MissionFeedbackRequest(kind: .reject)
            } label: {
                Label("却下して終了", systemImage: "xmark.circle")
            }
            .disabled(isSubmitting)
        }
        if detail.availableActions.contains("retry") {
            Button {
                feedbackText = ""
                feedbackRequest = MissionFeedbackRequest(kind: .retry)
            } label: {
                Label("再実行", systemImage: "arrow.clockwise")
            }
            .disabled(isSubmitting)
        }
        if detail.availableActions.contains("cancel") {
            Button(role: .destructive) {
                startSubmission { await cancel(detail) }
            } label: {
                Label("キャンセル", systemImage: "stop.circle")
            }
            .disabled(isSubmitting)
        }
    }

    private func missionActionBar(_ detail: VentureMissionDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                missionActions(detail)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await state.fetchMissionDetail(item)
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
                self.detail = try await state.reviewMissionDeliverable(
                    detail: detail,
                    decision: "rejected",
                    feedback: feedback
                )
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

    private func startSubmission(_ operation: @escaping @MainActor () async -> Void) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { await operation() }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
        case "awaiting_review": return "結果確認"
        case "completed": return "採用済み"
        case "failed": return "失敗"
        case "canceled": return "キャンセル"
        case "rejected": return "却下"
        default: return status
        }
    }

    private func attemptStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "待機中"
        case "dispatching": return "依頼中"
        case "running": return "実行中"
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
        case "knowledge_change": return "採用しても方針の正本は自動更新しません。"
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
                        Link(destination: url) {
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
                            Link(destination: url) {
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
                    ProductOpsTokenView("方針v\(item.mission.projectPolicyVersion)")
                }
                Text(item.mission.objective)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let knowledgeChange = item.knowledgeChange {
                    VentureKnowledgeChangeSummaryView(
                        summary: item.knowledgeChangeDeliverable?.summary ?? item.result?.summary ?? "",
                        knowledgeChange: knowledgeChange
                    )
                } else if let result = item.result {
                    VentureKnowledgeChangeSummaryView(summary: result.summary, knowledgeChange: result.knowledgeChange)
                } else if let error = item.mission.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("LearningからKnowledge更新候補を作成中です。方針はまだ更新しません。")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProductChangeSection(title: "現在", items: [knowledgeChange.currentState].filter { !$0.isEmpty })
            ProductChangeSection(title: "変更候補", items: [knowledgeChange.proposedState].filter { !$0.isEmpty }, tint: .primary)
            ProductChangeSection(title: "理由", items: [knowledgeChange.reason].filter { !$0.isEmpty })

            if !knowledgeChange.sourceIds.isEmpty {
                HStack(spacing: 6) {
                    ForEach(knowledgeChange.sourceIds.prefix(3), id: \.self) { sourceId in
                        ProductOpsTokenView(sourceId)
                    }
                }
            }

            Text("採用しても、この画面では正本の方針を自動更新しません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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
                            Link(destination: url) {
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
