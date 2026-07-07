import SwiftUI

@MainActor
struct AppRootView: View {
    private let dependencies: AppDependencies

    @State private var router = AppRouter()
    @State private var todayState: TodayState
    @State private var settingsState: SettingsState

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _todayState = State(initialValue: TodayState(useCases: dependencies.useCases))
        _settingsState = State(initialValue: SettingsState(useCases: dependencies.useCases))
    }

    var body: some View {
        NavigationStack(
            path: Binding(
                get: { router.path },
                set: { router.path = $0 }
            )
        ) {
            TodayView(state: todayState)
                .navigationDestination(for: AppRoute.self, destination: routeContent)
        }
        .environment(router)
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
