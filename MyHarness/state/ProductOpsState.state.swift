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

    var candidatesState: LoadState<[NeedCandidate]> = .idle
    var developmentTasksState: LoadState<[DevelopmentTask]> = .idle
    var policyState: LoadState<ProjectPolicy> = .idle
    var isPostingMemo = false
    var isSavingPolicy = false
    var message: String?
    var configurationErrorMessage: String?

    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?
    private let projectId: String
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
        await loadCandidates()
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

    func pursue(candidate: NeedCandidate) async -> NeedPursueResult? {
        await runNeedOperation(
            id: candidate.need.id,
            successMessage: "追うにしました"
        ) {
            try await apiClient?.pursueNeedCandidate(id: candidate.need.id, projectId: projectId)
        }
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

    private func cleanedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
}
