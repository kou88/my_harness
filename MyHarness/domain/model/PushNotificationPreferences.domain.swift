import Foundation

struct PushNotificationPreferences: Codable, Hashable {
    var pushEnabled: Bool
    var missionEventsEnabled: Bool
    var recommendationsEnabled: Bool

    static let enabled = PushNotificationPreferences(
        pushEnabled: true,
        missionEventsEnabled: true,
        recommendationsEnabled: true
    )

    func allows(_ topic: PushNotificationTopic) -> Bool {
        guard pushEnabled else { return false }
        switch topic {
        case .missionUpdate:
            return missionEventsEnabled
        case .recommendation:
            return recommendationsEnabled
        case .article:
            return true
        case .ai:
            return true
        case .legacy:
            return true
        }
    }
}

enum PushDeviceRegistrationState: Hashable {
    case disabled
    case permissionRequired
    case permissionDenied
    case registering
    case registered
    case failed

    var label: String {
        switch self {
        case .disabled: return "無効"
        case .permissionRequired: return "通知許可が必要"
        case .permissionDenied: return "iOS設定で拒否"
        case .registering: return "登録中"
        case .registered: return "登録済み"
        case .failed: return "登録失敗"
        }
    }
}

enum PushNotificationTopic: Hashable {
    case missionUpdate
    case recommendation
    case article
    case ai
    case legacy
}

enum PushNotificationRouting {
    private static let aiTerminalEventTypes: Set<String> = [
        "ai_run_completed",
        "ai_run_failed"
    ]

    private static let allowedRouteHosts: Set<String> = [
        "next-actions",
        "suggestions",
        "proposal",
        "proposals",
        "mission",
        "missions",
        "development-missions",
        "research",
        "research-missions",
        "message",
        "message-missions",
        "verification",
        "verification-missions",
        "knowledge",
        "knowledge-change",
        "knowledge_change",
        "knowledge-change-missions",
        "decision-brief",
        "decision_brief",
        "decision-brief-missions",
        "monitoring-alert",
        "monitoring_alert",
        "monitoring-alerts",
        "articles",
        "ai"
    ]

    static func topic(from userInfo: [AnyHashable: Any]) -> PushNotificationTopic {
        let eventType = stringValue(userInfo["eventType"] ?? userInfo["event_type"])?.lowercased()
        if eventType == "venture_recommendations_ready" || eventType == "suggestion_created" {
            return .recommendation
        }
        if eventType == "blog_post_import_completed" {
            return .article
        }
        if eventType?.hasPrefix("ai_") == true {
            return .ai
        }
        if let eventType,
           eventType == "execution_completed"
            || eventType == "execution_failed"
            || eventType.hasSuffix("_mission_completed")
            || eventType.hasSuffix("_mission_failed") {
            return .missionUpdate
        }

        switch entityType(from: userInfo) {
        case "blog_post":
            return .article
        case "ai_approval", "ai_run":
            return .ai
        case "venture_recommendation_set":
            return .recommendation
        case "execution",
             "development_mission",
             "research_mission",
             "message_mission",
             "verification_mission",
             "knowledge_change_mission",
             "decision_brief_mission",
             "mission",
             "venture_mission",
             "generic_mission",
             "venture_generic_mission":
            return .missionUpdate
        default:
            return .legacy
        }
    }

    static func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL {
        if let route = stringValue(userInfo["route"]),
           let url = URL(string: route),
           url.scheme == "myharness",
           let host = url.host?.lowercased(),
           allowedRouteHosts.contains(host) {
            return url
        }

        guard let entityId = entityId(from: userInfo) else {
            return nextActionsURL
        }
        let route: String
        switch entityType(from: userInfo) {
        case "blog_post":
            route = "articles"
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
        case "venture_recommendation_set":
            return nextActionsURL
        default:
            return nextActionsURL
        }
        return URL(string: "myharness://\(route)/\(entityId)") ?? nextActionsURL
    }

    static func shouldPresentInForeground(
        userInfo: [AnyHashable: Any],
        visibleAIConversationId: String?
    ) -> Bool {
        guard
            let visibleAIConversationId = nonEmptyString(visibleAIConversationId),
            let eventType = stringValue(userInfo["eventType"] ?? userInfo["event_type"])?.lowercased(),
            aiTerminalEventTypes.contains(eventType),
            aiConversationId(from: userInfo) == visibleAIConversationId
        else {
            return true
        }
        return false
    }

    static let nextActionsURL = URL(string: "myharness://next-actions")!

    private static func entityType(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(userInfo["entityType"] ?? userInfo["entity_type"])?.lowercased()
    }

    private static func entityId(from userInfo: [AnyHashable: Any]) -> String? {
        stringValue(userInfo["entityId"] ?? userInfo["entity_id"] ?? userInfo["id"])
    }

    private static func aiConversationId(from userInfo: [AnyHashable: Any]) -> String? {
        guard
            let route = stringValue(userInfo["route"]),
            let url = URL(string: route),
            url.scheme?.lowercased() == "myharness",
            url.host?.lowercased() == "ai"
        else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.first?.lowercased() == "conversations" else { return nil }
        return nonEmptyString(components.dropFirst().first)
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        let raw: String?
        if let value = value as? String {
            raw = value
        } else if let value = value as? NSNumber {
            raw = value.stringValue
        } else {
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
