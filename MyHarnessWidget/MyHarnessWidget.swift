import AppIntents
import SwiftData
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

private enum WidgetScheduleKind: String {
    case routine
    case oneShot

    var displayPriority: Int {
        switch self {
        case .oneShot:
            return 0
        case .routine:
            return 1
        }
    }

    static func displayPriority(rawValue: String) -> Int {
        guard let kind = WidgetScheduleKind(rawValue: rawValue) else {
            return 2
        }
        return kind.displayPriority
    }
}

private enum WidgetRoutineWeekday: Int, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    static var everyDay: Set<WidgetRoutineWeekday> {
        Set(allCases)
    }

    static func set(fromStorageValue value: String?) -> Set<WidgetRoutineWeekday> {
        let days = value?
            .split(separator: ",")
            .compactMap { Int($0).flatMap(WidgetRoutineWeekday.init(rawValue:)) } ?? []
        return days.isEmpty ? everyDay : Set(days)
    }
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

@Model
final class RoutineItemModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRawValue: String
    var scheduleKindRawValue: String = WidgetScheduleKind.routine.rawValue
    var sortOrder: Int
    var repeatWeekdaysRawValue: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        typeRawValue: String,
        scheduleKindRawValue: String,
        sortOrder: Int,
        repeatWeekdaysRawValue: String?,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.typeRawValue = typeRawValue
        self.scheduleKindRawValue = scheduleKindRawValue
        self.sortOrder = sortOrder
        self.repeatWeekdaysRawValue = repeatWeekdaysRawValue
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DayEntryModel {
    @Attribute(.unique) var id: UUID
    var dateKey: String
    var itemId: UUID
    var isCompleted: Bool
    var logText: String
    var completedAt: Date?
    var updatedAt: Date

    init(
        id: UUID,
        dateKey: String,
        itemId: UUID,
        isCompleted: Bool,
        logText: String,
        completedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.dateKey = dateKey
        self.itemId = itemId
        self.isCompleted = isCompleted
        self.logText = logText
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }
}

@Model
final class HarnessSettingsModel {
    @Attribute(.unique) var key: String
    var notificationHour: Int
    var notificationMinute: Int

    init(key: String, notificationHour: Int, notificationMinute: Int) {
        self.key = key
        self.notificationHour = notificationHour
        self.notificationMinute = notificationMinute
    }
}

private enum WidgetSwiftDataStore {
    static func readTodaySnapshot(on date: Date) -> WidgetTodaySnapshot? {
        guard
            let storeURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.identifier)?
                .appendingPathComponent("Library/Application Support/default.store"),
            FileManager.default.fileExists(atPath: storeURL.path)
        else {
            return nil
        }

