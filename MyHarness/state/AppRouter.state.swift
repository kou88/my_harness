import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var presentedSheet: AppSheet?
    var selectedTab: AppTab = .today
    var nextActionsPath: [AppRoute] = []
    var todayPath: [AppRoute] = []

    func push(_ route: AppRoute) {
        switch route.preferredTab {
        case .nextActions:
            selectedTab = .nextActions
            nextActionsPath.append(route)
        case .today:
            selectedTab = .today
            todayPath.append(route)
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "myharness" else { return }

        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let head = host?.isEmpty == false ? host! : pathComponents.first
        let tail = host?.isEmpty == false ? pathComponents : Array(pathComponents.dropFirst())

        switch head {
        case "open":
            selectedTab = .nextActions
        case "suggestions":
            selectedTab = .nextActions
            nextActionsPath = tail.first.map { [.actionSuggestionDetail(id: $0)] } ?? []
        case "development":
            selectedTab = .nextActions
            nextActionsPath = [.developmentBacklog]
        case "policy":
            selectedTab = .nextActions
            nextActionsPath = [.projectPolicy]
        case "executions":
            routeSuggestionReference(.actionExecution(id: tail.first ?? ""))
        case "needs":
            routeSuggestionReference(.need(id: tail.first ?? ""))
        case "codex-results":
            routeSuggestionReference(.codexResult(id: tail.first ?? ""))
        case "auth":
            break
        default:
            selectedTab = .today
        }
    }

    private func routeSuggestionReference(_ route: AppRoute) {
        selectedTab = .nextActions
        nextActionsPath = route.referenceId.isEmpty ? [] : [route]
    }
}

enum AppTab: Hashable {
    case nextActions
    case today
}

enum AppRoute: Hashable {
    case oneShotTasks
    case actionSuggestionDetail(id: String)
    case actionExecution(id: String)
    case need(id: String)
    case codexResult(id: String)
    case needList
    case developmentBacklog
    case projectPolicy
    case actionHistory
    case completedActions

    var preferredTab: AppTab {
        switch self {
        case .oneShotTasks:
            return .today
        case .actionSuggestionDetail,
             .actionExecution,
             .need,
             .codexResult,
             .needList,
             .developmentBacklog,
             .projectPolicy,
             .actionHistory,
             .completedActions:
            return .nextActions
        }
    }

    var referenceId: String {
        switch self {
        case .oneShotTasks:
            return ""
        case .actionSuggestionDetail(let id),
             .actionExecution(let id),
             .need(let id),
             .codexResult(let id):
            return id
        case .needList,
             .developmentBacklog,
             .projectPolicy,
             .actionHistory,
             .completedActions:
            return ""
        }
    }
}

enum AppSheet: Identifiable, Hashable {
    case addItem
    case editItem(RoutineItem)
    case settings
    case weeklyExport(String)

    var id: String {
        switch self {
        case .addItem:
            return "addItem"
        case .editItem(let item):
            return "editItem-\(item.id.uuidString)"
        case .settings:
            return "settings"
        case .weeklyExport:
            return "weeklyExport"
        }
    }
}
