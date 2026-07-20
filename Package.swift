// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyHarnessNotificationDomain",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyHarnessNotificationDomain", targets: ["MyHarnessNotificationDomain"]),
        .library(name: "MyHarnessProductOpsDomain", targets: ["MyHarnessProductOpsDomain"]),
    ],
    targets: [
        .target(
            name: "MyHarnessNotificationDomain",
            path: "MyHarness/domain/model",
            exclude: [
                "ActionSuggestion.domain.swift",
                "ActionSuggestionWidgetSnapshot.domain.swift",
                "DayEntry.domain.swift",
                "NotificationSchedule.domain.swift",
                "ProductOps.domain.swift",
                "RoutineItem.domain.swift",
                "WidgetDisplaySettings.domain.swift",
                "WidgetSnapshot.domain.swift"
            ],
            sources: ["PushNotificationPreferences.domain.swift"]
        ),
        .target(
            name: "MyHarnessProductOpsDomain",
            path: "MyHarness/domain/model",
            exclude: [
                "ActionSuggestionWidgetSnapshot.domain.swift",
                "DayEntry.domain.swift",
                "NotificationSchedule.domain.swift",
                "PushNotificationPreferences.domain.swift",
                "RoutineItem.domain.swift",
                "WidgetDisplaySettings.domain.swift",
                "WidgetSnapshot.domain.swift",
            ],
            sources: [
                "ActionSuggestion.domain.swift",
                "ProductOps.domain.swift",
            ]
        ),
        .testTarget(
            name: "MyHarnessNotificationDomainTests",
            dependencies: ["MyHarnessNotificationDomain"]
        ),
        .testTarget(
            name: "MyHarnessProductOpsDomainTests",
            dependencies: ["MyHarnessProductOpsDomain"]
        ),
    ]
)
