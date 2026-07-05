import Foundation
import SwiftData

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let useCases: AppUseCases

    static func live() throws -> AppDependencies {
        try make(isStoredInMemoryOnly: false, seedPreviewData: false)
    }

    static func preview() throws -> AppDependencies {
        try make(isStoredInMemoryOnly: true, seedPreviewData: true)
    }

    private static func make(
        isStoredInMemoryOnly: Bool,
        seedPreviewData: Bool
    ) throws -> AppDependencies {
        let schema = Schema([
            RoutineItemModel.self,
            DayEntryModel.self,
            HarnessSettingsModel.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let calendar = SystemCalendar()
        let itemRepository = SwiftDataRoutineItemRepository(context: container.mainContext)
        let entryRepository = SwiftDataDayEntryRepository(context: container.mainContext)
        let settingsRepository = SwiftDataSettingsRepository(context: container.mainContext)
        let widgetRepository = SharedWidgetSnapshotRepository()
        let notificationScheduler = LocalNotificationScheduler()
        let clipboard = PasteboardClipboardWriter()
        let todayReadStore = SwiftDataTodayReadStore(
            itemRepository: itemRepository,
            dayEntryRepository: entryRepository,
            calendar: calendar
        )
        let weekReadStore = SwiftDataWeekReadStore(
            itemRepository: itemRepository,
            dayEntryRepository: entryRepository,
            calendar: calendar
        )

        let useCases = AppUseCases(
            loadToday: LoadTodayUseCase(readStore: todayReadStore),
            createRoutineItem: CreateRoutineItemUseCase(repository: itemRepository),
            updateRoutineItem: UpdateRoutineItemUseCase(repository: itemRepository),
            deleteRoutineItem: DeleteRoutineItemUseCase(repository: itemRepository),
            reorderRoutineItems: ReorderRoutineItemsUseCase(repository: itemRepository),
            loadWeekdayTaskGroups: LoadWeekdayTaskGroupsUseCase(repository: itemRepository),
            updateDayEntry: UpdateDayEntryUseCase(repository: entryRepository, calendar: calendar),
            buildWeeklyExport: BuildWeeklyExportUseCase(readStore: weekReadStore, calendar: calendar),
            copyText: CopyTextUseCase(clipboard: clipboard),
            publishWidgetSnapshot: PublishWidgetSnapshotUseCase(repository: widgetRepository, calendar: calendar),
            syncWidgetUpdates: SyncWidgetUpdatesUseCase(
                widgetRepository: widgetRepository,
                entryRepository: entryRepository
            ),
            loadNotificationSchedule: LoadNotificationScheduleUseCase(repository: settingsRepository),
            saveNotificationSchedule: SaveNotificationScheduleUseCase(
                repository: settingsRepository,
                scheduler: notificationScheduler
            ),
            notificationPermission: NotificationPermissionUseCase(scheduler: notificationScheduler)
        )

        let dependencies = AppDependencies(modelContainer: container, useCases: useCases)

        if seedPreviewData {
            try seedPreviewDataIfNeeded(context: container.mainContext, calendar: calendar)
        }

        return dependencies
    }

    private static func seedPreviewDataIfNeeded(
        context: ModelContext,
        calendar: CalendarProviding
    ) throws {
        let items = [
            RoutineItem(title: "明日の服を出す", sortOrder: 0),
            RoutineItem(
                title: "ごみ出し準備",
                sortOrder: 1,
                repeatWeekdays: [.monday, .thursday]
            ),
            RoutineItem(title: "机を戻す", sortOrder: 2)
        ]

        for item in items {
            context.insert(RoutineItemModel(item: item))
        }

        let today = calendar.dateKey(for: Date())
        context.insert(DayEntryModel(entry: DayEntry(
            dateKey: today,
            itemId: items[0].id,
            isCompleted: true,
            completedAt: Date()
        )))
        context.insert(DayEntryModel(entry: DayEntry(
            dateKey: today,
            itemId: items[1].id,
            isCompleted: true,
            completedAt: Date()
        )))
        try context.save()
    }
}
