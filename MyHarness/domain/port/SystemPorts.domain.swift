import Foundation

@MainActor
protocol NotificationScheduler {
    func permissionState() async -> NotificationPermissionState
    func requestPermission() async throws -> NotificationPermissionState
    func scheduleWeekdayNotifications(_ schedule: NotificationSchedule) async throws
}

@MainActor
protocol ClipboardWriter {
    func write(_ text: String)
}

protocol CalendarProviding {
    var calendar: Calendar { get }
    func dateKey(for date: Date) -> String
    func weekdayDates(containing date: Date) -> [Date]
    func shortWeekdayLabel(for date: Date) -> String
    func shortDateLabel(for date: Date) -> String
}

