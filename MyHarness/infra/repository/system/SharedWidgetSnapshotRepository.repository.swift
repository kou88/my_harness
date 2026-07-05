import Foundation
import WidgetKit

@MainActor
final class SharedWidgetSnapshotRepository: WidgetSnapshotRepository {
    private enum Key {
        static let snapshot = "my_harness.widget.snapshot"
        static let pendingUpdates = "my_harness.widget.pending_updates"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(appGroupIdentifier: String = HarnessAppGroup.identifier) {
        defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    func publish(_ snapshot: WidgetTodaySnapshot) async throws {
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: Key.snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func consumePendingEntryUpdates() async throws -> [WidgetPendingEntryUpdate] {
        guard let data = defaults.data(forKey: Key.pendingUpdates) else {
            return []
        }

        let updates = try decoder.decode([WidgetPendingEntryUpdate].self, from: data)
        defaults.removeObject(forKey: Key.pendingUpdates)
        return updates
    }
}

