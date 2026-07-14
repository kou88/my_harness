import Foundation

enum WidgetTextDirection: String, CaseIterable, Codable, Hashable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal:
            return "横書き"
        case .vertical:
            return "縦書き"
        }
    }
}

struct WidgetDisplaySettings: Codable, Hashable {
    var textDirection: WidgetTextDirection

    static var `default`: WidgetDisplaySettings {
        WidgetDisplaySettings(textDirection: .horizontal)
    }
}
