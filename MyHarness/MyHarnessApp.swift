import SwiftData
import SwiftUI
import UIKit

@main
@MainActor
struct MyHarnessApp: App {
    @UIApplicationDelegateAdaptor(MyHarnessAppDelegate.self) private var appDelegate
    @State private var dependencies: AppDependencies

    init() {
        let dependencies = try! AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
