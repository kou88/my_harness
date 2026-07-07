import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var presentedSheet: AppSheet?
    var path: [AppRoute] = []

    func push(_ route: AppRoute) {
        path.append(route)
    }
}

enum AppRoute: Hashable {
    case oneShotTasks
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
