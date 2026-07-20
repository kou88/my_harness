import Foundation
import Observation

@MainActor
@Observable
final class ProductOpsState {
    enum LoadState<T: Hashable>: Hashable {
        case idle
        case loading
        case loaded(T)
        case failed(String)
    }

    var nextActionsState: LoadState<NextActionsPayload> = .idle
    var decisionInboxState: LoadState<VentureDecisionInboxPayload> = .idle
    var missionItemsState: LoadState<VentureMissionSummaryPage> = .idle
    var developmentMissionsState: LoadState<[VentureDevelopmentMissionItem]> = .idle
    var researchMissionsState: LoadState<[VentureResearchMissionItem]> = .idle
    var researchClipsState: LoadState<VentureResearchClipPage> = .idle
    var messageMissionsState: LoadState<[VentureMessageMissionItem]> = .idle
    var verificationMissionsState: LoadState<[VentureVerificationMissionItem]> = .idle
    var monitoringAlertsState: LoadState<[VentureMonitoringAlertItem]> = .idle
    var missionCatalogState: LoadState<VentureMissionCatalogPayload> = .idle
    var missionProgressState: LoadState<VentureMissionProgressPayload> = .idle
    var needsState: LoadState<[Need]> = .idle
    var candidatesState: LoadState<[NeedCandidate]> = .idle
    var developmentTasksState: LoadState<[DevelopmentTask]> = .idle
    var policyState: LoadState<VenturePolicy> = .idle
    var isPostingMemo = false
    var isSavingPolicy = false
    var isPostingVentureDecision = false
    var isRequestingRecommendationHeartbeat = false
    var isScanningMonitoringAlerts = false
    var isCreatingDirectMission = false
    var isUpdatingMission = false
    var isLoadingMoreMissionItems = false
    var message: String?
    var configurationErrorMessage: String?

    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?
    private let copyText: CopyTextUseCase
    private let projectId: String
    private let ventureId: String
    private let nextActionOrderStorageKey: String
    private var mutatingNeedIds: Set<String> = []
    private var updatingDevelopmentTaskIds: Set<String> = []
    private var startingCodexTaskIds: Set<String> = []
    private var mutatingVentureProposalIds: Set<String> = []
    private var mutatingMissionIds: Set<String> = []
    private var mutatingResearchClipIds: Set<String> = []

    init(
        authSession: CognitoAuthSession?,
        apiClient: ActionInboxAPIClient?,
        copyText: CopyTextUseCase,
        projectId: String,
        configurationErrorMessage: String?
    ) {
        self.authSession = authSession
        self.apiClient = apiClient
        self.copyText = copyText
        self.projectId = projectId
        ventureId = ProductOpsProject.landlordSaaSVenture
        nextActionOrderStorageKey = "myHarness.nextActionTodoOrder.\(projectId)"
        self.configurationErrorMessage = configurationErrorMessage
    }

    func copyMarkdown(_ markdown: String) {
        copyText.execute(markdown)
        message = "Markdownをコピーしました"
    }

    var isConfigured: Bool {
        apiClient != nil && authSession != nil
    }

    var isSignedIn: Bool {
        authSession?.isSignedIn == true
    }

    var candidates: [NeedCandidate] {
        guard case .loaded(let items) = candidatesState else {
            return []
        }
        return items
    }

    var nextActions: [NextActionItem] {
        guard case .loaded(let payload) = nextActionsState else {
            return []
        }
        return payload.items
    }

    var recommendedNextAction: NextActionItem? {
        nextActions.first { $0.status == "todo" || $0.status == "blocked" }
    }

    var decisionItems: [VentureDecisionInboxItem] {
        guard case .loaded(let payload) = decisionInboxState else {
            return []
        }
        return payload.items
    }

    var recommendedDecisionItem: VentureDecisionInboxItem? {
        decisionItems.first
    }

    var developmentMissionItems: [VentureDevelopmentMissionItem] {
        guard case .loaded(let items) = developmentMissionsState else {
            return []
        }
        return items
    }

    var researchMissionItems: [VentureResearchMissionItem] {
        guard case .loaded(let items) = researchMissionsState else {
            return []
        }
        return items
    }

    var researchClipItems: [VentureResearchClipListItem] {
        guard case .loaded(let page) = researchClipsState else { return [] }
        return page.items
    }

    var messageMissionItems: [VentureMessageMissionItem] {
        guard case .loaded(let items) = messageMissionsState else {
            return []
        }
        return items
    }

    var verificationMissionItems: [VentureVerificationMissionItem] {
        guard case .loaded(let items) = verificationMissionsState else {
            return []
        }
        return items
    }

    var monitoringAlertItems: [VentureMonitoringAlertItem] {
        guard case .loaded(let items) = monitoringAlertsState else {
            return []
        }
        return items
    }

    var missionSummaryItems: [VentureMissionSummaryItem] {
        guard case .loaded(let page) = missionItemsState else {
            return []
        }
        return page.items
    }

    var nextMissionCursor: String? {
        guard case .loaded(let page) = missionItemsState else {
            return nil
        }
        return page.nextCursor
    }

    var missionProgress: VentureMissionProgressPayload? {
        guard case .loaded(let payload) = missionProgressState else {
            return nil
        }
        return payload
    }

    var needs: [Need] {
        guard case .loaded(let items) = needsState else {
            return []
        }
        return items
    }

