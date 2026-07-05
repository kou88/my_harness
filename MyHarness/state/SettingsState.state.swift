import Foundation
import Observation

@MainActor
@Observable
final class SettingsState {
    var notificationDate: Date = NotificationSchedule.defaultWeekdayEvening.date()
    var scheduleText = NotificationSchedule.defaultWeekdayEvening.displayText
    var permissionText = NotificationPermissionState.notDetermined.label
    var widgetTextDirection: WidgetTextDirection = .horizontal
    var errorMessage: String?
    var isSaving = false

    private let useCases: AppUseCases

    init(useCases: AppUseCases) {
        self.useCases = useCases
    }

    func load() async {
        do {
            let schedule = try await useCases.loadNotificationSchedule.execute()
            let widgetSettings = try await useCases.loadWidgetDisplaySettings.execute()
            notificationDate = schedule.date()
            scheduleText = schedule.displayText
            permissionText = await useCases.notificationPermission.execute().label
            widgetTextDirection = widgetSettings.textDirection
            errorMessage = nil
        } catch {
            errorMessage = "設定の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func saveNotificationTime(_ date: Date) async {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        let schedule = NotificationSchedule(
            hour: components.hour ?? NotificationSchedule.defaultWeekdayEvening.hour,
            minute: components.minute ?? NotificationSchedule.defaultWeekdayEvening.minute
        )

        isSaving = true
        defer { isSaving = false }

        do {
            let permission = try await useCases.saveNotificationSchedule.execute(schedule)
            scheduleText = schedule.displayText
            permissionText = permission.label
            errorMessage = nil
        } catch {
            errorMessage = "通知設定に失敗しました: \(error.localizedDescription)"
        }
    }

    func saveWidgetTextDirection(_ direction: WidgetTextDirection) async {
        isSaving = true
        defer { isSaving = false }

        do {
            widgetTextDirection = direction
            try await useCases.saveWidgetDisplaySettings.execute(WidgetDisplaySettings(textDirection: direction))
            errorMessage = nil
        } catch {
            errorMessage = "ウィジェット設定に失敗しました: \(error.localizedDescription)"
        }
    }
}
