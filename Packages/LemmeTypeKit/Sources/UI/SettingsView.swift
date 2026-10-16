import SwiftUI

/// Root of the settings window. E1-S7 adds the Diagnostics pane.
public struct SettingsView: View {
    private let general: GeneralSettingsModel
    private let shortcut: ShortcutSettingsModel
    private let audio: AudioSettingsModel
    private let permissions: PermissionsModel
    @Bindable private var navigation: SettingsNavigation

    public init(
        general: GeneralSettingsModel,
        shortcut: ShortcutSettingsModel,
        audio: AudioSettingsModel,
        permissions: PermissionsModel,
        navigation: SettingsNavigation
    ) {
        self.general = general
        self.shortcut = shortcut
        self.audio = audio
        self.permissions = permissions
        self.navigation = navigation
    }

    public var body: some View {
        TabView(selection: $navigation.selectedPane) {
            Tab(String(localized: "General", bundle: .module), systemImage: "gearshape", value: .general) {
                GeneralSettingsView(model: general)
            }
            Tab(String(localized: "Shortcut", bundle: .module), systemImage: "keyboard", value: .shortcut) {
                ShortcutSettingsView(model: shortcut)
            }
            Tab(String(localized: "Audio", bundle: .module), systemImage: "mic", value: .audio) {
                AudioSettingsView(model: audio)
            }
            Tab(
                String(localized: "Permissions", bundle: .module),
                systemImage: "lock.shield",
                value: SettingsNavigation.Pane.permissions
            ) {
                PermissionsSettingsView(model: permissions)
            }
        }
        .frame(width: 520, height: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            general.refresh()
            permissions.refresh()
        }
    }
}
