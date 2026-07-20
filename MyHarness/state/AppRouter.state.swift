import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var presentedSheet: AppSheet?
    var selectedTab: AppTab = .today
    var nextActionsPath: [AppRoute] = []
    var todayPath: [AppRoute] = []
    var pendingProductOpsDeepLink: ProductOpsDeepLinkDestination?

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
            selectedTab = .today
            todayPath = []
        case "next-actions":
            showNextActions()
        case "suggestions":
            if let id = nonEmptyId(tail.first) {
                selectedTab = .nextActions
                nextActionsPath = [.actionSuggestionDetail(id: id)]
            } else {
                showNextActions()
            }
        case "proposal", "proposals":
            showProductOpsDetail(nonEmptyId(tail.first).map(ProductOpsDeepLinkDestination.proposal))
        case "mission", "missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .generic)
            })
        case "development-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .development)
            })
        case "research", "research-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .research)
            })
        case "message", "message-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .message)
            })
        case "verification", "verification-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .verification)
            })
        case "knowledge", "knowledge-change", "knowledge_change", "knowledge-change-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .knowledgeChange)
            })
        case "decision-brief", "decision_brief", "decision-brief-missions":
            showProductOpsDetail(nonEmptyId(tail.first).map {
                ProductOpsDeepLinkDestination.mission(id: $0, kind: .decisionBrief)
            })
        case "monitoring-alert", "monitoring_alert", "monitoring-alerts":
            showProductOpsDetail(nonEmptyId(tail.first).map(ProductOpsDeepLinkDestination.monitoringAlert))
        case "development":
            if let id = nonEmptyId(tail.first) {
                showProductOpsDetail(.mission(id: id, kind: .development))
            } else {
                selectedTab = .nextActions
                nextActionsPath = [.developmentBacklog]
            }
        case "policy":
            selectedTab = .nextActions
            nextActionsPath = [.venturePolicy]
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

    func consumePendingProductOpsDeepLink() -> ProductOpsDeepLinkDestination? {
        defer { pendingProductOpsDeepLink = nil }
        return pendingProductOpsDeepLink
    }

    private func showNextActions() {
        selectedTab = .nextActions
        nextActionsPath = []
        pendingProductOpsDeepLink = nil
    }

    private func showProductOpsDetail(_ destination: ProductOpsDeepLinkDestination?) {
        showNextActions()
        pendingProductOpsDeepLink = destination
    }

    private func nonEmptyId(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func routeSuggestionReference(_ route: AppRoute) {
        selectedTab = .nextActions
        nextActionsPath = route.referenceId.isEmpty ? [] : [route]
    }
}

enum ProductOpsMissionDeepLinkKind: String, Hashable {
    case generic
    case development
    case research
    case message
    case verification
    case knowledgeChange
    case decisionBrief

    var label: String {
        switch self {
        case .generic: return "Mission"
        case .development: return "Codex実装"
        case .research: return "調査"
        case .message: return "文案"
        case .verification: return "検証"
        case .knowledgeChange: return "Knowledge"
        case .decisionBrief: return "判断材料"
        }
    }
}

enum ProductOpsDeepLinkDestination: Identifiable, Hashable {
    case proposal(String)
    case mission(id: String, kind: ProductOpsMissionDeepLinkKind)
    case monitoringAlert(String)

    var id: String {
        switch self {
        case .proposal(let id):
            return "proposal-\(id)"
        case .mission(let id, let kind):
            return "mission-\(kind.rawValue)-\(id)"
        case .monitoringAlert(let id):
            return "monitoring-alert-\(id)"
        }
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
    case venturePolicy
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
             .venturePolicy,
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
             .venturePolicy,
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
