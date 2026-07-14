import Foundation
import WidgetKit

@MainActor
final class SharedWidgetSnapshotRepository: WidgetSnapshotRepository, WidgetSettingsRepository {
    private enum Key {
        static let snapshot = "my_harness.widget.snapshot"
        static let pendingUpdates = "my_harness.widget.pending_updates"
        static let displaySettings = "my_harness.widget.display_settings"
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

    func loadDisplaySettings() async throws -> WidgetDisplaySettings {
        guard let data = defaults.data(forKey: Key.displaySettings) else {
            return .default
        }

        return (try? decoder.decode(WidgetDisplaySettings.self, from: data)) ?? .default
    }

    func saveDisplaySettings(_ settings: WidgetDisplaySettings) async throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: Key.displaySettings)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
