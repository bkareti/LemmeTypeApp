import SwiftUI

/// Actions the status menu can trigger; supplied by the app's coordinator.
public struct MenuBarActions {
    public var finishSetup: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var showAbout: @MainActor () -> Void
    public var quit: @MainActor () -> Void

    public init(
        finishSetup: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAbout: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.finishSetup = finishSetup
        self.openSettings = openSettings
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// Contents of the menu-bar item's menu.
public struct MenuBarMenu: View {
    private let actions: MenuBarActions
    private let permissions: PermissionsModel

    public init(actions: MenuBarActions, permissions: PermissionsModel) {
        self.actions = actions
        self.permissions = permissions
    }

    public var body: some View {
        if !permissions.allGranted {
            Button(String(localized: "Finish Setup…", bundle: .module)) { actions.finishSetup() }
            Divider()
        }
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
