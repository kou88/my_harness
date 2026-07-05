import Foundation

@MainActor
struct BuildWeeklyExportUseCase {
    let readStore: WeekReadStore
    let calendar: CalendarProviding

    func execute(containing date: Date = Date()) async throws -> String {
        let week = try await readStore.weekdaySnapshots(containing: date)
        guard let first = week.first?.date, let last = week.last?.date else {
            return "my harness\n"
        }

        var lines: [String] = []
        lines.append("my harness")
        lines.append("\(calendar.shortDateLabel(for: first)) - \(calendar.shortDateLabel(for: last))")
        lines.append("")

        for day in week {
            lines.append("\(calendar.shortWeekdayLabel(for: day.date)) \(calendar.shortDateLabel(for: day.date))")

            if day.items.isEmpty {
                lines.append("- 項目なし")
            } else {
                for snapshot in day.items {
                    let completed = snapshot.entry?.isCompleted == true
                    let mark = completed ? "x" : " "
                    lines.append("- [\(mark)] \(snapshot.item.title)")

                    let logText = snapshot.entry?.logText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if snapshot.item.type == .checkLog, !logText.isEmpty {
                        lines.append("  - log: \(logText)")
                    }
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct CopyTextUseCase {
    let clipboard: ClipboardWriter

    func execute(_ text: String) {
        clipboard.write(text)
    }
}

