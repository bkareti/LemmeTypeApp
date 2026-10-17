import SwiftUI

/// Root of the settings window.
public struct SettingsView: View {
    private let general: GeneralSettingsModel
    private let dictation: DictationSettingsModel
    private let shortcut: ShortcutSettingsModel
    private let context: ContextSettingsModel
    private let audio: AudioSettingsModel
    private let permissions: PermissionsModel
    private let diagnostics: DiagnosticsModel
    @Bindable private var navigation: SettingsNavigation

    public init(
        general: GeneralSettingsModel,
        dictation: DictationSettingsModel,
        shortcut: ShortcutSettingsModel,
        context: ContextSettingsModel,
        audio: AudioSettingsModel,
        permissions: PermissionsModel,
        diagnostics: DiagnosticsModel,
        navigation: SettingsNavigation
    ) {
        self.general = general
        self.dictation = dictation
        self.shortcut = shortcut
        self.context = context
        self.audio = audio
        self.permissions = permissions
        self.diagnostics = diagnostics
        self.navigation = navigation
    }

    public var body: some View {
        TabView(selection: $navigation.selectedPane) {
            Tab(String(localized: "General", bundle: .module), systemImage: "gearshape", value: .general) {
                GeneralSettingsView(model: general)
            }
            Tab(String(localized: "Dictation", bundle: .module), systemImage: "waveform", value: .dictation) {
                DictationSettingsView(model: dictation)
            }
            Tab(String(localized: "Shortcut", bundle: .module), systemImage: "keyboard", value: .shortcut) {
                ShortcutSettingsView(model: shortcut)
            }
            Tab(String(localized: "Context", bundle: .module), systemImage: "text.cursor", value: .context) {
                ContextSettingsView(model: context, shortcut: shortcut)
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
            Tab(
                String(localized: "Diagnostics", bundle: .module),
                systemImage: "stethoscope",
                value: SettingsNavigation.Pane.diagnostics
            ) {
                DiagnosticsSettingsView(model: diagnostics)
            }
        }
        .frame(width: 600, height: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            general.refresh()
            permissions.refresh()
            dictation.refreshInBackground()
        }
    }
}
