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
                .task {
                    #if DEBUG
                        // `scripts/run-ios-evaluation.sh`: evaluate the corpus on this device, then quit.
                        if let request = IOSComposition.EvaluationRequest(arguments: ProcessInfo.processInfo.arguments)
                        {
                            exit(await IOSComposition.runEvaluation(request))
                        }
                    #endif
                    await composition.start()
                }
        }
    }
}
