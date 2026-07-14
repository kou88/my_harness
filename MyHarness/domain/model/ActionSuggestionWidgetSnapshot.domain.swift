import Foundation

struct ActionSuggestionWidgetItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var summary: String
    var riskLabel: String
    var updatedAt: Date?
}

struct ActionSuggestionWidgetSnapshot: Codable, Hashable {
    var updatedAt: Date
    var pendingCount: Int
    var highRiskCount: Int
    var items: [ActionSuggestionWidgetItem]

    static var empty: ActionSuggestionWidgetSnapshot {
        ActionSuggestionWidgetSnapshot(updatedAt: Date(), pendingCount: 0, highRiskCount: 0, items: [])
    }
}
