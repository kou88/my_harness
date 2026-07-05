import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetAppGroup {
    static let identifier = "group.com.kou888.myharness"
}

private enum WidgetStoreKey {
    static let snapshot = "my_harness.widget.snapshot"
    static let pendingUpdates = "my_harness.widget.pending_updates"
}

private struct WidgetItemSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sortOrder: Int
    var isCompleted: Bool
}

private struct WidgetTodaySnapshot: Codable, Hashable {
    var dateKey: String
    var updatedAt: Date
    var items: [WidgetItemSnapshot]

    static var empty: WidgetTodaySnapshot {
        WidgetTodaySnapshot(dateKey: Self.todayDateKey(), updatedAt: Date(), items: [])
    }

    static func todayDateKey(date: Date = Date()) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct WidgetPendingEntryUpdate: Identifiable, Codable {
    let id: UUID
    var dateKey: String
    var itemId: UUID
    var isCompleted: Bool
    var updatedAt: Date
}

private enum WidgetSharedStore {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetAppGroup.identifier) ?? .standard
    }

    static func readSnapshot() -> WidgetTodaySnapshot {
        guard
            let data = defaults.data(forKey: WidgetStoreKey.snapshot),
            let snapshot = try? JSONDecoder().decode(WidgetTodaySnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    static func writeSnapshot(_ snapshot: WidgetTodaySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetStoreKey.snapshot)
        }
    }

    static func appendPendingUpdate(_ update: WidgetPendingEntryUpdate) {
        var updates: [WidgetPendingEntryUpdate] = []
        if
            let data = defaults.data(forKey: WidgetStoreKey.pendingUpdates),
            let decoded = try? JSONDecoder().decode([WidgetPendingEntryUpdate].self, from: data)
        {
            updates = decoded
        }
        updates.append(update)
        if let data = try? JSONEncoder().encode(updates) {
            defaults.set(data, forKey: WidgetStoreKey.pendingUpdates)
        }
    }
}

struct ToggleHarnessItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle my harness item"
    static var description = IntentDescription("Toggle a my harness checklist item from the widget.")
    static var openAppWhenRun = false

    @Parameter(title: "Item ID")
    var itemId: String

    init() {
        itemId = ""
    }

    init(itemId: UUID) {
        self.itemId = itemId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: itemId) else {
            return .result()
        }

        var snapshot = WidgetSharedStore.readSnapshot()
        guard let index = snapshot.items.firstIndex(where: { $0.id == uuid }) else {
            return .result()
        }

        snapshot.items[index].isCompleted.toggle()
        snapshot.updatedAt = Date()
        WidgetSharedStore.writeSnapshot(snapshot)
        WidgetSharedStore.appendPendingUpdate(WidgetPendingEntryUpdate(
            id: UUID(),
            dateKey: snapshot.dateKey,
            itemId: uuid,
            isCompleted: snapshot.items[index].isCompleted,
            updatedAt: snapshot.updatedAt
        ))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private struct HarnessTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTodaySnapshot
}

private struct HarnessTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HarnessTimelineEntry {
        HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
            dateKey: WidgetTodaySnapshot.todayDateKey(),
            updatedAt: Date(),
            items: [
                WidgetItemSnapshot(
                    id: UUID(),
                    title: "睡眠メモ",
                    sortOrder: 0,
                    isCompleted: false
                )
            ]
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (HarnessTimelineEntry) -> Void) {
        completion(HarnessTimelineEntry(date: Date(), snapshot: WidgetSharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HarnessTimelineEntry>) -> Void) {
        let entry = HarnessTimelineEntry(date: Date(), snapshot: WidgetSharedStore.readSnapshot())
        let nextReload = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }
}

private struct MyHarnessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HarnessTimelineEntry

    private var visibleItems: [WidgetItemSnapshot] {
        switch family {
        case .systemSmall:
            Array(entry.snapshot.items.prefix(3))
        case .accessoryRectangular:
            Array(entry.snapshot.items.prefix(2))
        default:
            Array(entry.snapshot.items.prefix(6))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleItems.isEmpty {
                Text("項目なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleItems) { item in
                        Button(intent: ToggleHarnessItemIntent(itemId: item.id)) {
                            HStack(spacing: 6) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                                Text(item.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .strikethrough(item.isCompleted)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
    }
}

struct MyHarnessWidget: Widget {
    let kind = "MyHarnessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HarnessTimelineProvider()) { entry in
            MyHarnessWidgetView(entry: entry)
        }
        .configurationDisplayName("my harness")
        .description("今日のチェック項目を表示して、ウィジェットから完了状態を切り替えます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct MyHarnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyHarnessWidget()
    }
}

#Preview(as: .systemSmall) {
    MyHarnessWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
        dateKey: WidgetTodaySnapshot.todayDateKey(),
        updatedAt: Date(),
        items: [
            WidgetItemSnapshot(
                id: UUID(),
                title: "睡眠メモ",
                sortOrder: 0,
                isCompleted: true
            ),
            WidgetItemSnapshot(
                id: UUID(),
                title: "机を戻す",
                sortOrder: 1,
                isCompleted: false
            )
        ]
    ))
}
