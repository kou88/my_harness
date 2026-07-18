import Foundation
import Observation

@MainActor
@Observable
final class ActionInboxState {
    enum LoadState<T: Hashable>: Hashable {
        case idle
        case loading
        case loaded(T)
        case failed(String)
    }

    var inboxState: LoadState<ActionInboxPayload> = .idle
    var detailState: LoadState<ActionSuggestion> = .idle
    var isSigningIn = false
    var isPostingDecision = false
    var isRegisteringPush = false
    var message: String?
    var configurationErrorMessage: String?

    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?
    private let widgetRepository: ActionSuggestionWidgetSnapshotRepository

    init(
        authSession: CognitoAuthSession?,
        apiClient: ActionInboxAPIClient?,
        widgetRepository: ActionSuggestionWidgetSnapshotRepository,
        configurationErrorMessage: String?
    ) {
        self.authSession = authSession
        self.apiClient = apiClient
        self.widgetRepository = widgetRepository
        self.configurationErrorMessage = configurationErrorMessage
        self.message = ActionPushNotificationCoordinator.shared.registrationErrorMessage
    }

    var isConfigured: Bool {
        apiClient != nil && authSession != nil
    }

    var isSignedIn: Bool {
        authSession?.isSignedIn == true
    }

    var items: [ActionInboxItem] {
        guard case .loaded(let payload) = inboxState else {
            return []
        }
        return payload.items
    }

    var summary: ActionInboxSummary? {
        guard case .loaded(let payload) = inboxState else {
            return nil
        }
        return payload.summary
    }

    var pendingCount: Int {
        summary?.pendingCount
            ?? summary.map { ($0.approvalRequiredCount ?? 0) + ($0.resultReviewCount ?? 0) }
            ?? items.filter(\.isOpenForDecision).count
    }

    var highRiskCount: Int {
        summary?.highRiskCount ?? items.filter { [.high, .critical].contains($0.displayRiskLevel) }.count
    }

    var currentSuggestion: ActionSuggestion? {
        guard case .loaded(let suggestion) = detailState else {
            return nil
        }
        return suggestion
    }

    func loadIfPossible() async {
        guard isConfigured, isSignedIn else { return }
        await load()
    }

    func signIn() async {
        guard let authSession else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await authSession.signIn()
            ActionPushNotificationCoordinator.shared.configure(apiClient: apiClient)
            await load()
            message = nil
        } catch {
            message = "ログインに失敗しました: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        do {
            try authSession?.signOut()
            inboxState = .idle
            detailState = .idle
            try await widgetRepository.publish(.empty)
            message = nil
        } catch {
            message = "ログアウトに失敗しました: \(error.localizedDescription)"
        }
    }

    func load() async {
        guard let apiClient else { return }
        inboxState = .loading
        do {
            let payload = try await apiClient.fetchInbox()
            inboxState = .loaded(payload)
            try await publishWidgetSnapshot(from: payload)
            message = nil
        } catch {
            inboxState = .failed("おすすめの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func loadSuggestion(id: String) async {
        guard let apiClient else { return }
        detailState = .loading
        do {
            detailState = .loaded(try await apiClient.fetchSuggestion(id: id))
            message = nil
        } catch {
            detailState = .failed("詳細の読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    func decide(
        suggestion: ActionSuggestion,
        decision: ActionSuggestionDecision,
        decisionNote: String?
    ) async {
        await runVersionedOperation(successMessage: "\(decision.label)しました") {
            try await apiClient?.decideSuggestion(
                id: suggestion.id,
                decision: decision,
                expectedVersion: suggestion.version,
                decisionNote: cleanedNote(decisionNote),
                hostId: suggestion.hostId
            )
        }
        await reloadAfterOperation(id: suggestion.id)
    }

    func decideItem(
        id: String,
        version: Int,
        hostId: String?,
        decision: ActionSuggestionDecision,
        decisionNote: String?
    ) async {
        await runVersionedOperation(successMessage: "\(decision.label)しました") {
            try await apiClient?.decideSuggestion(
                id: id,
                decision: decision,
                expectedVersion: version,
                decisionNote: cleanedNote(decisionNote),
                hostId: hostId
            )
        }
        await loadIfPossible()
    }

    func adoptResult(suggestion: ActionSuggestion, decisionNote: String?) async {
        await runVersionedOperation(successMessage: "結果を採用しました") {
            try await apiClient?.adoptResult(
                id: suggestion.id,
                expectedVersion: suggestion.version,
                decisionNote: cleanedNote(decisionNote),
                hostId: suggestion.hostId
            )
        }
        await reloadAfterOperation(id: suggestion.id)
    }

    func rejectResult(suggestion: ActionSuggestion, decisionNote: String?) async {
        await runVersionedOperation(successMessage: "結果を却下しました") {
            try await apiClient?.rejectResult(
                id: suggestion.id,
                expectedVersion: suggestion.version,
                decisionNote: cleanedNote(decisionNote),
                hostId: suggestion.hostId
            )
        }
        await reloadAfterOperation(id: suggestion.id)
    }

    func cancel(suggestion: ActionSuggestion, decisionNote: String?) async {
        await runVersionedOperation(successMessage: "キャンセルしました") {
            try await apiClient?.cancelSuggestion(
                id: suggestion.id,
                expectedVersion: suggestion.version,
                decisionNote: cleanedNote(decisionNote),
                hostId: suggestion.hostId
            )
        }
        await reloadAfterOperation(id: suggestion.id)
    }

    func registerForPushNotifications() async {
        isRegisteringPush = true
        defer { isRegisteringPush = false }

        do {
            ActionPushNotificationCoordinator.shared.configure(apiClient: apiClient)
            try await ActionPushNotificationCoordinator.shared.requestAuthorizationAndRegister()
            message = "通知登録を開始しました"
        } catch {
            message = "通知登録に失敗しました: \(error.localizedDescription)"
        }
    }

    func reportPushRegistrationFailure(_ message: String) {
        self.message = message
    }

    private func runVersionedOperation(
        successMessage: String,
        operation: () async throws -> Void
    ) async {
        guard apiClient != nil else { return }
        isPostingDecision = true
        defer { isPostingDecision = false }

        do {
            try await operation()
            message = successMessage
        } catch {
            message = "操作に失敗しました: \(error.localizedDescription)"
        }
    }

    private func reloadAfterOperation(id: String) async {
        await load()
        await loadSuggestion(id: id)
    }

    private func cleanedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func publishWidgetSnapshot(from payload: ActionInboxPayload) async throws {
        let openItems = payload.items.filter(\.isOpenForDecision)
        let snapshot = ActionSuggestionWidgetSnapshot(
            updatedAt: Date(),
            pendingCount: payload.summary?.pendingCount
                ?? payload.summary.map { ($0.approvalRequiredCount ?? 0) + ($0.resultReviewCount ?? 0) }
                ?? openItems.count,
            highRiskCount: payload.summary?.highRiskCount ?? openItems.filter {
                [.high, .critical].contains($0.displayRiskLevel)
            }.count,
            items: openItems.prefix(5).map { item in
                ActionSuggestionWidgetItem(
                    id: item.id,
                    title: item.displayTitle,
                    summary: item.displaySummary,
                    riskLabel: item.displayRiskLevel.label,
                    updatedAt: item.updatedAt ?? item.createdAt
                )
            }
        )
        try await widgetRepository.publish(snapshot)
    }
}
