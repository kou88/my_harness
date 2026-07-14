import Foundation
import WidgetKit

@MainActor
final class ActionSuggestionWidgetSnapshotRepository {
    private enum Key {
        static let snapshot = "my_harness.action_suggestions.widget_snapshot"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(appGroupIdentifier: String = HarnessAppGroup.identifier) {
        defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    func publish(_ snapshot: ActionSuggestionWidgetSnapshot) async throws {
        defaults.set(try encoder.encode(snapshot), forKey: Key.snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
