import AppIntents
import SwiftUI
import UI

/// The iPhone and iPad app. The only scene is the Quick Dictation window; all
/// services are built by `IOSComposition`.
@main
struct LemmeTypeiOSApp: App {
    private let composition: IOSComposition

    init() {
        let composition = IOSComposition.make(arguments: ProcessInfo.processInfo.arguments)
        AppDependencyManager.shared.add(dependency: composition.launchRequests)
        self.composition = composition
    }

    var body: some Scene {
        WindowGroup {
            composition.rootView()
                .task { await composition.start() }
        }
    }
}
