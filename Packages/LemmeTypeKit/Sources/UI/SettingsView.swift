import SwiftUI

/// Root of the settings window. Later stories add Shortcut, Audio, and Diagnostics panes.
public struct SettingsView: View {
    private let general: GeneralSettingsModel
    private let status: StatusViewModel

    public init(general: GeneralSettingsModel, status: StatusViewModel) {
        self.general = general
        self.status = status
    }

    public var body: some View {
        TabView {
            Tab(String(localized: "General", bundle: .module), systemImage: "gearshape") {
                GeneralSettingsView(model: general)
            }
            Tab(String(localized: "Permissions", bundle: .module), systemImage: "lock.shield") {
                StatusView(model: status)
            }
        }
        .frame(width: 460, height: 360)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            general.refresh()
        }
    }
}
