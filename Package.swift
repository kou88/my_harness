// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyHarnessNotificationDomain",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyHarnessNotificationDomain", targets: ["MyHarnessNotificationDomain"]),
        .library(name: "MyHarnessProductOpsDomain", targets: ["MyHarnessProductOpsDomain"]),
        .library(name: "MyHarnessBlogPostDomain", targets: ["MyHarnessBlogPostDomain"]),
        .library(name: "MyHarnessAIDomain", targets: ["MyHarnessAIDomain"]),
    ],
    targets: [
        .target(
            name: "MyHarnessNotificationDomain",
            path: "MyHarness/domain/model",
            exclude: [
                "ActionSuggestion.domain.swift",
                "ActionSuggestionWidgetSnapshot.domain.swift",
                "BlogPost.domain.swift",
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
                "BlogPost.domain.swift",
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
        .target(
            name: "MyHarnessBlogPostDomain",
            path: "MyHarness/domain/model",
            exclude: [
                "ActionSuggestion.domain.swift",
                "ActionSuggestionWidgetSnapshot.domain.swift",
                "DayEntry.domain.swift",
                "NotificationSchedule.domain.swift",
                "ProductOps.domain.swift",
                "PushNotificationPreferences.domain.swift",
                "RoutineItem.domain.swift",
                "WidgetDisplaySettings.domain.swift",
                "WidgetSnapshot.domain.swift"
            ],
            sources: ["BlogPost.domain.swift"]
        ),
        .target(
            name: "MyHarnessAIDomain",
            path: "MyHarness/domain/ai"
        ),
        .testTarget(
            name: "MyHarnessNotificationDomainTests",
            dependencies: ["MyHarnessNotificationDomain"]
        ),
        .testTarget(
            name: "MyHarnessProductOpsDomainTests",
            dependencies: ["MyHarnessProductOpsDomain"]
        ),
        .testTarget(
            name: "MyHarnessBlogPostDomainTests",
            dependencies: ["MyHarnessBlogPostDomain"]
        ),
        .testTarget(
            name: "MyHarnessAIDomainTests",
            dependencies: ["MyHarnessAIDomain"]
        ),
    ]
)