        do {
            let schema = Schema([
                RoutineItemModel.self,
                DayEntryModel.self,
                HarnessSettingsModel.self
            ])
            let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            return try todaySnapshot(on: date, context: context)
        } catch {
            return nil
        }
    }

    private static func todaySnapshot(on date: Date, context: ModelContext) throws -> WidgetTodaySnapshot {
        let dateKey = WidgetTodaySnapshot.todayDateKey(date: date)
        let activeItems = try context.fetch(FetchDescriptor<RoutineItemModel>(
            predicate: #Predicate { item in
                item.isArchived == false
            },
            sortBy: [
                SortDescriptor(\RoutineItemModel.sortOrder, order: .forward),
                SortDescriptor(\RoutineItemModel.createdAt, order: .forward)
            ]
        )).sorted { first, second in
            let firstPriority = WidgetScheduleKind.displayPriority(rawValue: first.scheduleKindRawValue)
            let secondPriority = WidgetScheduleKind.displayPriority(rawValue: second.scheduleKindRawValue)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }
            if first.sortOrder != second.sortOrder {
                return first.sortOrder < second.sortOrder
            }
            return first.createdAt < second.createdAt
        }
        let entries = try context.fetch(FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { entry in
                entry.dateKey == dateKey
            }
        ))
        let completedEntries = try context.fetch(FetchDescriptor<DayEntryModel>(
            predicate: #Predicate { entry in
                entry.isCompleted == true
            },
            sortBy: [
                SortDescriptor(\DayEntryModel.dateKey, order: .forward),
                SortDescriptor(\DayEntryModel.updatedAt, order: .forward)
            ]
        ))
        let entryByItemId = Dictionary(uniqueKeysWithValues: entries.map { ($0.itemId, $0) })
        let completedDateKeyByItemId = earliestCompletedDateKeys(from: completedEntries)
        let calendar = Calendar.autoupdatingCurrent
        let todayWeekday = calendar.component(.weekday, from: date)

        let snapshots = activeItems.compactMap { item -> WidgetItemSnapshot? in
            guard
                let scheduleKind = WidgetScheduleKind(rawValue: item.scheduleKindRawValue),
                isVisible(
                    item: item,
                    scheduleKind: scheduleKind,
                    dateKey: dateKey,
                    todayWeekday: todayWeekday,
                    completedDateKey: completedDateKeyByItemId[item.id]
                )
            else {
                return nil
            }

            return WidgetItemSnapshot(
                id: item.id,
                title: item.title,
                sortOrder: item.sortOrder,
                isCompleted: entryByItemId[item.id]?.isCompleted == true
            )
        }

        return WidgetTodaySnapshot(dateKey: dateKey, updatedAt: Date(), items: snapshots)
    }

    private static func earliestCompletedDateKeys(from entries: [DayEntryModel]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for entry in entries {
            if let existingDateKey = result[entry.itemId] {
                result[entry.itemId] = min(existingDateKey, entry.dateKey)
            } else {
                result[entry.itemId] = entry.dateKey
            }
        }
        return result
    }

    private static func isVisible(
        item: RoutineItemModel,
        scheduleKind: WidgetScheduleKind,
        dateKey: String,
        todayWeekday: Int,
        completedDateKey: String?
    ) -> Bool {
        switch scheduleKind {
        case .routine:
            let weekdays = WidgetRoutineWeekday.set(fromStorageValue: item.repeatWeekdaysRawValue)
            guard let weekday = WidgetRoutineWeekday(rawValue: todayWeekday) else {
                return true
            }
            return weekdays.contains(weekday)
        case .oneShot:
            let createdDateKey = WidgetTodaySnapshot.todayDateKey(date: item.createdAt)
            guard dateKey >= createdDateKey else { return false }
            guard let completedDateKey else { return true }
            return dateKey <= completedDateKey
        }
    }
}

private enum WidgetSharedStore {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetAppGroup.identifier) ?? .standard
    }

    static func readSnapshot(on date: Date) -> WidgetTodaySnapshot {
        if let snapshot = WidgetSwiftDataStore.readTodaySnapshot(on: date) {
            return applyPendingUpdates(to: snapshot)
        }

        guard
            let data = defaults.data(forKey: WidgetStoreKey.snapshot),
            let snapshot = try? JSONDecoder().decode(WidgetTodaySnapshot.self, from: data)
        else {
            return WidgetTodaySnapshot.empty(dateKey: WidgetTodaySnapshot.todayDateKey(date: date), updatedAt: date)
        }
        return applyPendingUpdates(to: WidgetTodaySnapshot.visibleSnapshot(snapshot, on: date))
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
        updates = readPendingUpdates()
        updates.append(update)
        if let data = try? JSONEncoder().encode(updates) {
            defaults.set(data, forKey: WidgetStoreKey.pendingUpdates)
        }
    }

    private static func readPendingUpdates() -> [WidgetPendingEntryUpdate] {
        guard
            let data = defaults.data(forKey: WidgetStoreKey.pendingUpdates),
            let decoded = try? JSONDecoder().decode([WidgetPendingEntryUpdate].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func applyPendingUpdates(to snapshot: WidgetTodaySnapshot) -> WidgetTodaySnapshot {
        let updates = readPendingUpdates()
            .filter { $0.dateKey == snapshot.dateKey }
            .sorted { $0.updatedAt < $1.updatedAt }
        guard !updates.isEmpty else { return snapshot }

        var snapshot = snapshot
        for update in updates {
            guard let index = snapshot.items.firstIndex(where: { $0.id == update.itemId }) else {
                continue
            }
            snapshot.items[index].isCompleted = update.isCompleted
            snapshot.updatedAt = max(snapshot.updatedAt, update.updatedAt)
        }
        return snapshot
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
        Button(intent: OpenMyHarnessIntent()) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel("my harnessを開く")
        .containerBackground(.background, for: .widget)
    }

    private var content: some View {
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
        Text("my harness")
            .font(.headline)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: textDirection == .vertical ? .trailing : .leading)
        .frame(height: 28, alignment: .center)
        .padding(.top, 2)
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
        .description("今日のチェック項目を表示して、タップでmy harnessを開きます。")
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
