import Support
import SwiftUI
import UI

@main
struct LemmeTypeApp: App {
    @State private var statusModel: StatusViewModel

    init() {
        let composition = AppComposition.make(
            arguments: ProcessInfo.processInfo.arguments,
            infoDictionary: Bundle.main.infoDictionary
        )
        _statusModel = State(initialValue: composition.makeStatusViewModel())
        Log.lifecycle.info("Launched with \(composition.mode.rawValue, privacy: .public) services")
    }

    var body: some Scene {
        Window("LemmeType", id: "status") {
            StatusView(model: statusModel)
        }
        .windowResizability(.contentSize)
    }
}
