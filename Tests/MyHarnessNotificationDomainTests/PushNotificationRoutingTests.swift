import Foundation
import Testing
@testable import MyHarnessNotificationDomain

@Test func defaultPreferencesEnableRequestedNotifications() {
    let preferences = PushNotificationPreferences.enabled

    #expect(preferences.allows(.missionUpdate))
    #expect(preferences.allows(.recommendation))
    #expect(preferences.allows(.legacy))
}

@Test func masterSwitchDisablesEveryNotificationTopic() {
    let preferences = PushNotificationPreferences(
        pushEnabled: false,
        missionEventsEnabled: true,
        recommendationsEnabled: true
    )

    #expect(!preferences.allows(.missionUpdate))
    #expect(!preferences.allows(.recommendation))
    #expect(!preferences.allows(.legacy))
}

@Test func notificationPreferencesUseServerContractFieldNames() throws {
    let encoded = try JSONEncoder().encode(PushNotificationPreferences.enabled)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Bool])

    #expect(object["pushEnabled"] == true)
    #expect(object["missionEventsEnabled"] == true)
    #expect(object["recommendationsEnabled"] == true)
    #expect(object["missionUpdatesEnabled"] == nil)
}

@Test func classifiesMissionAndRecommendationPayloads() {
    #expect(PushNotificationRouting.topic(from: ["entityType": "research_mission"]) == .missionUpdate)
    #expect(PushNotificationRouting.topic(from: ["entity_type": "venture_recommendation_set"]) == .recommendation)
    #expect(PushNotificationRouting.topic(from: ["eventType": "development_mission_failed"]) == .missionUpdate)
    #expect(PushNotificationRouting.topic(from: ["event_type": "venture_recommendations_ready"]) == .recommendation)
}

@Test func routesMissionToItsDetail() {
    let url = PushNotificationRouting.deepLinkURL(from: [
        "entityType": "message_mission",
        "entityId": "mission-123"
    ])

    #expect(url.absoluteString == "myharness://message-missions/mission-123")
}

@Test func recommendationAndUnknownTargetsFallBackToNextActions() {
    let recommendation = PushNotificationRouting.deepLinkURL(from: [
        "entityType": "venture_recommendation_set",
        "entityId": "set-123"
    ])
    let unknown = PushNotificationRouting.deepLinkURL(from: [
        "entityType": "unknown",
        "entityId": "unknown-123"
    ])

    #expect(recommendation == PushNotificationRouting.nextActionsURL)
    #expect(unknown == PushNotificationRouting.nextActionsURL)
}

@Test func acceptsOnlyKnownAppRoutes() {
    let allowed = PushNotificationRouting.deepLinkURL(from: [
        "route": "myharness://research-missions/mission-123"
    ])
    let rejected = PushNotificationRouting.deepLinkURL(from: [
        "route": "myharness://auth/callback"
    ])

    #expect(allowed.absoluteString == "myharness://research-missions/mission-123")
    #expect(rejected == PushNotificationRouting.nextActionsURL)
}
