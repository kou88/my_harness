import SwiftData
import SwiftUI

@main
@MainActor
struct MyHarnessApp: App {
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

