import Foundation
import Observation

@MainActor
@Observable
final class SettingsState {
    var notificationDate: Date = NotificationSchedule.defaultWeekdayEvening.date()
    var scheduleText = NotificationSchedule.defaultWeekdayEvening.displayText
    var permissionText = NotificationPermissionState.notDetermined.label
    var pushPreferences = PushNotificationPreferences.enabled
    var pushPermissionState = NotificationPermissionState.notDetermined
    var pushRegistrationState = PushDeviceRegistrationState.permissionRequired
    var canEditPushPreferences = false
    var widgetTextDirection: WidgetTextDirection = .horizontal
    var errorMessage: String?
    var isSaving = false
    var isSavingPush = false

    private let useCases: AppUseCases
    private let authSession: CognitoAuthSession?
    private let apiClient: ActionInboxAPIClient?

    init(
        useCases: AppUseCases,
        authSession: CognitoAuthSession?,
        apiClient: ActionInboxAPIClient?
    ) {
        self.useCases = useCases
        self.authSession = authSession
        self.apiClient = apiClient
    }

    func load() async {
        canEditPushPreferences = false
        do {
            let schedule = try await useCases.loadNotificationSchedule.execute()
            let widgetSettings = try await useCases.loadWidgetDisplaySettings.execute()
            notificationDate = schedule.date()
            scheduleText = schedule.displayText
            permissionText = await useCases.notificationPermission.execute().label
            pushPreferences = ActionPushNotificationCoordinator.shared.preferences
            await refreshPushRegistrationState()
            widgetTextDirection = widgetSettings.textDirection
            if authSession?.isSignedIn == true, let apiClient {
                let serverPreferences = try await apiClient.fetchNotificationPreferences()
                pushPreferences = serverPreferences
                canEditPushPreferences = true
                try await ActionPushNotificationCoordinator.shared.synchronizeAfterSignIn(serverPreferences)
                await refreshPushRegistrationState()
            } else {
                canEditPushPreferences = false
            }
            errorMessage = nil
        } catch {
            canEditPushPreferences = false
            errorMessage = "設定の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func setPushEnabled(_ isEnabled: Bool) async {
        var updated = pushPreferences
        updated.pushEnabled = isEnabled
        await savePushPreferences(updated)
    }

    func setMissionUpdatesEnabled(_ isEnabled: Bool) async {
        var updated = pushPreferences
        updated.missionEventsEnabled = isEnabled
        await savePushPreferences(updated)
    }

    func setRecommendationsEnabled(_ isEnabled: Bool) async {
        var updated = pushPreferences
        updated.recommendationsEnabled = isEnabled
        await savePushPreferences(updated)
    }

    func openSystemNotificationSettings() {
        ActionPushNotificationCoordinator.shared.openSystemNotificationSettings()
    }

    func requestPushAuthorization() async {
        guard !isSavingPush else { return }
        isSavingPush = true
        defer { isSavingPush = false }
        do {
            try await ActionPushNotificationCoordinator.shared.requestAuthorizationAndRegister()
            pushPreferences = ActionPushNotificationCoordinator.shared.preferences
            await refreshPushRegistrationState()
            errorMessage = nil
        } catch {
            pushPreferences = ActionPushNotificationCoordinator.shared.preferences
            await refreshPushRegistrationState()
            errorMessage = "Push通知設定に失敗しました: \(error.localizedDescription)"
        }
    }

    func refreshPushRegistrationState() async {
        pushPermissionState = await ActionPushNotificationCoordinator.shared.permissionState()
        pushRegistrationState = ActionPushNotificationCoordinator.shared.registrationState(
            permission: pushPermissionState
        )
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

    private func savePushPreferences(_ preferences: PushNotificationPreferences) async {
        guard !isSavingPush, canEditPushPreferences, let apiClient else {
            errorMessage = "Push通知設定を変更するにはログインが必要です。"
            return
        }
        isSavingPush = true
        defer { isSavingPush = false }

        do {
            let saved = try await apiClient.updateNotificationPreferences(preferences)
            pushPreferences = saved
            try await ActionPushNotificationCoordinator.shared.updatePreferences(saved)
            await refreshPushRegistrationState()
            errorMessage = nil
        } catch {
            await refreshPushRegistrationState()
            errorMessage = "Push通知設定に失敗しました: \(error.localizedDescription)"
        }
    }
}
