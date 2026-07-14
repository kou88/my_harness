@MainActor
struct AppUseCases {
    let loadToday: LoadTodayUseCase
    let createRoutineItem: CreateRoutineItemUseCase
    let updateRoutineItem: UpdateRoutineItemUseCase
    let updateOneShotPin: UpdateOneShotPinUseCase
    let deleteRoutineItem: DeleteRoutineItemUseCase
    let reorderRoutineItems: ReorderRoutineItemsUseCase
    let loadWeekdayTaskGroups: LoadWeekdayTaskGroupsUseCase
    let updateDayEntry: UpdateDayEntryUseCase
    let buildWeeklyExport: BuildWeeklyExportUseCase
    let copyText: CopyTextUseCase
    let publishWidgetSnapshot: PublishWidgetSnapshotUseCase
    let syncWidgetUpdates: SyncWidgetUpdatesUseCase
    let loadWidgetDisplaySettings: LoadWidgetDisplaySettingsUseCase
    let saveWidgetDisplaySettings: SaveWidgetDisplaySettingsUseCase
    let loadNotificationSchedule: LoadNotificationScheduleUseCase
    let saveNotificationSchedule: SaveNotificationScheduleUseCase
    let notificationPermission: NotificationPermissionUseCase
}
