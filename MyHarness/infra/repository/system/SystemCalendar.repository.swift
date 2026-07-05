import Foundation

struct SystemCalendar: CalendarProviding {
    var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func weekdayDates(containing date: Date) -> [Date] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return [date]
        }
        return (0..<5).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    func shortWeekdayLabel(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 2:
            return "月"
        case 3:
            return "火"
        case 4:
            return "水"
        case 5:
            return "木"
        case 6:
            return "金"
        case 7:
            return "土"
        default:
            return "日"
        }
    }

    func shortDateLabel(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d/%02d/%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
