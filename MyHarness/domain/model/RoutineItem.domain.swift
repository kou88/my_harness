import Foundation

enum RoutineWeekday: Int, CaseIterable, Codable, Hashable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday:
            return "日"
        case .monday:
            return "月"
        case .tuesday:
            return "火"
        case .wednesday:
            return "水"
        case .thursday:
            return "木"
        case .friday:
            return "金"
        case .saturday:
            return "土"
        }
    }

    static var everyDay: Set<RoutineWeekday> {
        Set(allCases)
    }

    static var weekdays: Set<RoutineWeekday> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    static var weekends: Set<RoutineWeekday> {
        [.sunday, .saturday]
    }

    static func set(fromStorageValue value: String?) -> Set<RoutineWeekday> {
        let days = value?
            .split(separator: ",")
            .compactMap { Int($0).flatMap(RoutineWeekday.init(rawValue:)) } ?? []
        return days.isEmpty ? everyDay : Set(days)
    }

    static func storageValue(for days: Set<RoutineWeekday>) -> String {
        let normalized = days.isEmpty ? everyDay : days
        return normalized
            .sorted { $0.rawValue < $1.rawValue }
            .map { String($0.rawValue) }
            .joined(separator: ",")
    }
}

enum RoutineItemType: String, Codable, Hashable, Identifiable {
    case check

    var id: String { rawValue }

    var label: String {
        "チェック"
    }
}

enum RoutineScheduleKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case routine
    case oneShot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .routine:
            return "ルーチン"
        case .oneShot:
            return "単発"
        }
    }
}

struct RoutineItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var type: RoutineItemType
    var scheduleKind: RoutineScheduleKind
    var sortOrder: Int
    var repeatWeekdays: Set<RoutineWeekday>
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        type: RoutineItemType = .check,
        scheduleKind: RoutineScheduleKind,
        sortOrder: Int,
        repeatWeekdays: Set<RoutineWeekday> = RoutineWeekday.everyDay,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.scheduleKind = scheduleKind
        self.sortOrder = sortOrder
        self.repeatWeekdays = repeatWeekdays.isEmpty ? RoutineWeekday.everyDay : repeatWeekdays
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func isActive(on date: Date, calendar: Calendar) -> Bool {
        guard scheduleKind == .routine else { return true }
        let weekday = calendar.component(.weekday, from: date)
        guard let day = RoutineWeekday(rawValue: weekday) else {
            return true
        }
        return repeatWeekdays.contains(day)
    }

    func isVisible(
        on date: Date,
        dateKey: String,
        createdDateKey: String,
        completedDateKey: String?,
        calendar: Calendar
    ) -> Bool {
        switch scheduleKind {
        case .routine:
            return isActive(on: date, calendar: calendar)
        case .oneShot:
            guard dateKey >= createdDateKey else { return false }
            guard let completedDateKey else { return true }
            return dateKey <= completedDateKey
        }
    }

    var repeatWeekdaysLabel: String {
        if repeatWeekdays == RoutineWeekday.everyDay {
            return "毎日"
        }
        if repeatWeekdays == RoutineWeekday.weekdays {
            return "平日"
        }
        if repeatWeekdays == RoutineWeekday.weekends {
            return "土日"
        }

        let ordered = RoutineWeekday.allCases.filter { repeatWeekdays.contains($0) }
        return ordered.map(\.shortLabel).joined(separator: "・")
    }
}

struct WeekdayTaskGroup: Identifiable, Hashable {
    let weekday: RoutineWeekday
    var items: [RoutineItem]

    var id: Int { weekday.rawValue }
}
