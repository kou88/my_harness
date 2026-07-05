import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private enum Key {
        static let root = "root"
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func notificationSchedule() async throws -> NotificationSchedule {
        if let model = try settingsModel() {
            return NotificationSchedule(hour: model.notificationHour, minute: model.notificationMinute)
        }
        return .defaultWeekdayEvening
    }

    func saveNotificationSchedule(_ schedule: NotificationSchedule) async throws {
        if let model = try settingsModel() {
            model.notificationHour = schedule.hour
            model.notificationMinute = schedule.minute
        } else {
            context.insert(HarnessSettingsModel(
                key: Key.root,
                notificationHour: schedule.hour,
                notificationMinute: schedule.minute
            ))
        }
        try context.save()
    }

    private func settingsModel() throws -> HarnessSettingsModel? {
        let rootKey = Key.root
        var descriptor = FetchDescriptor<HarnessSettingsModel>(
            predicate: #Predicate { model in
                model.key == rootKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
