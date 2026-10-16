import AppKit
import Support
import UI

/// Handles the app-level commands from the status menu and from other launches.
@MainActor
final class AppController {
    let settings: SettingsWindowController

    init(settings: SettingsWindowController) {
        self.settings = settings
    }

    var menuActions: MenuBarActions {
        MenuBarActions(
            openSettings: { [weak self] in self?.showSettings() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
    }

    func showSettings() {
        settings.show()
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Recording does not exist yet; E1-S6 makes quit stop an active recording first.
    func quit() {
        Log.lifecycle.info("Quit requested")
        NSApp.terminate(nil)
    }
}