    var developmentTasks: [DevelopmentTask] {
        guard case .loaded(let items) = developmentTasksState else {
            return []
        }
        return items
    }

    var policy: VenturePolicy? {
        guard case .loaded(let policy) = policyState else {
            return nil
        }
        return policy
    }

    func reset() {
        nextActionsState = .idle
        decisionInboxState = .idle
        missionItemsState = .idle
        developmentMissionsState = .idle
        researchMissionsState = .idle
        researchClipsState = .idle
        messageMissionsState = .idle
        verificationMissionsState = .idle
        monitoringAlertsState = .idle
        missionCatalogState = .idle
        missionProgressState = .idle
        needsState = .idle
        candidatesState = .idle
        developmentTasksState = .idle
        policyState = .idle
        message = nil
        mutatingNeedIds.removeAll()
        updatingDevelopmentTaskIds.removeAll()
        startingCodexTaskIds.removeAll()
        mutatingVentureProposalIds.removeAll()
        mutatingMissionIds.removeAll()
        mutatingResearchClipIds.removeAll()
        isRequestingRecommendationHeartbeat = false
    }

    func loadRecommendationsIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadDecisionInbox()
    }

    func loadNextActionsIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadNextActions()
    }

    func loadNeedsIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadNeeds()
    }

    func loadDevelopmentTasksIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadDevelopmentTasks()
    }

    func loadPolicyIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadPolicy()
    }

    func loadCandidates() async {
        guard let apiClient else { return }
        candidatesState = .loading
        do {
            candidatesState = .loaded(try await apiClient.fetchNeedCandidates(projectId: projectId))
            message = nil
        } catch {
            candidatesState = .failed("候補の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadNextActions() async {
        guard let apiClient else { return }
        let hasVisibleContent: Bool
        if case .loaded = decisionInboxState {
            hasVisibleContent = true
        } else {
            hasVisibleContent = false
            decisionInboxState = .loading
            missionItemsState = .loading
            developmentMissionsState = .loading
            researchMissionsState = .loading
            messageMissionsState = .loading
            verificationMissionsState = .loading
            monitoringAlertsState = .loading
            missionProgressState = .loading
        }
        do {
            applyNextActionsPayload(try await apiClient.fetchVentureNextActions(ventureId: ventureId))
            message = nil
        } catch {
            let errorMessage = "次にやることの読み込みに失敗しました: \(error.localizedDescription)"
            if hasVisibleContent {
                message = errorMessage
            } else {
                decisionInboxState = .failed(errorMessage)
                missionItemsState = .idle
                developmentMissionsState = .idle
                researchMissionsState = .idle
                messageMissionsState = .idle
                verificationMissionsState = .idle
                monitoringAlertsState = .idle
                missionProgressState = .idle
            }
        }
    }

    func loadDecisionInbox() async {
        guard let apiClient else { return }
        let hadVisibleContent: Bool
        if case .loaded = decisionInboxState {
            hadVisibleContent = true
        } else {
            hadVisibleContent = false
            decisionInboxState = .loading
        }
        do {
            decisionInboxState = .loaded(
                try await apiClient.fetchVentureDecisionInbox(ventureId: ventureId)
            )
        } catch {
            let errorMessage = "おすすめの更新に失敗しました: \(error.localizedDescription)"
            if hadVisibleContent {
                message = errorMessage
            } else {
                decisionInboxState = .failed(errorMessage)
            }
        }
    }

    func loadMoreMissionItems() async {
        guard let apiClient, let cursor = nextMissionCursor, !isLoadingMoreMissionItems else { return }
        isLoadingMoreMissionItems = true
        defer { isLoadingMoreMissionItems = false }
        do {
            let payload = try await apiClient.fetchVentureNextActions(
                ventureId: ventureId,
                limit: 10,
                cursor: cursor
            )
            let existing = missionSummaryItems
            let knownIds = Set(existing.map(\.id))
            let additional = payload.missionItems.items.filter { !knownIds.contains($0.id) }
            decisionInboxState = .loaded(payload.decisionInbox)
            missionItemsState = .loaded(VentureMissionSummaryPage(
                items: existing + additional,
                nextCursor: payload.missionItems.nextCursor
            ))
            monitoringAlertsState = .loaded(payload.monitoringAlerts)
            missionProgressState = .loaded(payload.missionProgress)
        } catch {
            message = "続きを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func fetchMissionDetail(_ item: VentureMissionSummaryItem) async throws -> VentureMissionDetail {
        try await fetchMissionDetail(missionId: item.id)
    }

    func fetchMissionDetail(missionId: String) async throws -> VentureMissionDetail {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        return try await apiClient.fetchVentureMissionDetail(missionId: missionId)
    }

    func fetchResearchClipCandidates(deliverableId: String) async throws -> VentureResearchClipCandidatePayload {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        return try await apiClient.fetchResearchClipCandidates(deliverableId: deliverableId)
    }

    func saveResearchClip(deliverableId: String, itemKey: String) async throws -> VentureResearchClip {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        mutatingResearchClipIds.insert(itemKey)
        defer { mutatingResearchClipIds.remove(itemKey) }
        let result = try await apiClient.saveResearchClip(deliverableId: deliverableId, itemKey: itemKey)
        message = result.outcome == "existing" ? "保存済みの調査メモです" : "調査メモに保存しました"
        return result.clip
    }

    func loadResearchClips() async {
        guard let apiClient else { return }
        researchClipsState = .loading
        do {
            researchClipsState = .loaded(try await apiClient.fetchResearchClips(ventureId: ventureId))
        } catch {
            researchClipsState = .failed("調査メモの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadMoreResearchClips() async {
        guard let apiClient,
              case .loaded(let current) = researchClipsState,
              let cursor = current.nextCursor else { return }
        do {
            let next = try await apiClient.fetchResearchClips(ventureId: ventureId, cursor: cursor)
            let existingIds = Set(current.items.map(\.id))
            researchClipsState = .loaded(VentureResearchClipPage(
                items: current.items + next.items.filter { !existingIds.contains($0.id) },
                nextCursor: next.nextCursor
            ))
        } catch {
            message = "調査メモの続きを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func fetchResearchClipAssociationOptions() async throws -> VentureResearchClipAssociationOptions {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        return try await apiClient.fetchResearchClipAssociationOptions(ventureId: ventureId)
    }

    func updateResearchClip(
        _ clip: VentureResearchClip,
        userNote: String,
        opportunityId: String?,
        hypothesisId: String?
    ) async throws -> VentureResearchClip {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        mutatingResearchClipIds.insert(clip.id)
        defer { mutatingResearchClipIds.remove(clip.id) }
        let updated = try await apiClient.updateResearchClip(
            clipId: clip.id,
            expectedVersion: clip.version,
            userNote: userNote,
            opportunityId: opportunityId,
            hypothesisId: hypothesisId
        )
        replaceResearchClip(updated)
        message = "調査メモを更新しました"
        return updated
    }

    func archiveResearchClip(_ clip: VentureResearchClip) async throws {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        mutatingResearchClipIds.insert(clip.id)
        defer { mutatingResearchClipIds.remove(clip.id) }
        _ = try await apiClient.archiveResearchClip(clipId: clip.id, expectedVersion: clip.version)
        if case .loaded(let page) = researchClipsState {
            researchClipsState = .loaded(VentureResearchClipPage(
                items: page.items.filter { $0.clip.id != clip.id },
                nextCursor: page.nextCursor
            ))
        }
        message = "調査メモの保存を解除しました"
    }

    func archiveResearchClip(clipId: String, expectedVersion: Int) async throws {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        mutatingResearchClipIds.insert(clipId)
        defer { mutatingResearchClipIds.remove(clipId) }
        _ = try await apiClient.archiveResearchClip(clipId: clipId, expectedVersion: expectedVersion)
        message = "調査メモの保存を解除しました"
    }

    func isMutatingResearchClip(id: String) -> Bool {
        mutatingResearchClipIds.contains(id)
    }

    private func replaceResearchClip(_ clip: VentureResearchClip) {
        guard case .loaded(let page) = researchClipsState else { return }
        researchClipsState = .loaded(VentureResearchClipPage(
            items: page.items.map { item in
                guard item.clip.id == clip.id else { return item }
                return VentureResearchClipListItem(clip: clip, sourceState: item.sourceState)
            },
            nextCursor: page.nextCursor
        ))
    }

    func fetchProposalDetail(_ item: VentureDecisionInboxItem) async throws -> VentureProposalDetail {
        try await fetchProposalDetail(proposalId: item.proposalId)
    }

    func fetchProposalDetail(proposalId: String) async throws -> VentureProposalDetail {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        return try await apiClient.fetchVentureProposalDetail(proposalId: proposalId)
    }

    func isMutatingVentureProposal(id: String) -> Bool {
        mutatingVentureProposalIds.contains(id)
    }

    func isMutatingMission(id: String) -> Bool {
        mutatingMissionIds.contains(id)
    }

    func reviewMissionDeliverable(
        detail: VentureMissionDetail,
        decision: String,
        feedback: String,
        expectedRevisionHash: String? = nil
    ) async throws -> VentureMissionDetail {
        guard let apiClient, let deliverable = detail.currentDeliverable else {
            throw ActionInboxAPIClient.ClientError.invalidResponse
        }
        isUpdatingMission = true
        defer { isUpdatingMission = false }
        try await apiClient.reviewVentureDeliverable(
            deliverableId: deliverable.id,
            expectedMissionVersion: detail.mission.version,
            expectedRevisionHash: expectedRevisionHash,
            decision: decision,
            feedback: feedback
        )
        await loadNextActions()
        message = decision == "adopted"
            ? "成果物を採用しました"
            : decision == "revision_requested"
                ? "修正を依頼しました"
                : "成果物を却下しました"
        return try await apiClient.fetchVentureMissionDetail(missionId: detail.mission.id)
    }

    func rejectMissionDeliverable(
        detail: VentureMissionDetail,
        feedback: String
    ) async throws {
        guard let apiClient, let deliverable = detail.currentDeliverable else {
            throw ActionInboxAPIClient.ClientError.invalidResponse
        }
        isUpdatingMission = true
        defer { isUpdatingMission = false }
        try await apiClient.reviewVentureDeliverable(
            deliverableId: deliverable.id,
            expectedMissionVersion: detail.mission.version,
            expectedRevisionHash: nil,
            decision: "rejected",
            feedback: feedback
        )
        removeMissionFromList(id: detail.mission.id)
        removeMonitoringAlertForMission(id: detail.mission.id)
        await loadNextActions()
        message = "成果物を却下しました"
    }

    func retryMission(detail: VentureMissionDetail, feedback: String) async throws -> VentureMissionDetail {
        guard let apiClient else { throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL") }
        isUpdatingMission = true
        defer { isUpdatingMission = false }
        try await apiClient.retryVentureMission(
            missionId: detail.mission.id,
            expectedMissionVersion: detail.mission.version,
            feedback: feedback
        )
        await loadNextActions()
        message = "Missionを再実行します"
        return try await apiClient.fetchVentureMissionDetail(missionId: detail.mission.id)
    }

    func cancelMission(detail: VentureMissionDetail) async throws -> VentureMissionDetail {
        guard let apiClient else { throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL") }
        isUpdatingMission = true
        defer { isUpdatingMission = false }
        try await apiClient.cancelVentureMission(
            missionId: detail.mission.id,
            expectedMissionVersion: detail.mission.version
        )
        await loadNextActions()
        message = "Missionをキャンセルしました"
        return try await apiClient.fetchVentureMissionDetail(missionId: detail.mission.id)
    }

    func decideVentureProposal(
        _ item: VentureDecisionInboxItem,
        decision: VentureDecision,
        reasonCodes: [String],
        feedbackNote: String? = nil
    ) async {
        guard let apiClient, !mutatingVentureProposalIds.contains(item.proposalId) else { return }
        let previousInbox = decisionInboxState
        mutatingVentureProposalIds.insert(item.proposalId)
        isPostingVentureDecision = true
        removeVentureProposalFromInbox(id: item.proposalId)
        defer {
            mutatingVentureProposalIds.remove(item.proposalId)
            isPostingVentureDecision = !mutatingVentureProposalIds.isEmpty
        }
        do {
            let result = try await apiClient.decideVentureProposal(
                proposalId: item.proposalId,
                expectedVersion: item.version,
                decision: decision,
                reason: decisionReason(decision, item: item),
                reasonCodes: reasonCodes,
                feedbackNote: cleanedNote(feedbackNote),
                preferredProposalId: nil,
                successCriteria: item.suggestedSuccessCriteria,
                stopConditions: item.suggestedStopConditions
            )
            message = decisionSuccessMessage(
                decision,
                item: item,
                developmentMission: result.developmentMission,
                researchMission: result.researchMission,
                messageMission: result.messageMission
            )
            await loadNextActions()
        } catch {
            decisionInboxState = previousInbox
            await reconcileDecisionAfterFailure(item: item, decision: decision, error: error)
        }
    }

    func adoptMissionFromList(_ item: VentureMissionSummaryItem) async {
        guard let apiClient,
              let deliverableId = item.currentDeliverableId,
              !mutatingMissionIds.contains(item.id) else { return }
        let previousPage = missionItemsState
        mutatingMissionIds.insert(item.id)
        removeMissionFromList(id: item.id)
        defer { mutatingMissionIds.remove(item.id) }
        do {
            try await apiClient.reviewVentureDeliverable(
                deliverableId: deliverableId,
                expectedMissionVersion: item.missionVersion,
                expectedRevisionHash: nil,
                decision: "adopted",
                feedback: "成果物を確認し採用"
            )
            await loadNextActions()
            message = "成果物を採用しました"
        } catch {
            missionItemsState = previousPage
            message = "成果物を採用できませんでした: \(error.localizedDescription)"
        }
    }

    func cancelMissionFromList(_ item: VentureMissionSummaryItem) async {
        guard let apiClient, !mutatingMissionIds.contains(item.id) else { return }
        let previousPage = missionItemsState
        mutatingMissionIds.insert(item.id)
        removeMissionFromList(id: item.id)
        defer { mutatingMissionIds.remove(item.id) }
        do {
            try await apiClient.cancelVentureMission(
                missionId: item.id,
                expectedMissionVersion: item.missionVersion
            )
            await loadNextActions()
            message = "Missionをキャンセルしました"
        } catch {
            missionItemsState = previousPage
            message = "Missionをキャンセルできませんでした: \(error.localizedDescription)"
        }
    }

    func dismissMissionFromList(_ item: VentureMissionSummaryItem) async {
        guard let apiClient, !mutatingMissionIds.contains(item.id) else { return }
        let previousPage = missionItemsState
        mutatingMissionIds.insert(item.id)
        removeMissionFromList(id: item.id)
        defer { mutatingMissionIds.remove(item.id) }
        do {
            try await apiClient.dismissVentureMission(missionId: item.id)
            await loadNextActions()
            message = "確認待ちから削除しました"
        } catch {
            missionItemsState = previousPage
            message = "削除できませんでした: \(error.localizedDescription)"
        }
    }

    func dismissMission(missionId: String) async throws {
        guard let apiClient else { throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL") }
        guard !mutatingMissionIds.contains(missionId) else { return }
        mutatingMissionIds.insert(missionId)
        defer { mutatingMissionIds.remove(missionId) }
        try await apiClient.dismissVentureMission(missionId: missionId)
        removeMissionFromList(id: missionId)
        removeMonitoringAlertForMission(id: missionId)
        await loadNextActions()
        message = "確認待ちから削除しました"
    }

    func dismissMonitoringAlert(_ item: VentureMonitoringAlertItem) async {
        guard let apiClient, !mutatingMissionIds.contains(item.alert.missionId) else { return }
        let previousAlerts = monitoringAlertsState
        mutatingMissionIds.insert(item.alert.missionId)
        removeMonitoringAlertFromList(id: item.id)
        defer { mutatingMissionIds.remove(item.alert.missionId) }
        do {
            try await apiClient.dismissVentureMission(missionId: item.alert.missionId)
            removeMissionFromList(id: item.alert.missionId)
            await loadNextActions()
            message = "監視アラートを削除しました"
        } catch {
            monitoringAlertsState = previousAlerts
            message = "監視アラートを削除できませんでした: \(error.localizedDescription)"
        }
    }

    func requestRecommendationHeartbeat() async {
        guard let apiClient else { return }
        isRequestingRecommendationHeartbeat = true
        defer { isRequestingRecommendationHeartbeat = false }
        do {
            let result = try await apiClient.runVentureRecommendationHeartbeat(ventureId: ventureId)
            await loadNextActions()
            message = recommendationHeartbeatMessage(result)
        } catch {
            message = "提案準備を開始できませんでした: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createDirectMission(
        _ request: VentureDirectMissionRequest
    ) async throws -> VentureDirectMissionRequestResult {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        guard !isCreatingDirectMission else {
            throw ActionInboxAPIClient.ClientError.invalidResponse
        }
        isCreatingDirectMission = true
        defer { isCreatingDirectMission = false }
        let result = try await apiClient.createDirectMission(
            ventureId: ventureId,
            request: request
        )
        await loadNextActions()
        message = result.kind == "research"
            ? "調査を依頼しました"
            : "文案作成を依頼しました。外部送信はしていません"
        return result
    }

    private func reconcileDecisionAfterFailure(item: VentureDecisionInboxItem, decision: VentureDecision, error: Error) async {
        guard let apiClient else {
            message = "判断を保存できませんでした: \(error.localizedDescription)"
            return
        }
        do {
            let payload = try await apiClient.fetchVentureNextActions(ventureId: ventureId)
            applyNextActionsPayload(payload)
            if payload.decisionInbox.items.contains(where: { $0.proposalId == item.proposalId }) {
                message = "判断を保存できませんでした: \(error.localizedDescription)"
            } else {
                message = decisionSavedAfterLostConnectionMessage(decision, item: item)
            }
        } catch {
            message = "判断を保存できませんでした: \(error.localizedDescription)"
        }
    }

    private func recommendationHeartbeatMessage(_ result: VentureRecommendationHeartbeatResult) -> String {
        switch result.reason {
        case "queued":
            return "提案生成を開始しました。完了すると通知されます。"
        case "generated":
            return result.generatedCount > 0
                ? "次の提案を\(result.generatedCount)件準備しました。"
                : "次の提案を準備しました。"
        case "already_running":
            return "提案生成はすでに実行中です。"
        case "inbox_ready":
            return "判断待ちの提案があるため、追加生成は行いませんでした。"
        case "claim_conflict":
            return "別の処理が提案生成を開始しました。"
        case "generation_failed":
            return result.lastError.map { "提案生成に失敗しました: \($0)" } ?? "提案生成に失敗しました。"
        default:
            return "提案準備の状態を更新しました。"
        }
    }

    func loadNeeds() async {
        guard let apiClient else { return }
        needsState = .loading
        do {
            needsState = .loaded(try await apiClient.fetchNeeds())
            message = nil
        } catch {
            needsState = .failed("ニーズ一覧の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadDevelopmentTasks() async {
        guard let apiClient else { return }
        developmentTasksState = .loading
        do {
            developmentTasksState = .loaded(try await apiClient.fetchDevelopmentTasks(projectId: projectId))
            message = nil
        } catch {
            developmentTasksState = .failed("開発バックログの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadPolicy() async {
        guard let apiClient else { return }
        policyState = .loading
        do {
            policyState = .loaded(try await apiClient.fetchVenturePolicy(ventureId: ventureId))
            message = nil
        } catch {
            policyState = .failed("方針の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func isMutatingNeed(id: String) -> Bool {
        mutatingNeedIds.contains(id)
    }

    func isUpdatingDevelopmentTask(id: String) -> Bool {
        updatingDevelopmentTaskIds.contains(id)
    }

    func isStartingCodex(taskId: String) -> Bool {
        startingCodexTaskIds.contains(taskId)
    }

    func moveNextActionTodoRows(from offsets: IndexSet, to destination: Int) {
        guard case .loaded(let payload) = nextActionsState else { return }
        let movableItems = movableTodoItems(in: payload.items)
        let movedItems = Self.moved(items: movableItems, fromOffsets: offsets, toOffset: destination)
        storeNextActionTodoOrder(movedItems)
        nextActionsState = .loaded(payload.replacingItems(reorderedTodoItems: movedItems))
    }

    func moveNextActionTodoRow(id sourceId: String, before targetId: String) {
        guard
            sourceId != targetId,
            case .loaded(let payload) = nextActionsState
        else {
            return
        }

        var movableItems = movableTodoItems(in: payload.items)
        guard let sourceIndex = movableItems.firstIndex(where: { $0.id == sourceId }) else { return }
        let moving = movableItems.remove(at: sourceIndex)
        let targetIndex = movableItems.firstIndex(where: { $0.id == targetId }) ?? movableItems.count
        movableItems.insert(moving, at: targetIndex)
        storeNextActionTodoOrder(movableItems)
        nextActionsState = .loaded(payload.replacingItems(reorderedTodoItems: movableItems))
    }

    func pursue(candidate: NeedCandidate) async -> NeedPursueResult? {
        await runNeedOperation(
            id: candidate.need.id,
            successMessage: "追うにしました"
        ) {
            try await apiClient?.pursueNeedCandidate(id: candidate.need.id, projectId: projectId)
        }
    }

    func pursueNeed(id: String) async -> NeedPursueResult? {
        let result = await runNeedOperation(
            id: id,
            successMessage: "追うにしました"
        ) {
            try await apiClient?.pursueNeedCandidate(id: id, projectId: projectId)
        }
        await loadNextActions()
        return result
    }

    func hold(candidate: NeedCandidate, decisionNote: String?) async {
        _ = await runNeedOperation(
            id: candidate.need.id,
            successMessage: "保留しました"
        ) {
            try await apiClient?.holdNeedCandidate(
                id: candidate.need.id,
                decisionNote: cleanedNote(decisionNote)
            )
        }
    }

    func holdNeed(id: String, decisionNote: String?) async {
        _ = await runNeedOperation(
            id: id,
            successMessage: "保留しました"
        ) {
            try await apiClient?.holdNeedCandidate(
                id: id,
                decisionNote: cleanedNote(decisionNote)
            )
        }
        await loadNextActions()
    }

    func reject(candidate: NeedCandidate, decisionNote: String?) async {
        _ = await runNeedOperation(
            id: candidate.need.id,
            successMessage: "却下しました"
        ) {
            try await apiClient?.rejectNeedCandidate(
                id: candidate.need.id,
                decisionNote: cleanedNote(decisionNote)
            )
        }
    }

    func rejectNeed(id: String, decisionNote: String?) async {
        _ = await runNeedOperation(
            id: id,
            successMessage: "却下しました"
        ) {
            try await apiClient?.rejectNeedCandidate(
                id: id,
                decisionNote: cleanedNote(decisionNote)
            )
        }
        await loadNextActions()
    }

    func createNeedFromMemo(_ memo: String) async -> Need? {
        guard let apiClient else { return nil }
        let cleanedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedMemo.isEmpty else {
            message = "メモを入力してください"
            return nil
        }

        isPostingMemo = true
        defer { isPostingMemo = false }

        do {
            let need = try await apiClient.createNeedFromMemo(projectId: projectId, memo: cleanedMemo)
            message = "メモからニーズを作成しました"
            await loadCandidates()
            await loadNextActions()
            return need
        } catch {
            message = "メモの登録に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    func updateDevelopmentTask(
        _ task: DevelopmentTask,
        status: String? = nil,
        priority: String? = nil,
        assignedExecutor: String? = nil
    ) async {
        guard let apiClient else { return }
        updatingDevelopmentTaskIds.insert(task.id)
        defer { updatingDevelopmentTaskIds.remove(task.id) }

        do {
            let updated = try await apiClient.updateDevelopmentTask(
                id: task.id,
                status: status,
                priority: priority,
                assignedExecutor: assignedExecutor
            )
            replaceDevelopmentTask(updated)
            message = "バックログを更新しました"
        } catch {
            message = "バックログ更新に失敗しました: \(error.localizedDescription)"
        }
    }

    func reorderDevelopmentTasks(fromOffsets: IndexSet, toOffset: Int) async {
        guard let apiClient, case .loaded(let tasks) = developmentTasksState else { return }
        let moved = Self.moved(tasks: tasks, fromOffsets: fromOffsets, toOffset: toOffset)
        developmentTasksState = .loaded(moved)

        do {
            let updated = try await apiClient.reorderDevelopmentTasks(
                projectId: projectId,
                orderedIds: moved.map(\.id)
            )
            developmentTasksState = .loaded(updated)
            message = "順番を更新しました"
        } catch {
            message = "並び替えに失敗しました: \(error.localizedDescription)"
            await loadDevelopmentTasks()
        }
    }

    func startCodex(task: DevelopmentTask) async -> ActionSuggestion? {
        guard let apiClient else { return nil }
        startingCodexTaskIds.insert(task.id)
        defer { startingCodexTaskIds.remove(task.id) }

        do {
            let suggestion = try await apiClient.startCodexDevelopmentTask(id: task.id)
            message = "Codex実装のおすすめを作成しました"
            await loadDevelopmentTasks()
            return suggestion
        } catch {
            message = "Codex実装を開始できませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func startCodex(taskId: String) async -> ActionSuggestion? {
        guard let apiClient else { return nil }
        startingCodexTaskIds.insert(taskId)
        defer { startingCodexTaskIds.remove(taskId) }

        do {
            let suggestion = try await apiClient.startCodexDevelopmentTask(id: taskId)
            message = "Codex実装を開始しました"
            await loadDevelopmentTasks()
            await loadNextActions()
            return suggestion
        } catch {
            message = "Codex実装を開始できませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func scanMonitoringAlerts() async {
        guard let apiClient else { return }
        isScanningMonitoringAlerts = true
        defer { isScanningMonitoringAlerts = false }
        do {
            let result = try await apiClient.scanVentureMonitoringAlerts(ventureId: ventureId)
            await loadNextActions()
            message = result.createdCount > 0
                ? "監視アラートを\(result.createdCount)件作成しました"
                : "新しい監視アラートはありません"
        } catch {
            message = "監視スキャンに失敗しました: \(error.localizedDescription)"
        }
    }

    private func applyNextActionsPayload(_ payload: VentureNextActionsPayload) {
        decisionInboxState = .loaded(payload.decisionInbox)
        missionItemsState = .loaded(payload.missionItems)
        monitoringAlertsState = .loaded(payload.monitoringAlerts)
        missionProgressState = .loaded(payload.missionProgress)
    }

    private func removeVentureProposalFromInbox(id: String) {
        guard case .loaded(var payload) = decisionInboxState else { return }
        payload.items.removeAll { $0.proposalId == id }
        decisionInboxState = .loaded(payload)
    }

    private func removeMissionFromList(id: String) {
        guard case .loaded(var page) = missionItemsState else { return }
        page.items.removeAll { $0.id == id }
        missionItemsState = .loaded(page)
    }

    private func removeMonitoringAlertFromList(id: String) {
        guard case .loaded(var items) = monitoringAlertsState else { return }
        items.removeAll { $0.id == id }
        monitoringAlertsState = .loaded(items)
    }

    private func removeMonitoringAlertForMission(id: String) {
        guard case .loaded(var items) = monitoringAlertsState else { return }
        items.removeAll { $0.alert.missionId == id }
        monitoringAlertsState = .loaded(items)
    }

    func createPolicyTextRevision(
        policyText: String,
        reason: String
    ) async -> VenturePolicyRevisionDetail? {
        guard let apiClient, let currentPolicy = policy else { return nil }
        isSavingPolicy = true
        message = "事業方針の変更内容を準備しています"
        defer { isSavingPolicy = false }

        do {
            let context = try await apiClient.fetchVenturePolicyRevisionContext(ventureId: ventureId)
            let revision = try await apiClient.createVenturePolicyRevision(
                ventureId: ventureId,
                request: VenturePolicyRevisionDraft(
                    clientRequestId: UUID().uuidString.lowercased(),
                    contextHash: context.contextHash,
                    basePolicyTextVersionId: currentPolicy.policyTextVersionId,
                    baseStrategyVersionId: currentPolicy.strategyVersionId,
                    baseDecisionFrameVersionId: currentPolicy.decisionFrameVersionId,
                    nextPolicyText: policyText,
                    nextStrategy: nil,
                    nextDecisionFrame: nil,
                    rationale: reason,
                    expectedImpact: "AIが参照する事業方針の文脈を更新する",
                    contraryEvidence: [],
                    sourceRefs: [],
                    risk: "medium",
                    consultationSummary: "iPhoneで事業方針本文を編集",
                    executorSessionId: nil,
                    executorTurnId: nil
                )
            )
            await loadNextActions()
            await loadPolicy()
            message = "変更内容を確認してください"
            return revision
        } catch {
            message = "事業方針の変更案を作成できませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func createRecommendationSettingsRevision(
        strategy: VenturePolicyStrategySettingsRequest,
        decisionFrame: VenturePolicyDecisionFrameSettingsRequest,
        reason: String
    ) async -> VenturePolicyRevisionDetail? {
        guard let apiClient, let currentPolicy = policy else { return nil }
        isSavingPolicy = true
        message = "推薦設定の変更内容を準備しています"
        defer { isSavingPolicy = false }

        do {
            let context = try await apiClient.fetchVenturePolicyRevisionContext(ventureId: ventureId)
            let revision = try await apiClient.createVenturePolicyRevision(
                ventureId: ventureId,
                request: VenturePolicyRevisionDraft(
                    clientRequestId: UUID().uuidString.lowercased(),
                    contextHash: context.contextHash,
                    basePolicyTextVersionId: currentPolicy.policyTextVersionId,
                    baseStrategyVersionId: currentPolicy.strategyVersionId,
                    baseDecisionFrameVersionId: currentPolicy.decisionFrameVersionId,
                    nextPolicyText: nil,
                    nextStrategy: VenturePolicyStrategySettingsRequest(
                        mission: strategy.mission,
                        targetSegments: strategy.targetSegments,
                        desiredOutcomes: strategy.desiredOutcomes,
                        commercialHypotheses: strategy.commercialHypotheses,
                        focusAreas: strategy.focusAreas,
                        exclusions: strategy.exclusions,
                        researchGuardrails: strategy.researchGuardrails,
                        deliveryGuardrails: strategy.deliveryGuardrails
                    ),
                    nextDecisionFrame: decisionFrame,
                    rationale: reason,
                    expectedImpact: "提案の対象、除外条件、採点、推薦順位を更新する",
                    contraryEvidence: [],
                    sourceRefs: [],
                    risk: "high",
                    consultationSummary: "iPhoneで推薦設定を編集",
                    executorSessionId: nil,
                    executorTurnId: nil
                )
            )
            await loadNextActions()
            await loadPolicy()
            message = "変更内容を確認してください"
            return revision
        } catch {
            message = "推薦設定の変更案を作成できませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func fetchPolicyRevision(missionId: String) async throws -> VenturePolicyRevisionDetail {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        return try await apiClient.fetchVenturePolicyRevision(missionId: missionId)
    }

    func reviewPolicyRevision(
        detail: VenturePolicyRevisionDetail,
        decision: String,
        feedback: String
    ) async throws -> VenturePolicyRevisionDetail {
        guard let apiClient else {
            throw ActionInboxConfigurationError.missingValue("ActionAPIBaseURL")
        }
        isUpdatingMission = true
        defer { isUpdatingMission = false }
        try await apiClient.reviewVentureDeliverable(
            deliverableId: detail.deliverableId,
            expectedMissionVersion: detail.missionVersion,
            expectedRevisionHash: detail.revisionHash,
            decision: decision,
            feedback: feedback
        )
        await loadNextActions()
        await loadPolicy()
        let refreshed = try await apiClient.fetchVenturePolicyRevision(missionId: detail.missionId)
        switch decision {
        case "adopted":
            message = refreshed.applicationStatus == "applied"
                ? "方針変更を反映しました"
                : "方針変更の採用を受け付けました"
        case "revision_requested":
            message = "修正を依頼しました"
        default:
            message = "方針変更案を却下しました"
        }
        return refreshed
    }

    private func runNeedOperation<Result>(
        id: String,
        successMessage: String,
        operation: () async throws -> Result?
    ) async -> Result? {
        guard apiClient != nil else { return nil }
        mutatingNeedIds.insert(id)
        defer { mutatingNeedIds.remove(id) }

        do {
            let result = try await operation()
            removeCandidate(id: id)
            message = successMessage
            return result
        } catch {
            message = "候補の操作に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    private func removeCandidate(id: String) {
        guard case .loaded(let items) = candidatesState else { return }
        candidatesState = .loaded(items.filter { $0.need.id != id })
    }

    private func replaceDevelopmentTask(_ task: DevelopmentTask) {
        guard case .loaded(var items) = developmentTasksState else { return }
        guard let index = items.firstIndex(where: { $0.id == task.id }) else { return }
        items[index] = task
        developmentTasksState = .loaded(items)
    }

    private func movableTodoItems(in items: [NextActionItem]) -> [NextActionItem] {
        let recommendedId = items.first(where: Self.isTodoLike)?.id
        return items.filter { item in
            Self.isTodoLike(item) && item.id != recommendedId
        }
    }

    private func applyingStoredTodoOrder(to payload: NextActionsPayload) -> NextActionsPayload {
        let currentItems = movableTodoItems(in: payload.items)
        guard
            let storedIds = UserDefaults.standard.stringArray(forKey: nextActionOrderStorageKey),
            !storedIds.isEmpty,
            !currentItems.isEmpty
        else {
            return payload
        }

        var remainingItems = currentItems
        var orderedItems: [NextActionItem] = []
        for id in storedIds {
            guard let index = remainingItems.firstIndex(where: { $0.id == id }) else { continue }
            orderedItems.append(remainingItems.remove(at: index))
        }
        orderedItems.append(contentsOf: remainingItems)
        return payload.replacingItems(reorderedTodoItems: orderedItems)
    }

    private func storeNextActionTodoOrder(_ items: [NextActionItem]) {
        UserDefaults.standard.set(items.map(\.id), forKey: nextActionOrderStorageKey)
    }

    private static func isTodoLike(_ item: NextActionItem) -> Bool {
        item.status == "todo" || item.status == "blocked"
    }

    private func cleanedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func decisionReason(_ decision: VentureDecision, item: VentureDecisionInboxItem) -> String {
        switch decision {
        case .approved:
            return item.approvalReason
        case .deferred:
            return "今は優先しない"
        case .rejected:
            return "現時点では追わない"
        }
    }

    private func decisionSuccessMessage(
        _ decision: VentureDecision,
        item: VentureDecisionInboxItem,
        developmentMission: VentureDevelopmentMission?,
        researchMission: VentureResearchMission?,
        messageMission: VentureMessageMission?
    ) -> String {
        switch decision {
        case .approved:
            if developmentMission != nil {
                return "Codexへ依頼しました"
            }
            if researchMission != nil {
                return "調査を開始しました"
            }
            if messageMission != nil {
                return "メッセージ下書きを作成します。送信はしていません"
            }
            if item.actionKind == "outreach" {
                return "メッセージ下書きを作成します。送信はしていません"
            }
            if item.actionKind == "research" {
                return "調査を進める判断を保存しました"
            }
            return "承認しました"
        case .deferred:
            return "あとでにしました"
        case .rejected:
            return "却下しました"
        }
    }

    private func decisionSavedAfterLostConnectionMessage(_ decision: VentureDecision, item: VentureDecisionInboxItem) -> String {
        switch decision {
        case .approved:
            if item.actionKind == "outreach" {
                return "保存済みです。メッセージ送信はしていません"
            }
            return "保存済みです"
        case .deferred:
            return "あとでに保存済みです"
        case .rejected:
            return "却下済みです"
        }
    }

    private static func moved(
        tasks: [DevelopmentTask],
        fromOffsets: IndexSet,
        toOffset: Int
    ) -> [DevelopmentTask] {
        var result = tasks
        let moving = fromOffsets.map { result[$0] }
        for index in fromOffsets.sorted(by: >) {
            result.remove(at: index)
        }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let insertionIndex = max(0, min(toOffset - removedBeforeDestination, result.count))
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }

    private static func moved(
        items: [NextActionItem],
        fromOffsets: IndexSet,
        toOffset: Int
    ) -> [NextActionItem] {
        var result = items
        let moving = fromOffsets.map { result[$0] }
        for index in fromOffsets.sorted(by: >) {
            result.remove(at: index)
        }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let insertionIndex = max(0, min(toOffset - removedBeforeDestination, result.count))
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }
}
