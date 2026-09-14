import Foundation
import Observation

@MainActor @Observable
final class AICronState {
    private let api: AIAPIClient?
    private let auth: CognitoAuthSession?
    private let configurationErrorMessage: String?

    var snapshots: [AICronHostSnapshot] = []
    var selectedHostId: String?
    var activeOperationIds: Set<String> = []
    var isLoading = false
    var errorMessage = ""

    init(apiClient: AIAPIClient?, authSession: CognitoAuthSession?, configurationErrorMessage: String?) {
        api = apiClient
        auth = authSession
        self.configurationErrorMessage = configurationErrorMessage
    }

    var selectedHost: AICronHostSnapshot? {
        if let selectedHostId, let host = snapshots.first(where: { $0.hostId == selectedHostId }) { return host }
        return snapshots.first
    }

    func refresh() async {
        guard !isLoading else { return }
        if let configurationErrorMessage { errorMessage = configurationErrorMessage; return }
        guard auth?.isSignedIn == true else { errorMessage = "定期タスクを使うにはログインしてください。"; return }
        guard let api else { errorMessage = "AIサーバーが設定されていません。"; return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshots = try await api.cronSnapshots()
            if selectedHost == nil { selectedHostId = snapshots.first?.hostId }
            errorMessage = snapshots.isEmpty ? "定期タスク対応のPCから、まだ同期されていません。" : ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func perform(_ request: AICronOperationRequest) async -> Bool {
        guard let api else { errorMessage = "AIサーバーが設定されていません。"; return false }
        guard let host = selectedHost else { errorMessage = "対象のPCを選択してください。"; return false }
        guard host.online else { errorMessage = "定期タスク対応のPCがオフラインです。"; return false }
        let id = UUID().uuidString.lowercased()
        activeOperationIds.insert(id)
        defer { activeOperationIds.remove(id) }
        do {
            var operation = try await api.queueCronOperation(.init(id: id, hostId: host.hostId, operation: request))
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while !operation.isTerminal && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(500))
                operation = try await api.cronOperation(id)
            }
            guard operation.isTerminal else { throw AICronStateError.timeout }
            guard operation.status == "succeeded" else { throw AICronStateError.operation(operation.error) }
            await refresh()
            return true
        } catch {
            await refresh()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func create(_ spec: AICronJobSpec, dismissing suggestionId: String?) async -> Bool {
        guard await perform(.create(spec)) else { return false }
        guard let suggestionId else { return true }
        _ = await perform(.dismissSuggestion(suggestionId: suggestionId))
        return true
    }
}

private enum AICronStateError: LocalizedError {
    case timeout
    case operation(String)
    var errorDescription: String? {
        switch self {
        case .timeout: "PCから操作結果が返りませんでした。状態を再読み込みしてください。"
        case .operation(let message): message.isEmpty ? "定期タスク操作に失敗しました。" : message
        }
    }
}
