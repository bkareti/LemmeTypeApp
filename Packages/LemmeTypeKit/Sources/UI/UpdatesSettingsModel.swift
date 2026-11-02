import Domain
import Foundation
import Observation

/// Settings › General › Updates (E7-S3): the user starts a check, sees the
/// result, and may turn on the weekly check. The app only ever opens the
/// release page; it downloads and installs nothing (ADR 0026).
@MainActor
@Observable
public final class UpdatesSettingsModel {
    public private(set) var status: UpdateStatus = .unknown
    public private(set) var checksWeekly: Bool

    private let checker: any UpdateChecking
    private let preferences: any AppPreferences
    private let openPage: @MainActor (URL) -> Void
    public let appVersion: String

    public init(
        checker: any UpdateChecking, preferences: any AppPreferences, appVersion: String,
        openPage: @escaping @MainActor (URL) -> Void
    ) {
        self.checker = checker
        self.preferences = preferences
        self.appVersion = appVersion
        self.openPage = openPage
        self.checksWeekly = preferences.checksForUpdatesWeekly
    }

    public var isChecking: Bool { status == .checking }

    /// The release to offer, if the last check found one.
    public var availableRelease: ReleaseInfo? {
        if case .available(let release, _) = status { return release }
        return nil
    }

    /// Asks once. The user pressed the button, so this is the only trigger.
    public func check() async {
        guard !isChecking else { return }
        status = .checking
        status = await checker.checkNow()
    }

    public func setChecksWeekly(_ enabled: Bool) {
        preferences.checksForUpdatesWeekly = enabled
        checksWeekly = enabled
    }

    public func openReleasePage() {
        if let release = availableRelease { openPage(release.pageURL) }
    }

    /// Reads what the checker already knows (for example after a weekly check).
    public func refresh() async {
        let current = await checker.status
        if current != .unknown { status = current }
    }

    // MARK: Text

    public var summary: String {
        switch status {
        case .unknown:
            String(localized: "Not checked yet.", bundle: .module)
        case .checking:
            String(localized: "Checking…", bundle: .module)
        case .upToDate:
            String(localized: "LemmeType \(appVersion) is up to date.", bundle: .module)
        case .available(let release, _):
            String(localized: "LemmeType \(release.version.description) is available.", bundle: .module)
        case .noReleases:
            String(localized: "No newer version has been published.", bundle: .module)
        case .deferred:
            String(localized: "A dictation is in progress. Check again when it finishes.", bundle: .module)
        case .failed(let error, _):
            Self.message(for: error)
        }
    }

    static func message(for error: UpdateError) -> String {
        switch error {
        case .offline:
            String(localized: "Couldn’t reach GitHub. Check your connection and try again.", bundle: .module)
        case .rateLimited:
            String(localized: "GitHub is limiting requests right now. Try again later.", bundle: .module)
        case .badResponse, .tooLarge, .untrustedLink:
            String(localized: "GitHub’s answer wasn’t what LemmeType expected. Try again later.", bundle: .module)
        case .unknownVersion:
            String(localized: "This build has no readable version number, so it can’t compare.", bundle: .module)
        }
    }
}
