import SwiftUI
import UI

@main
struct LemmeTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(actions: appDelegate.controller.menuActions)
        } label: {
            Image(systemName: "waveform")
                .accessibilityLabel(Text("LemmeType"))
        }
        .menuBarExtraStyle(.menu)
    }
}
