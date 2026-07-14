import SwiftUI

@MainActor
struct AppRootView: View {
    private let dependencies: AppDependencies

    @State private var router = AppRouter()
    @State private var todayState: TodayState
    @State private var settingsState: SettingsState
    @State private var actionInboxState: ActionInboxState

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _todayState = State(initialValue: TodayState(useCases: dependencies.useCases))
        _settingsState = State(initialValue: SettingsState(useCases: dependencies.useCases))
        _actionInboxState = State(initialValue: ActionInboxState(
            authSession: dependencies.actionInbox.authSession,
            apiClient: dependencies.actionInbox.apiClient,
            widgetRepository: dependencies.actionInbox.widgetRepository,
            configurationErrorMessage: dependencies.actionInbox.configurationErrorMessage
        ))
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
                    get: { router.suggestionsPath },
                    set: { router.suggestionsPath = $0 }
                )
            ) {
                ActionInboxView(state: actionInboxState)
                    .navigationDestination(for: AppRoute.self, destination: routeContent)
            }
            .tabItem {
                Label("おすすめ", systemImage: "sparkles")
            }
            .tag(AppTab.suggestions)
        }
        .environment(router)
        .onOpenURL { url in
            router.handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionInboxDeepLink)) { notification in
            guard let url = notification.object as? URL else { return }
            router.handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionInboxShouldReload)) { _ in
            Task { await actionInboxState.loadIfPossible() }
        }
        .sheet(
            item: Binding(
                get: { router.presentedSheet },
                set: { router.presentedSheet = $0 }
            ),
            content: sheetContent
        )
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
