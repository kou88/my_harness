@MainActor
protocol SettingsRepository {
    func notificationSchedule() async throws -> NotificationSchedule
    func saveNotificationSchedule(_ schedule: NotificationSchedule) async throws
}

