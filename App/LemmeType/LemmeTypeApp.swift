import SwiftUI
import UI

@main
struct LemmeTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(
                actions: appDelegate.controller.menuActions,
                permissions: appDelegate.controller.permissions,
                shortcut: appDelegate.controller.shortcut,
                recorder: appDelegate.controller.recorder,
                dictation: appDelegate.controller.dictation,
                context: appDelegate.controller.context
            )
        } label: {
            Image(systemName: "waveform")
                .accessibilityLabel(Text("LemmeType"))
        }
        .menuBarExtraStyle(.menu)
    }
}
