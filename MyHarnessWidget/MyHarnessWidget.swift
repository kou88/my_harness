import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetAppGroup {
    static let identifier = "group.com.kou888.myharness"
}

private enum WidgetStoreKey {
    static let snapshot = "my_harness.widget.snapshot"
    static let pendingUpdates = "my_harness.widget.pending_updates"
    static let displaySettings = "my_harness.widget.display_settings"
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

    static func empty(dateKey: String, updatedAt: Date) -> WidgetTodaySnapshot {
        WidgetTodaySnapshot(dateKey: dateKey, updatedAt: updatedAt, items: [])
    }

    static func visibleSnapshot(_ snapshot: WidgetTodaySnapshot, on date: Date) -> WidgetTodaySnapshot {
        let todayDateKey = Self.todayDateKey(date: date)
        guard snapshot.dateKey == todayDateKey else {
            return Self.empty(dateKey: todayDateKey, updatedAt: date)
        }
        return snapshot
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

private enum WidgetTextDirection: String, Codable, Hashable {
    case horizontal
    case vertical
}

private struct WidgetDisplaySettings: Codable, Hashable {
    var textDirection: WidgetTextDirection

    static var `default`: WidgetDisplaySettings {
        WidgetDisplaySettings(textDirection: .horizontal)
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

    static func readSnapshot(on date: Date) -> WidgetTodaySnapshot {
        guard
            let data = defaults.data(forKey: WidgetStoreKey.snapshot),
            let snapshot = try? JSONDecoder().decode(WidgetTodaySnapshot.self, from: data)
        else {
            return WidgetTodaySnapshot.empty(dateKey: WidgetTodaySnapshot.todayDateKey(date: date), updatedAt: date)
        }
        return WidgetTodaySnapshot.visibleSnapshot(snapshot, on: date)
    }

    static func writeSnapshot(_ snapshot: WidgetTodaySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetStoreKey.snapshot)
        }
    }

    static func readDisplaySettings() -> WidgetDisplaySettings {
        guard
            let data = defaults.data(forKey: WidgetStoreKey.displaySettings),
            let settings = try? JSONDecoder().decode(WidgetDisplaySettings.self, from: data)
        else {
            return .default
        }
        return settings
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

        var snapshot = WidgetSharedStore.readSnapshot(on: Date())
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

struct OpenMyHarnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Open my harness"
    static var description = IntentDescription("Open my harness.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

private struct HarnessTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTodaySnapshot
    let displaySettings: WidgetDisplaySettings

    init(
        date: Date,
        snapshot: WidgetTodaySnapshot,
        displaySettings: WidgetDisplaySettings = .default
    ) {
        self.date = date
        self.snapshot = snapshot
        self.displaySettings = displaySettings
    }
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
        completion(HarnessTimelineEntry(
            date: Date(),
            snapshot: WidgetSharedStore.readSnapshot(on: Date()),
            displaySettings: WidgetSharedStore.readDisplaySettings()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HarnessTimelineEntry>) -> Void) {
        let now = Date()
        let entry = HarnessTimelineEntry(
            date: now,
            snapshot: WidgetSharedStore.readSnapshot(on: now),
            displaySettings: WidgetSharedStore.readDisplaySettings()
        )
        let nextReload = nextTimelineReload(after: now)
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }

    private func nextTimelineReload(after date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let nextRegularReload = calendar.date(byAdding: .minute, value: 30, to: date) ?? date.addingTimeInterval(1_800)
        let nextDateChange = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) ?? nextRegularReload
        return min(nextRegularReload, nextDateChange)
    }
}

private struct MyHarnessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HarnessTimelineEntry

    private var visibleItems: [WidgetItemSnapshot] {
        switch family {
        case .systemSmall:
            Array(entry.snapshot.items.prefix(3))
        case .systemMedium:
            Array(entry.snapshot.items.prefix(entry.displaySettings.textDirection == .vertical ? 4 : 8))
        case .systemLarge:
            Array(entry.snapshot.items.prefix(entry.displaySettings.textDirection == .vertical ? 7 : 16))
        case .accessoryRectangular:
            Array(entry.snapshot.items.prefix(2))
        default:
            Array(entry.snapshot.items.prefix(8))
        }
    }

    private var checklistColumns: [[WidgetItemSnapshot]] {
        switch family {
        case .systemMedium, .systemLarge:
            let leadingCount = (visibleItems.count + 1) / 2
            return [
                Array(visibleItems.prefix(leadingCount)),
                Array(visibleItems.dropFirst(leadingCount))
            ].filter { !$0.isEmpty }
        default:
            return [visibleItems]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                WidgetHeaderView(textDirection: entry.displaySettings.textDirection)
            }

            if visibleItems.isEmpty {
                Text("項目なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if entry.displaySettings.textDirection == .vertical {
                    WidgetVerticalChecklistView(
                        items: visibleItems,
                        characterLimit: verticalCharacterLimit,
                        itemWidth: verticalItemWidth,
                        titleFont: verticalTitleFont
                    )
                } else {
                    WidgetChecklistColumnsView(columns: checklistColumns)
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
    }

    private var showsTitle: Bool {
        switch family {
        case .accessoryRectangular:
            return false
        default:
            return true
        }
    }

    private var verticalCharacterLimit: Int {
        switch family {
        case .systemLarge:
            return 7
        case .systemMedium:
            return 5
        default:
            return 5
        }
    }

    private var verticalItemWidth: CGFloat {
        switch family {
        case .systemLarge:
            return 34
        case .systemMedium:
            return 32
        default:
            return 28
        }
    }

    private var verticalTitleFont: Font {
        switch family {
        case .systemLarge:
            return .system(size: 12)
        default:
            return .system(size: 11)
        }
    }
}

private struct WidgetHeaderView: View {
    let textDirection: WidgetTextDirection

    var body: some View {
        HStack(spacing: 8) {
            if textDirection == .vertical {
                WidgetOpenButton()
            }

            Text("my harness")
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: textDirection == .vertical ? .trailing : .leading)

            if textDirection == .horizontal {
                WidgetOpenButton()
            }
        }
        .frame(height: 28, alignment: .center)
        .padding(.top, 2)
    }
}

private struct WidgetOpenButton: View {
    var body: some View {
        Button(intent: OpenMyHarnessIntent()) {
            Image(systemName: "arrow.up.forward.app")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("アプリを開く")
    }
}

private struct WidgetChecklistColumnsView: View {
    let columns: [[WidgetItemSnapshot]]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(column) { item in
                        WidgetChecklistRowView(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct WidgetChecklistRowView: View {
    let item: WidgetItemSnapshot

    var body: some View {
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

private struct WidgetVerticalChecklistView: View {
    let items: [WidgetItemSnapshot]
    let characterLimit: Int
    let itemWidth: CGFloat
    let titleFont: Font

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(Array(items.reversed())) { item in
                WidgetVerticalItemView(
                    item: item,
                    characterLimit: characterLimit,
                    itemWidth: itemWidth,
                    titleFont: titleFont
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct WidgetVerticalItemView: View {
    let item: WidgetItemSnapshot
    let characterLimit: Int
    let itemWidth: CGFloat
    let titleFont: Font

    var body: some View {
        Button(intent: ToggleHarnessItemIntent(itemId: item.id)) {
            VStack(spacing: 2) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isCompleted ? .green : .secondary)

                WidgetVerticalTitleView(
                    title: item.title,
                    isCompleted: item.isCompleted,
                    characterLimit: characterLimit,
                    font: titleFont
                )
            }
            .frame(width: itemWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

private struct WidgetVerticalTitleView: View {
    let title: String
    let isCompleted: Bool
    let characterLimit: Int
    let font: Font

    private var characters: [Character] {
        Array(title.filter { !$0.isWhitespace }.prefix(characterLimit))
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .strikethrough(isCompleted)
            }
        }
        .foregroundStyle(isCompleted ? .secondary : .primary)
    }
}

private struct MyHarnessButtonWidgetView: View {
    let entry: HarnessTimelineEntry

    private var targetItem: WidgetItemSnapshot? {
        entry.snapshot.items.first { !$0.isCompleted } ?? entry.snapshot.items.first
    }

    var body: some View {
        VStack {
            if let item = targetItem {
                Button(intent: ToggleHarnessItemIntent(itemId: item.id)) {
                    VStack(spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title)
                            .foregroundStyle(.black)

                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                Text("項目なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct MyHarnessOpenWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "checklist")
                .font(.title3.weight(.semibold))
                .widgetLabel("my harness")
                .containerBackground(.background, for: .widget)
        default:
            VStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.black)

                Text("my harness")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.background, for: .widget)
        }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct MyHarnessButtonWidget: Widget {
    let kind = "MyHarnessButtonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HarnessTimelineProvider()) { entry in
            MyHarnessButtonWidgetView(entry: entry)
        }
        .configurationDisplayName("my harness button")
        .description("今日の未完了項目を1つだけ表示して、タップで完了状態を切り替えます。")
        .supportedFamilies([.systemSmall])
    }
}

struct MyHarnessOpenWidget: Widget {
    let kind = "MyHarnessOpenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HarnessTimelineProvider()) { _ in
            MyHarnessOpenWidgetView()
        }
        .configurationDisplayName("my harness open")
        .description("my harnessを開くためのウィジェットです。")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct MyHarnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyHarnessWidget()
        MyHarnessButtonWidget()
        MyHarnessOpenWidget()
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

#Preview("Large", as: .systemLarge) {
    MyHarnessWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
        dateKey: WidgetTodaySnapshot.todayDateKey(),
        updatedAt: Date(),
        items: [
            WidgetItemSnapshot(id: UUID(), title: "朝 薬飲む", sortOrder: 0, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "風呂入る", sortOrder: 1, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "水 1L 飲む", sortOrder: 2, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "ランニングする", sortOrder: 3, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "夜 薬飲む", sortOrder: 4, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "洗濯", sortOrder: 5, isCompleted: false)
        ]
    ))
}

#Preview("Crowded", as: .systemMedium) {
    MyHarnessWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
        dateKey: WidgetTodaySnapshot.todayDateKey(),
        updatedAt: Date(),
        items: [
            WidgetItemSnapshot(id: UUID(), title: "朝 薬飲む", sortOrder: 0, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "お弁当持っていく", sortOrder: 1, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "風呂入る", sortOrder: 2, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "夜 薬飲む", sortOrder: 3, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "ランニングする", sortOrder: 4, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "お弁当作る", sortOrder: 5, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "水 1L 飲む", sortOrder: 6, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "洗濯", sortOrder: 7, isCompleted: false)
        ]
    ))
}

#Preview("Vertical", as: .systemMedium) {
    MyHarnessWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
        dateKey: WidgetTodaySnapshot.todayDateKey(),
        updatedAt: Date(),
        items: [
            WidgetItemSnapshot(id: UUID(), title: "朝 薬飲む", sortOrder: 0, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "風呂入る", sortOrder: 1, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "水 1L 飲む", sortOrder: 2, isCompleted: true),
            WidgetItemSnapshot(id: UUID(), title: "ランニングする", sortOrder: 3, isCompleted: false),
            WidgetItemSnapshot(id: UUID(), title: "夜 薬飲む", sortOrder: 4, isCompleted: true)
        ]
    ), displaySettings: WidgetDisplaySettings(textDirection: .vertical))
}

#Preview("Open", as: .systemSmall) {
    MyHarnessOpenWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot.empty)
}

#Preview("Open Circular", as: .accessoryCircular) {
    MyHarnessOpenWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot.empty)
}

#Preview("Button", as: .systemSmall) {
    MyHarnessButtonWidget()
} timeline: {
    HarnessTimelineEntry(date: Date(), snapshot: WidgetTodaySnapshot(
        dateKey: WidgetTodaySnapshot.todayDateKey(),
        updatedAt: Date(),
        items: [
            WidgetItemSnapshot(
                id: UUID(),
                title: "机を戻す",
                sortOrder: 0,
                isCompleted: false
            )
        ]
    ))
}
