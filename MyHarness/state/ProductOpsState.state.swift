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
    var developmentMissionsState: LoadState<[VentureDevelopmentMissionItem]> = .idle
    var researchMissionsState: LoadState<[VentureResearchMissionItem]> = .idle
    var messageMissionsState: LoadState<[VentureMessageMissionItem]> = .idle
    var verificationMissionsState: LoadState<[VentureVerificationMissionItem]> = .idle
    var knowledgeChangeMissionsState: LoadState<[VentureKnowledgeChangeMissionItem]> = .idle
    var needsState: LoadState<[Need]> = .idle
    var candidatesState: LoadState<[NeedCandidate]> = .idle
    var developmentTasksState: LoadState<[DevelopmentTask]> = .idle
    var policyState: LoadState<ProjectPolicy> = .idle
    var isPostingMemo = false
    var isSavingPolicy = false
    var isPostingVentureDecision = false
    var message: String?
    var configurationErrorMessage: String?

    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?
    private let projectId: String
    private let ventureId: String
    private let nextActionOrderStorageKey: String
    private var mutatingNeedIds: Set<String> = []
    private var updatingDevelopmentTaskIds: Set<String> = []
    private var startingCodexTaskIds: Set<String> = []

    init(
        authSession: CognitoAuthSession?,
        apiClient: ActionInboxAPIClient?,
        projectId: String,
        configurationErrorMessage: String?
    ) {
        self.authSession = authSession
        self.apiClient = apiClient
        self.projectId = projectId
        ventureId = ProductOpsProject.landlordSaaSVenture
        nextActionOrderStorageKey = "myHarness.nextActionTodoOrder.\(projectId)"
        self.configurationErrorMessage = configurationErrorMessage
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

    var knowledgeChangeMissionItems: [VentureKnowledgeChangeMissionItem] {
        guard case .loaded(let items) = knowledgeChangeMissionsState else {
            return []
        }
        return items
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

    var policy: ProjectPolicy? {
        guard case .loaded(let policy) = policyState else {
            return nil
        }
        return policy
    }

    func reset() {
        nextActionsState = .idle
        decisionInboxState = .idle
        developmentMissionsState = .idle
        researchMissionsState = .idle
        messageMissionsState = .idle
        verificationMissionsState = .idle
        knowledgeChangeMissionsState = .idle
        needsState = .idle
        candidatesState = .idle
        developmentTasksState = .idle
        policyState = .idle
        message = nil
        mutatingNeedIds.removeAll()
        updatingDevelopmentTaskIds.removeAll()
        startingCodexTaskIds.removeAll()
    }

    func loadRecommendationsIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadDecisionInbox()
    }

    func loadNextActionsIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await loadDecisionInbox()
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
        decisionInboxState = .loading
        developmentMissionsState = .loading
        researchMissionsState = .loading
        messageMissionsState = .loading
        verificationMissionsState = .loading
        knowledgeChangeMissionsState = .loading
        do {
            var payload = try await apiClient.fetchVentureDecisionInbox(ventureId: ventureId)
            if payload.refreshRequired {
                _ = try await apiClient.generateVentureProposals(ventureId: ventureId)
                payload = try await apiClient.fetchVentureDecisionInbox(ventureId: ventureId)
            }
            decisionInboxState = .loaded(payload)
            do {
                developmentMissionsState = .loaded(try await apiClient.fetchVentureDevelopmentMissions(ventureId: ventureId).items)
            } catch {
                developmentMissionsState = .failed("開発Missionの読み込みに失敗しました: \(error.localizedDescription)")
            }
            do {
                researchMissionsState = .loaded(try await apiClient.fetchVentureResearchMissions(ventureId: ventureId).items)
            } catch {
                researchMissionsState = .failed("調査Missionの読み込みに失敗しました: \(error.localizedDescription)")
            }
            do {
                messageMissionsState = .loaded(try await apiClient.fetchVentureMessageMissions(ventureId: ventureId).items)
            } catch {
                messageMissionsState = .failed("文案Missionの読み込みに失敗しました: \(error.localizedDescription)")
            }
            do {
                verificationMissionsState = .loaded(try await apiClient.fetchVentureVerificationMissions(ventureId: ventureId).items)
            } catch {
                verificationMissionsState = .failed("検証Missionの読み込みに失敗しました: \(error.localizedDescription)")
            }
            do {
                knowledgeChangeMissionsState = .loaded(try await apiClient.fetchVentureKnowledgeChangeMissions(ventureId: ventureId).items)
            } catch {
                knowledgeChangeMissionsState = .failed("Knowledge更新候補の読み込みに失敗しました: \(error.localizedDescription)")
            }
            message = nil
        } catch {
            decisionInboxState = .failed("次にやることの読み込みに失敗しました: \(error.localizedDescription)")
            developmentMissionsState = .idle
            researchMissionsState = .idle
            messageMissionsState = .idle
            verificationMissionsState = .idle
            knowledgeChangeMissionsState = .idle
        }
    }

    func loadDecisionInbox() async {
        await loadNextActions()
    }

    func decideVentureProposal(_ item: VentureDecisionInboxItem, decision: VentureDecision) async {
        guard let apiClient else { return }
        isPostingVentureDecision = true
        defer { isPostingVentureDecision = false }
        do {
            let result = try await apiClient.decideVentureProposal(
                proposalId: item.proposalId,
                expectedVersion: item.version,
                decision: decision,
                reason: decisionReason(decision, item: item),
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
            await loadDecisionInbox()
        } catch {
            await reconcileDecisionAfterFailure(item: item, decision: decision, error: error)
        }
    }

    private func reconcileDecisionAfterFailure(item: VentureDecisionInboxItem, decision: VentureDecision, error: Error) async {
        guard let apiClient else {
            message = "判断を保存できませんでした: \(error.localizedDescription)"
            return
        }
        do {
            var payload = try await apiClient.fetchVentureDecisionInbox(ventureId: ventureId)
            if payload.refreshRequired {
                _ = try await apiClient.generateVentureProposals(ventureId: ventureId)
                payload = try await apiClient.fetchVentureDecisionInbox(ventureId: ventureId)
            }
            decisionInboxState = .loaded(payload)
            developmentMissionsState = .loaded(try await apiClient.fetchVentureDevelopmentMissions(ventureId: ventureId).items)
            researchMissionsState = .loaded(try await apiClient.fetchVentureResearchMissions(ventureId: ventureId).items)
            messageMissionsState = .loaded(try await apiClient.fetchVentureMessageMissions(ventureId: ventureId).items)
            verificationMissionsState = .loaded(try await apiClient.fetchVentureVerificationMissions(ventureId: ventureId).items)
            knowledgeChangeMissionsState = .loaded(try await apiClient.fetchVentureKnowledgeChangeMissions(ventureId: ventureId).items)
            if payload.items.contains(where: { $0.proposalId == item.proposalId }) {
                message = "判断を保存できませんでした: \(error.localizedDescription)"
            } else {
                message = decisionSavedAfterLostConnectionMessage(decision, item: item)
            }
        } catch {
            message = "判断を保存できませんでした: \(error.localizedDescription)"
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
            policyState = .loaded(try await apiClient.fetchProjectPolicy(projectId: projectId))
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

    func adoptResearchLearning(deliverable: VentureDeliverable) async {
        guard let apiClient else { return }
        do {
            _ = try await apiClient.adoptResearchLearning(
                deliverableId: deliverable.id,
                decisionNote: "調査結果をLearningとして採用"
            )
            message = "調査結果をLearningとして採用しました"
            await loadNextActions()
        } catch {
            message = "Learningとして採用できませんでした: \(error.localizedDescription)"
        }
    }

    func updatePolicy(fields: ProjectPolicyEditableFields) async -> ProjectPolicy? {
        guard let apiClient else { return nil }
        isSavingPolicy = true
        defer { isSavingPolicy = false }

        do {
            let policy = try await apiClient.updateProjectPolicy(projectId: projectId, fields: fields)
            policyState = .loaded(policy)
            message = "方針を保存しました"
            return policy
        } catch {
            message = "方針を保存できませんでした: \(error.localizedDescription)"
            return nil
        }
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
