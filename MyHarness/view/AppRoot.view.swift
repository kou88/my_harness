import SwiftUI

@MainActor
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies: AppDependencies
    private let televisionAPIClient: KonomiTVAPIClient
    @StateObject private var televisionPlayerController: TelevisionPlayerController

    @State private var router = AppRouter()
    @State private var todayState: TodayState
    @State private var settingsState: SettingsState
    @State private var actionInboxState: ActionInboxState
    @State private var productOpsState: ProductOpsState
    @State private var blogPostState: BlogPostState
    @State private var aiChatState: AIChatState
    @State private var lastForegroundRefreshAt = Date.distantPast
    @State private var pushRegistrationErrorMessage: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let televisionAPIClient = KonomiTVAPIClient.automatic(
            localServerURL: KonomiTVConfiguration.serverURL,
            expectedGatewayBaseURL: KonomiTVConfiguration.expectedGatewayBaseURL,
            remoteAccess: dependencies.actionInbox.televisionRemoteAccess
        )
        self.televisionAPIClient = televisionAPIClient
        _televisionPlayerController = StateObject(
            wrappedValue: TelevisionPlayerController(apiClient: televisionAPIClient)
        )
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
        _blogPostState = State(initialValue: BlogPostState(
            authSession: dependencies.actionInbox.authSession,
            apiClient: dependencies.actionInbox.apiClient,
            configurationErrorMessage: dependencies.actionInbox.configurationErrorMessage,
            importCandidateRepository: dependencies.sharedXImportCandidates
        ))
        _aiChatState = State(initialValue: AIChatState(
            apiClient: dependencies.actionInbox.aiClient,
            authSession: dependencies.actionInbox.authSession,
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

            NavigationStack(
                path: Binding(
                    get: { router.articlesPath },
                    set: { router.articlesPath = $0 }
                )
            ) {
                ArticleListView(state: blogPostState)
                    .navigationDestination(for: AppRoute.self, destination: routeContent)
            }
            .tabItem {
                Label("記事", systemImage: "doc.richtext")
            }
            .badge(blogPostState.importCandidates.count)
            .tag(AppTab.articles)

            NavigationStack {
                AIConversationListView(state: aiChatState)
            }
            .tabItem {
                Label("AI", systemImage: "sparkles")
            }
            .tag(AppTab.ai)

            NavigationStack {
                TelevisionView(
                    apiClient: televisionAPIClient,
                    playerController: televisionPlayerController
                )
            }
            .tabItem {
                Label("テレビ", systemImage: "tv")
            }
            .tag(AppTab.television)
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
                await blogPostState.loadIfPossible()
                if router.selectedTab == .ai {
                    await aiChatState.restoreAfterForeground()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .televisionShouldRestoreUserInterface)) { _ in
            router.selectedTab = .television
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionPushRegistrationFailed)) { notification in
            guard let message = notification.object as? String else { return }
            actionInboxState.reportPushRegistrationFailure(message)
            pushRegistrationErrorMessage = message
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionPushRegistrationStatusChanged)) { _ in
            Task { await settingsState.refreshPushRegistrationState() }
        }
        .onChange(of: router.selectedTab) { previousTab, selectedTab in
            if previousTab == .television,
               selectedTab != .television,
               scenePhase == .active {
                televisionPlayerController.handleForegroundTabExit()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            televisionPlayerController.handleScenePhase(phase)
            if phase == .active, router.selectedTab != .television {
                televisionPlayerController.handleForegroundTabExit()
            }
            guard phase == .active,
                  Date().timeIntervalSince(lastForegroundRefreshAt) >= 15 else {
                return
            }
            lastForegroundRefreshAt = Date()
            blogPostState.refreshImportCandidates()
            Task {
                await productOpsState.loadRecommendationsIfPossible()
                if router.selectedTab == .articles {
                    await blogPostState.loadIfPossible()
                }
                if router.selectedTab == .ai {
                    await aiChatState.restoreAfterForeground()
                }
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
            blogPostState.refreshImportCandidates()
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
        case .venturePolicy:
            VenturePolicyView(state: productOpsState)
        case .actionHistory:
            ActionHistoryView(state: actionInboxState, mode: .history)
        case .completedActions:
            ActionHistoryView(state: actionInboxState, mode: .completed)
        case .article(let id):
            ArticleDetailView(id: id, state: blogPostState)
        case .aiConversation(let id):
            AIConversationDetailView(id: id, state: aiChatState)
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
