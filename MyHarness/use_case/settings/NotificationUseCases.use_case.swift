@MainActor
struct LoadNotificationScheduleUseCase {
    let repository: SettingsRepository

    func execute() async throws -> NotificationSchedule {
        try await repository.notificationSchedule()
    }
}

@MainActor
struct SaveNotificationScheduleUseCase {
    let repository: SettingsRepository
    let scheduler: NotificationScheduler

    func execute(_ schedule: NotificationSchedule) async throws -> NotificationPermissionState {
        try await repository.saveNotificationSchedule(schedule)
        let state = try await scheduler.requestPermission()
        if state == .authorized || state == .provisional || state == .ephemeral {
            try await scheduler.scheduleWeekdayNotifications(schedule)
        }
        return state
    }
}

@MainActor
struct NotificationPermissionUseCase {
    let scheduler: NotificationScheduler

    func execute() async -> NotificationPermissionState {
        await scheduler.permissionState()
    }
}

