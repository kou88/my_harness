import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var presentedSheet: AppSheet?
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
