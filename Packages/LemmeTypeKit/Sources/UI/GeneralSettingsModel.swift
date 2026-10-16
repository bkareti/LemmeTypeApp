import Domain
import Observation
import Support

/// Launch at Login state for the General settings pane. Always reflects what
/// macOS reports rather than a stored preference.
@MainActor
@Observable
public final class GeneralSettingsModel {
    public private(set) var loginItemStatus: LoginItemStatus
    public private(set) var errorMessage: String?
    public let buildInfo: BuildInfo

    public private(set) var playsFeedbackSounds: Bool

    private let loginItems: any LoginItemManaging
    private let preferences: any AppPreferences

    public init(loginItems: any LoginItemManaging, preferences: any AppPreferences, buildInfo: BuildInfo) {
        self.loginItems = loginItems
        self.preferences = preferences
        self.buildInfo = buildInfo
        self.loginItemStatus = loginItems.status()
        self.playsFeedbackSounds = preferences.playsFeedbackSounds
    }

    public func setPlaysFeedbackSounds(_ enabled: Bool) {
        preferences.playsFeedbackSounds = enabled
        playsFeedbackSounds = enabled
    }

    /// Toggle value. `requiresApproval` counts as on: the user asked for it and
    /// only needs to approve it in System Settings.
    public var launchAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    public var canChangeLaunchAtLogin: Bool {
        loginItemStatus != .unavailable
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(
                localized:
                    "macOS couldn’t update Launch at Login. Try again, or change it in System Settings › Login Items.",
                bundle: .module
            )
        }
        refresh()
    }

    public func openLoginItemsSettings() {
        loginItems.openSystemSettings()
    }

    public func refresh() {
        loginItemStatus = loginItems.status()
    }
}
