import Domain
import Foundation
import Support

/// Decides when to ask the feed, and what the answer means (E7-S3, ADR 0026).
///
/// Nothing is requested unless the user asked (`checkNow`) or turned on the
/// weekly check and a week has passed (`checkIfDue`), and never while a
/// dictation session is active.
public actor UpdateChecker: UpdateChecking {
    /// A weekly check is due this long after the last one.
    public static let interval: TimeInterval = 7 * 24 * 3600

    private let feed: any UpdateFeed
    private let currentVersion: SemanticVersion?
    private let preferences: any AppPreferences
    private let isSessionActive: @Sendable () async -> Bool
    private let diagnostics: any DiagnosticsRecording
    private let now: @Sendable () -> Date
    private var current: UpdateStatus = .unknown

    public init(
        feed: any UpdateFeed, currentVersion: String, preferences: any AppPreferences,
        isSessionActive: @escaping @Sendable () async -> Bool = { false },
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.feed = feed
        self.currentVersion = SemanticVersion(currentVersion)
        self.preferences = preferences
        self.isSessionActive = isSessionActive
        self.diagnostics = diagnostics
        self.now = now
    }

    public var status: UpdateStatus { current }

    @discardableResult
    public func checkNow() async -> UpdateStatus {
        await check()
    }

    public func checkIfDue() async {
        guard preferences.checksForUpdatesWeekly else { return }
        if let last = preferences.lastUpdateCheck, now().timeIntervalSince(last) < Self.interval { return }
        _ = await check()
    }

    private func check() async -> UpdateStatus {
        if case .checking = current { return current }
        guard !(await isSessionActive()) else {
            current = .deferred
            diagnostics.record(.lifecycle, "update.deferred")
            return current
        }
        guard let currentVersion else {
            return finish(.failed(.unknownVersion, checkedAt: now()))
        }
        current = .checking
        diagnostics.record(.lifecycle, "update.check-started")
        do throws(UpdateError) {
            let releases = try await feed.releases()
            return finish(Self.status(for: releases, running: currentVersion, at: now()))
        } catch {
            return finish(.failed(error, checkedAt: now()))
        }
    }

    private func finish(_ status: UpdateStatus) -> UpdateStatus {
        current = status
        preferences.lastUpdateCheck = status.checkedAt
        diagnostics.record(.lifecycle, "update.check-finished", ["result": .id(status.identifier)])
        return status
    }

    /// The newest release the user should hear about: higher than the running
    /// version, and a pre-release only if the running build is one.
    static func status(for releases: [ReleaseInfo], running: SemanticVersion, at date: Date) -> UpdateStatus {
        let candidates = releases.filter { running.isPrerelease || !$0.isPrerelease }
        guard let newest = candidates.max(by: { $0.version < $1.version }) else { return .noReleases(checkedAt: date) }
        return newest.version > running ? .available(newest, checkedAt: date) : .upToDate(checkedAt: date)
    }
}
