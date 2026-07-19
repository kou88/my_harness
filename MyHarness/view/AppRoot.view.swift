import SwiftUI

@MainActor
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies: AppDependencies

    @State private var router = AppRouter()
    @State private var todayState: TodayState
    @State private var settingsState: SettingsState
    @State private var actionInboxState: ActionInboxState
    @State private var productOpsState: ProductOpsState
    @State private var lastForegroundRefreshAt = Date.distantPast
    @State private var pushRegistrationErrorMessage: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _todayState = State(initialValue: TodayState(useCases: dependencies.useCases))
        _settingsState = State(initialValue: SettingsState(
            useCases: dependencies.useCases,
            authSession: dependencies.actionInbox.authSession,
            apiClient: dependencies.actionInbox.apiClient
        ))
        _actionInboxState = State(initialValue: ActionInboxState(
            authSession: dependencies.actionInbox.authSession,
            apiClient: dependencies.actionInbox.apiClient,
            widgetRepository: dependencies.actionInbox.widgetRepository,
            configurationErrorMessage: dependencies.actionInbox.configurationErrorMessage
        ))
        _productOpsState = State(initialValue: ProductOpsState(
            authSession: dependencies.actionInbox.authSession,
            apiClient: dependencies.actionInbox.apiClient,
            copyText: dependencies.useCases.copyText,
            projectId: ProductOpsProject.landlordSaaS,
            configurationErrorMessage: dependencies.actionInbox.configurationErrorMessage
        ))
        _pushRegistrationErrorMessage = State(
            initialValue: ActionPushNotificationCoordinator.shared.registrationErrorMessage
        )
    }

    var body: some View {
        TabView(
            selection: Binding(
                get: { router.selectedTab },
                set: { router.selectedTab = $0 }
            )
        ) {
            NavigationStack(
                path: Binding(
                    get: { router.todayPath },
                    set: { router.todayPath = $0 }
                )
            ) {
                TodayView(state: todayState)
                    .navigationDestination(for: AppRoute.self, destination: routeContent)
            }
            .tabItem {
                Label("今日", systemImage: "checklist")
            }
            .tag(AppTab.today)

            NavigationStack(
                path: Binding(
                    get: { router.nextActionsPath },
                    set: { router.nextActionsPath = $0 }
                )
            ) {
                NextActionsView(
                    actionInboxState: actionInboxState,
                    productOpsState: productOpsState
                )
                    .navigationDestination(for: AppRoute.self, destination: routeContent)
            }
            .tabItem {
                Label("次にやる", systemImage: "sparkles")
            }
            .tag(AppTab.nextActions)
        }
        .environment(router)
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionInboxDeepLink)) { notification in
            guard let url = notification.object as? URL else { return }
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionInboxShouldReload)) { _ in
            Task {
                await actionInboxState.loadIfPossible()
                await productOpsState.loadRecommendationsIfPossible()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionPushRegistrationFailed)) { notification in
            guard let message = notification.object as? String else { return }
            actionInboxState.reportPushRegistrationFailure(message)
            pushRegistrationErrorMessage = message
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionPushRegistrationStatusChanged)) { _ in
            Task { await settingsState.refreshPushRegistrationState() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  Date().timeIntervalSince(lastForegroundRefreshAt) >= 15 else {
                return
            }
            lastForegroundRefreshAt = Date()
            Task {
                await productOpsState.loadRecommendationsIfPossible()
            }
        }
        .onChange(of: actionInboxState.isSignedIn) { _, isSignedIn in
            guard isSignedIn,
                  let pendingURL = ActionPushNotificationCoordinator.shared.pendingDeepLinkURL else {
                return
            }
            router.handleDeepLink(pendingURL)
            ActionPushNotificationCoordinator.shared.clearPendingDeepLink()
        }
        .task {
            await actionInboxState.synchronizePushAfterSignIn()
            guard let pendingURL = ActionPushNotificationCoordinator.shared.pendingDeepLinkURL else { return }
            router.handleDeepLink(pendingURL)
            if actionInboxState.isSignedIn {
                ActionPushNotificationCoordinator.shared.clearPendingDeepLink()
            }
        }
        .alert(
            "Push通知を登録できません",
            isPresented: Binding(
                get: { pushRegistrationErrorMessage != nil },
                set: { if !$0 { pushRegistrationErrorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) {
                pushRegistrationErrorMessage = nil
            }
        } message: {
            Text(pushRegistrationErrorMessage ?? "Push通知の端末登録に失敗しました。")
        }
        .sheet(
            item: Binding(
                get: { router.presentedSheet },
                set: { router.presentedSheet = $0 }
            ),
            content: sheetContent
        )
    }

    private func handleDeepLink(_ url: URL) {
        router.handleDeepLink(url)
        if actionInboxState.isSignedIn {
            ActionPushNotificationCoordinator.shared.clearPendingDeepLink()
        }
    }

    @ViewBuilder
    private func routeContent(_ route: AppRoute) -> some View {
        switch route {
        case .oneShotTasks:
            OneShotTasksView(state: todayState)
        case .actionSuggestionDetail(let id):
            ActionSuggestionDetailView(id: id, state: actionInboxState)
        case .actionExecution(let id):
            ActionReferenceView(kind: .execution, id: id)
        case .need(let id):
            ActionReferenceView(kind: .need, id: id)
        case .codexResult(let id):
            ActionReferenceView(kind: .codexResult, id: id)
        case .needList:
            ProductNeedListView(state: productOpsState)
        case .developmentBacklog:
            DevelopmentView(state: productOpsState, actionInboxState: actionInboxState)
        case .projectPolicy:
            ProjectPolicyView(state: productOpsState)
        case .actionHistory:
            ActionHistoryView(state: actionInboxState, mode: .history)
        case .completedActions:
            ActionHistoryView(state: actionInboxState, mode: .completed)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .addItem:
            NavigationStack {
                ItemEditorView(
                    state: ItemEditorState(useCases: dependencies.useCases),
                    afterSave: { await todayState.load() }
                )
            }
        case .editItem(let item):
            NavigationStack {
                ItemEditorView(
                    state: ItemEditorState(useCases: dependencies.useCases, editingItem: item),
                    afterSave: { await todayState.load() }
                )
            }
        case .settings:
            NavigationStack {
                SettingsView(state: settingsState)
            }
        case .weeklyExport(let text):
            NavigationStack {
                WeeklyExportView(text: text)
            }
        }
    }
}

#Preview {
    AppRootView(dependencies: try! AppDependencies.preview())
}
