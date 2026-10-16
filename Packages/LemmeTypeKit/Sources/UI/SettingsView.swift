import SwiftUI

/// Root of the settings window. Later stories add Shortcut, Audio, and Diagnostics panes.
public struct SettingsView: View {
    private let general: GeneralSettingsModel
    private let permissions: PermissionsModel

    public init(general: GeneralSettingsModel, permissions: PermissionsModel) {
        self.general = general
        self.permissions = permissions
    }

    public var body: some View {
        TabView {
            Tab(String(localized: "General", bundle: .module), systemImage: "gearshape") {
                GeneralSettingsView(model: general)
            }
            Tab(String(localized: "Permissions", bundle: .module), systemImage: "lock.shield") {
                PermissionsSettingsView(model: permissions)
            }
        }
        .frame(width: 480, height: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            general.refresh()
            permissions.refresh()
        }
    }
}
