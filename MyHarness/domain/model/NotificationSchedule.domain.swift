import Foundation

struct NotificationSchedule: Codable, Hashable {
    var hour: Int
    var minute: Int

    static let defaultWeekdayEvening = NotificationSchedule(hour: 20, minute: 0)

    var displayText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func date(on baseDate: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        var next = DateComponents()
        next.year = components.year
        next.month = components.month
        next.day = components.day
        next.hour = hour
        next.minute = minute
        return calendar.date(from: next) ?? baseDate
    }
}

enum NotificationPermissionState: String, Hashable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var label: String {
        switch self {
        case .notDetermined:
            return "未確認"
        case .denied:
            return "拒否"
        case .authorized:
            return "許可済み"
        case .provisional:
            return "仮許可"
        case .ephemeral:
            return "一時許可"
        case .unknown:
            return "不明"
        }
    }
}
