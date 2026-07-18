import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let actionInboxDeepLink = Notification.Name("my_harness.action_inbox.deep_link")
    static let actionInboxShouldReload = Notification.Name("my_harness.action_inbox.should_reload")
    static let actionPushRegistrationFailed = Notification.Name("my_harness.action_push.registration_failed")
}

enum ActionSuggestionNotification {
    static let lowRiskCategory = "ACTION_SUGGESTION_LOW_RISK"
    static let reviewCategory = "ACTION_SUGGESTION_REVIEW"
    static let dangerousCategory = "ACTION_SUGGESTION_DANGEROUS"
    static let approveAction = "ACTION_SUGGESTION_APPROVE"
    static let laterAction = "ACTION_SUGGESTION_LATER"
    static let rejectAction = "ACTION_SUGGESTION_REJECT"
    static let detailAction = "ACTION_SUGGESTION_DETAIL"
}

@MainActor
final class ActionPushNotificationCoordinator {
    enum PushError: LocalizedError {
        case permissionDenied
        case missingAppVersion

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "通知権限が許可されていません。"
            case .missingAppVersion:
                return "アプリバージョンを取得できません。"
            }
        }
    }

    static let shared = ActionPushNotificationCoordinator()

    private enum Key {
        static let deviceToken = "my_harness.action_inbox.apns_token"
        static let pushDeviceId = "my_harness.action_inbox.push_device_id"
        static let registrationError = "my_harness.action_inbox.push_registration_error"
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var apiClient: ActionInboxAPIClient?

    func configure(apiClient: ActionInboxAPIClient?, registerStoredToken: Bool = true) {
        self.apiClient = apiClient
        registerNotificationCategories()
        guard registerStoredToken else { return }
        Task {
            do {
                try await registerStoredDeviceTokenIfPossible()
            } catch {
                reportRegistrationFailure(error)
            }
        }
    }

    func registerNotificationCategories() {
        let approve = UNNotificationAction(
            identifier: ActionSuggestionNotification.approveAction,
            title: "承認",
            options: [.authenticationRequired]
        )
        let later = UNNotificationAction(
            identifier: ActionSuggestionNotification.laterAction,
            title: "後で",
            options: []
        )
        let reject = UNNotificationAction(
            identifier: ActionSuggestionNotification.rejectAction,
            title: "却下",
            options: [.destructive]
        )
        let detail = UNNotificationAction(
            identifier: ActionSuggestionNotification.detailAction,
            title: "詳細を開く",
            options: [.foreground]
        )

        let lowRisk = UNNotificationCategory(
            identifier: ActionSuggestionNotification.lowRiskCategory,
            actions: [approve, later, reject],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let review = UNNotificationCategory(
            identifier: ActionSuggestionNotification.reviewCategory,
            actions: [detail],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let dangerous = UNNotificationCategory(
            identifier: ActionSuggestionNotification.dangerousCategory,
            actions: [detail],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([lowRisk, review, dangerous])
    }

    var registrationErrorMessage: String? {
        defaults.string(forKey: Key.registrationError)
    }

    func requestAuthorizationAndRegister() async throws {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let settings = await center.notificationSettings()
        guard granted || settings.authorizationStatus == .provisional else {
            throw PushError.permissionDenied
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: Key.deviceToken)
        Task {
            do {
                try await registerStoredDeviceTokenIfPossible()
            } catch {
                reportRegistrationFailure(error)
            }
        }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        defaults.removeObject(forKey: Key.deviceToken)
        reportRegistrationFailure(error)
    }

    func handle(response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let deepLink = deepLinkURL(from: userInfo)

        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            return
        }

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier
            || response.actionIdentifier == ActionSuggestionNotification.detailAction {
            openDeepLink(deepLink)
            return
        }

        guard
            entityType(from: userInfo) == "action_suggestion",
            response.notification.request.content.categoryIdentifier == ActionSuggestionNotification.lowRiskCategory,
            let suggestionId = suggestionId(from: userInfo),
            let decision = decision(for: response.actionIdentifier),
            canRunDirectDecision(userInfo: userInfo),
            let expectedVersion = expectedVersion(from: userInfo),
            let apiClient
        else {
            openDeepLink(deepLink)
            return
        }

        do {
            try await apiClient.decideSuggestion(
                id: suggestionId,
                decision: decision,
                expectedVersion: expectedVersion,
                decisionNote: "通知から\(decision.label)",
                hostId: stringValue(userInfo["hostId"])
            )
            NotificationCenter.default.post(name: .actionInboxShouldReload, object: nil)
        } catch {
            openDeepLink(deepLink)
        }
    }

    func openSuggestion(id: String) {
        openDeepLink(URL(string: "myharness://suggestions/\(id)"))
    }

    private func openDeepLink(_ url: URL?) {
        guard let url else { return }
        NotificationCenter.default.post(name: .actionInboxDeepLink, object: url)
    }

    private func registerStoredDeviceTokenIfPossible() async throws {
        guard
            let token = defaults.string(forKey: Key.deviceToken),
            let apiClient
        else {
            return
        }
        let pushDeviceId = try await apiClient.registerPushDevice(
            token: token,
            environment: pushEnvironment,
            appVersion: try appVersion()
        )
        defaults.set(pushDeviceId, forKey: Key.pushDeviceId)
        defaults.removeObject(forKey: Key.registrationError)
    }

    private var pushEnvironment: ActionInboxAPIClient.PushEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    private func appVersion() throws -> String {
        guard
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            throw PushError.missingAppVersion
        }
        return "\(version) (\(build))"
    }

    private func decision(for actionIdentifier: String) -> ActionSuggestionDecision? {
        switch actionIdentifier {
        case ActionSuggestionNotification.approveAction:
            return .approved
        case ActionSuggestionNotification.laterAction:
            return .later
        case ActionSuggestionNotification.rejectAction:
            return .rejected
        default:
            return nil
        }
    }

    private func canRunDirectDecision(userInfo: [AnyHashable: Any]) -> Bool {
        if boolValue(userInfo["requiresAppConfirmation"]) == true || boolValue(userInfo["requiresConfirmation"]) == true {
            return false
        }

        let risk = stringValue(userInfo["riskLevel"] ?? userInfo["risk_level"])?.lowercased()
        guard risk == nil || risk == ActionSuggestionRiskLevel.low.rawValue else {
            return false
        }

        let operationText = [
            userInfo["actionType"],
            userInfo["action_type"],
            userInfo["sourceType"],
            userInfo["source_type"],
            userInfo["operationType"],
            userInfo["operation_type"]
        ]
            .compactMap { stringValue($0) }
            .joined(separator: " ")
            .lowercased()

        return [
            "adopt-result",
            "codex",
            "external",
            "send",
            "deploy",
            "production",
            "prod",
            "pull_request",
            "pr"
        ].allSatisfy { !operationText.contains($0) }
    }

    private func suggestionId(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(
            userInfo["suggestionId"]
                ?? userInfo["suggestion_id"]
                ?? userInfo["actionSuggestionId"]
                ?? userInfo["action_suggestion_id"]
                ?? userInfo["entityId"]
                ?? userInfo["entity_id"]
                ?? userInfo["id"]
        )
    }

    private func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL? {
        if let route = stringValue(userInfo["route"]),
           let url = URL(string: route),
           url.scheme == "myharness" {
            return url
        }

        guard let entityId = entityId(from: userInfo) else {
            return URL(string: "myharness://next-actions")
        }
        let route: String
        switch entityType(from: userInfo) {
        case "action_suggestion":
            route = "suggestions"
        case "proposal", "venture_proposal":
            route = "proposals"
        case "development_mission":
            route = "development-missions"
        case "research_mission":
            route = "research-missions"
        case "message_mission":
            route = "message-missions"
        case "verification_mission":
            route = "verification-missions"
        case "knowledge_change_mission":
            route = "knowledge-change-missions"
        case "decision_brief_mission":
            route = "decision-brief-missions"
        case "monitoring_alert":
            route = "monitoring-alerts"
        case "mission", "venture_mission", "generic_mission", "venture_generic_mission":
            route = "missions"
        default:
            return URL(string: "myharness://next-actions")
        }
        return URL(string: "myharness://\(route)/\(entityId)")
    }

    private func entityType(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(userInfo["entityType"] ?? userInfo["entity_type"])
    }

    private func entityId(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(userInfo["entityId"] ?? userInfo["entity_id"] ?? userInfo["id"])
    }

    private func reportRegistrationFailure(_ error: Error) {
        let message = "Push通知の端末登録に失敗しました: \(error.localizedDescription)"
        defaults.set(message, forKey: Key.registrationError)
        NotificationCenter.default.post(
            name: .actionPushRegistrationFailed,
            object: message
        )
    }

    private func expectedVersion(from userInfo: [AnyHashable: Any]) -> Int? {
        intValue(userInfo["expectedVersion"] ?? userInfo["expected_version"] ?? userInfo["version"])
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return nil
    }
}

@MainActor
final class MyHarnessAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ActionPushNotificationCoordinator.shared.registerNotificationCategories()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        ActionPushNotificationCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        ActionPushNotificationCoordinator.shared.didFailToRegisterForRemoteNotifications(error: error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await ActionPushNotificationCoordinator.shared.handle(response: response)
    }
}
