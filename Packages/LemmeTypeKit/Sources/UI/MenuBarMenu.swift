import SwiftUI

/// Actions the status menu can trigger; supplied by the app's coordinator.
public struct MenuBarActions {
    public var finishSetup: @MainActor () -> Void
    public var chooseShortcut: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var showAbout: @MainActor () -> Void
    public var quit: @MainActor () -> Void

    public init(
        finishSetup: @escaping @MainActor () -> Void,
        chooseShortcut: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAbout: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.finishSetup = finishSetup
        self.chooseShortcut = chooseShortcut
        self.openSettings = openSettings
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// Contents of the menu-bar item's menu.
public struct MenuBarMenu: View {
    private let actions: MenuBarActions
    private let permissions: PermissionsModel
    private let shortcut: ShortcutSettingsModel

    public init(actions: MenuBarActions, permissions: PermissionsModel, shortcut: ShortcutSettingsModel) {
        self.actions = actions
        self.permissions = permissions
        self.shortcut = shortcut
    }

    public var body: some View {
        if !permissions.allGranted {
            Button(String(localized: "Finish Setup…", bundle: .module)) { actions.finishSetup() }
        }
        if shortcut.isShortcutUnavailable {
            Button(String(localized: "Shortcut Unavailable — Choose Another…", bundle: .module)) {
                actions.chooseShortcut()
            }
        } else {
            Text(String(localized: "Dictate: \(shortcut.shortcut.displayString)", bundle: .module))
        }
        Divider()
        // Enabled once recording exists (E1-S6).
        Button(String(localized: "Start Test Recording", bundle: .module)) {}
            .disabled(true)
        Divider()
        Button(String(localized: "Settings…", bundle: .module)) { actions.openSettings() }
            .keyboardShortcut(",")
        Button(String(localized: "About LemmeType", bundle: .module)) { actions.showAbout() }
        Divider()
        Button(String(localized: "Quit LemmeType", bundle: .module)) { actions.quit() }
            .keyboardShortcut("q")
    }
}
