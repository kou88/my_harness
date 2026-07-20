import UserNotifications

@MainActor
final class LocalNotificationScheduler: NotificationScheduler {
    private let center: UNUserNotificationCenter
    private let identifiers = (2...6).map { "my-harness-weekday-\($0)" }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        return NotificationPermissionState(status: settings.authorizationStatus)
    }

    func requestPermission() async throws -> NotificationPermissionState {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await permissionState()
    }

    func scheduleWeekdayNotifications(_ schedule: NotificationSchedule) async throws {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for weekday in 2...6 {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = schedule.hour
            components.minute = schedule.minute

            let content = UNMutableNotificationContent()
            content.title = "my harness"
            content.body = "今日のチェックを確認する時間です。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "my-harness-weekday-\(weekday)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }
}

extension NotificationPermissionState {
    init(status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}
