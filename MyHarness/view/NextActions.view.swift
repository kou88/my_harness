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
        let recommended = payload.items.first
        let remaining = Array(payload.items.dropFirst())
        let developmentMissionItems = productOpsState.developmentMissionItems
        let researchMissionItems = productOpsState.researchMissionItems
        let messageMissionItems = productOpsState.messageMissionItems
        let verificationMissionItems = productOpsState.verificationMissionItems
        let reviewMissions = developmentMissionItems.filter { $0.mission.status == "awaiting_review" || $0.mission.status == "failed" }
        let reviewResearchMissions = researchMissionItems.filter { $0.mission.status == "awaiting_review" || $0.mission.status == "failed" }
        let reviewMessageMissions = messageMissionItems.filter { $0.mission.status == "awaiting_review" || $0.mission.status == "failed" }
        let reviewVerificationMissions = verificationMissionItems.filter { $0.mission.status == "awaiting_review" || $0.mission.status == "failed" }
        let runningMissions = developmentMissionItems.filter { ["queued", "dispatching", "running"].contains($0.mission.status) }
        let runningResearchMissions = researchMissionItems.filter { ["queued", "dispatching", "running"].contains($0.mission.status) }
        let runningMessageMissions = messageMissionItems.filter { ["queued", "dispatching", "running"].contains($0.mission.status) }
        let runningVerificationMissions = verificationMissionItems.filter { ["queued", "dispatching", "running"].contains($0.mission.status) }

        if let recommended {
            Section("おすすめ") {
                RecommendedVentureProposalCard(
                    item: recommended,
                    isWorking: productOpsState.isPostingVentureDecision,
                    onApprove: { decide(recommended, .approved) },
                    onLater: { decide(recommended, .deferred) },
                    onReject: { decide(recommended, .rejected) }
                )
                .listRowSeparator(.hidden)
            }
        }

        if !reviewMissions.isEmpty || !reviewResearchMissions.isEmpty || !reviewMessageMissions.isEmpty || !reviewVerificationMissions.isEmpty {
            Section("結果確認") {
                ForEach(reviewMissions) { item in
                    VentureDevelopmentMissionRow(item: item)
                }
                ForEach(reviewResearchMissions) { item in
                    VentureResearchMissionRow(
                        item: item,
                        onAdopt: { deliverable in
                            Task { await productOpsState.adoptResearchLearning(deliverable: deliverable) }
                        }
                    )
                }
                ForEach(reviewMessageMissions) { item in
                    VentureMessageMissionRow(item: item)
                }
                ForEach(reviewVerificationMissions) { item in
                    VentureVerificationMissionRow(item: item)
                }
            }
        }

        Section("やること") {
            if remaining.isEmpty {
                emptyRow(recommended == nil ? "判断待ちはありません" : "他の判断待ちはありません")
            } else {
                ForEach(remaining) { item in
                    VentureProposalRow(
                        item: item,
                        isWorking: productOpsState.isPostingVentureDecision,
                        onApprove: { decide(item, .approved) },
                        onLater: { decide(item, .deferred) },
                        onReject: { decide(item, .rejected) }
                    )
                }
            }
        }

        if !runningMissions.isEmpty || !runningResearchMissions.isEmpty || !runningMessageMissions.isEmpty || !runningVerificationMissions.isEmpty {
            Section("進行中") {
                ForEach(runningMissions) { item in
                    VentureDevelopmentMissionRow(item: item)
                }
                ForEach(runningResearchMissions) { item in
                    VentureResearchMissionRow(item: item, onAdopt: { _ in })
                }
                ForEach(runningMessageMissions) { item in
                    VentureMessageMissionRow(item: item)
                }
                ForEach(runningVerificationMissions) { item in
                    VentureVerificationMissionRow(item: item)
                }
            }
        }

        if case .failed(let message) = productOpsState.developmentMissionsState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

        if case .failed(let message) = productOpsState.researchMissionsState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

        if case .failed(let message) = productOpsState.messageMissionsState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

        if case .failed(let message) = productOpsState.verificationMissionsState {
            Section {
                ProductOpsMessageBar(text: message, systemImage: "exclamationmark.triangle")
                    .listRowSeparator(.hidden)
            }
        }

        if payload.refreshRequired {
            Section {
                ProductOpsMessageBar(text: "方針または判断軸が更新されています。再読み込みしてください。", systemImage: "arrow.triangle.2.circlepath")
                    .listRowSeparator(.hidden)
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

    private func decide(_ item: VentureDecisionInboxItem, _ decision: VentureDecision) {
        Task {
            await productOpsState.decideVentureProposal(item, decision: decision)
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
                    ForEach(report.checkedCriteria.prefix(4), id: \.criterion) { criterion in
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

            ProductChangeSection(title: "リスク", items: report.risks.prefixArray(3), tint: .orange)
            ProductChangeSection(title: "次対応", items: report.requiredFollowUps.prefixArray(3))
        }
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
