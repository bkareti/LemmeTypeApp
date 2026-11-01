import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Updates

final class ScriptedFeed: UpdateFeed {
    private struct State {
        var releases: [ReleaseInfo] = []
        var error: UpdateError?
        var calls = 0
    }

    private let state = Mutex(State())
    var calls: Int { state.withLock { $0.calls } }
    func set(_ releases: [ReleaseInfo], error: UpdateError? = nil) {
        state.withLock {
            $0.releases = releases
            $0.error = error
        }
    }
    func releases() async throws(UpdateError) -> [ReleaseInfo] {
        let snapshot = state.withLock { state -> State in
            state.calls += 1
            return state
        }
        if let error = snapshot.error { throw error }
        return snapshot.releases
    }
}

/// E7-S3: when the check runs, and what it concludes.
struct UpdateCheckerTests {
    final class Flag: Sendable {
        private let value = Mutex(false)
        var isOn: Bool { value.withLock { $0 } }
        func set(_ newValue: Bool) { value.withLock { $0 = newValue } }
    }

    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    static func release(_ version: String, pre: Bool = false) -> ReleaseInfo {
        ReleaseInfo(
            version: SemanticVersion(version) ?? SemanticVersion(major: 0, minor: 0, patch: 0),
            pageURL: URL(string: "https://github.com/bkareti/LemmeTypeApp/releases/tag/v\(version)")
                ?? URL(fileURLWithPath: "/"),
            isPrerelease: pre)
    }

    struct Setup {
        let checker: UpdateChecker
        let feed: ScriptedFeed
        let preferences: FakePreferences
        let session: Flag
        let clock: Clock
        let diagnostics: RecordingDiagnostics
    }

    static func make(running: String = "0.1.0", weekly: Bool = false) -> Setup {
        let feed = ScriptedFeed()
        let preferences = FakePreferences()
        preferences.checksForUpdatesWeekly = weekly
        let session = Flag()
        let clock = Clock()
        let diagnostics = RecordingDiagnostics()
        let checker = UpdateChecker(
            feed: feed, currentVersion: running, preferences: preferences, isSessionActive: { session.isOn },
            diagnostics: diagnostics, now: { clock.now })
        return Setup(
            checker: checker, feed: feed, preferences: preferences, session: session, clock: clock,
            diagnostics: diagnostics)
    }

    // MARK: When it runs

    @Test func nothingIsRequestedUntilTheUserAsks() async {
        let setup = Self.make()
        await setup.checker.checkIfDue()  // weekly is off
        #expect(setup.feed.calls == 0)
        #expect(await setup.checker.status == .unknown)
    }

    @Test func aClickMakesExactlyOneRequest() async {
        let setup = Self.make()
        setup.feed.set([Self.release("0.2.0")])
        let status = await setup.checker.checkNow()
        #expect(setup.feed.calls == 1)
        guard case .available(let release, _) = status else {
            Issue.record("expected an update, got \(status)"); return
        }
        #expect(release.version.description == "0.2.0")
    }

    @Test func theWeeklyCheckRunsOnlyWhenOnAndOverdue() async {
        let setup = Self.make(weekly: true)
        setup.feed.set([Self.release("0.1.0")])

        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 1, "never checked: due")
        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 1, "just checked: not due")

        setup.clock.advance(UpdateChecker.interval - 60)
        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 1, "a minute early: not due")

        setup.clock.advance(120)
        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 2, "a week has passed: due")
        #expect(setup.preferences.lastUpdateCheck == setup.clock.now)
    }

    @Test func turningTheWeeklyCheckOffStopsIt() async {
        let setup = Self.make(weekly: true)
        setup.preferences.checksForUpdatesWeekly = false
        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 0)
    }

    @Test func noRequestIsMadeWhileASessionIsActive() async {
        let setup = Self.make(weekly: true)
        setup.session.set(true)
        #expect(await setup.checker.checkNow() == .deferred)
        await setup.checker.checkIfDue()
        #expect(setup.feed.calls == 0)

        setup.session.set(false)
        setup.feed.set([])
        _ = await setup.checker.checkNow()
        #expect(setup.feed.calls == 1)
    }

    // MARK: What it concludes

    @Test func aNewerReleaseIsAvailableAndTheSameOrOlderIsUpToDate() async {
        let setup = Self.make(running: "0.2.0")
        setup.feed.set([Self.release("0.1.0"), Self.release("0.2.0")])
        guard case .upToDate = await setup.checker.checkNow() else { Issue.record("expected up to date"); return }
        setup.feed.set([Self.release("0.1.0"), Self.release("0.3.1"), Self.release("0.3.0")])
        guard case .available(let release, _) = await setup.checker.checkNow() else {
            Issue.record("expected an update"); return
        }
        #expect(release.version.description == "0.3.1", "the newest wins")
    }

    @Test func preReleasesAreIgnoredUnlessTheRunningBuildIsOne() async {
        let beta = Self.release("0.3.0-beta.1", pre: true)
        let stable = await Self.setupAndCheck(running: "0.2.0", releases: [beta, Self.release("0.2.0")])
        guard case .upToDate = stable else { Issue.record("a stable build ignores betas"); return }
        let onBeta = await Self.setupAndCheck(running: "0.3.0-beta.0", releases: [beta, Self.release("0.2.0")])
        guard case .available(let release, _) = onBeta else { Issue.record("a beta build is offered betas"); return }
        #expect(release.version.description == "0.3.0-beta.1")
    }

    /// Withdrawing a release (marking it a pre-release) stops stable users being offered it (docs/release/rollback.md).
    @Test func aWithdrawnReleaseIsNotOffered() async {
        let withdrawn = Self.release("0.3.0", pre: true)
        let status = await Self.setupAndCheck(running: "0.1.0", releases: [withdrawn, Self.release("0.2.0")])
        guard case .available(let release, _) = status else { Issue.record("expected the older good release"); return }
        #expect(release.version.description == "0.2.0")
    }

    @Test func aDowngradeIsNeverOffered() async {
        let status = await Self.setupAndCheck(running: "1.0.0", releases: [Self.release("0.9.0")])
        guard case .upToDate = status else { Issue.record("expected up to date, got \(status)"); return }
    }

    @Test func noReleasesPublishedIsNotAnError() async {
        let status = await Self.setupAndCheck(running: "0.1.0", releases: [])
        guard case .noReleases = status else { Issue.record("expected noReleases, got \(status)"); return }
    }

    static func setupAndCheck(running: String, releases: [ReleaseInfo]) async -> UpdateStatus {
        let setup = make(running: running)
        setup.feed.set(releases)
        return await setup.checker.checkNow()
    }

    // MARK: Failure

    @Test(arguments: [UpdateError.offline, .rateLimited, .badResponse, .untrustedLink])
    func failuresAreReportedByIdentifierAndRemembered(error: UpdateError) async {
        let setup = Self.make()
        setup.feed.set([], error: error)
        let status = await setup.checker.checkNow()
        guard case .failed(let failure, let date) = status else { Issue.record("expected a failure"); return }
        #expect(failure == error)
        #expect(date == setup.clock.now)
        #expect(setup.preferences.lastUpdateCheck == setup.clock.now, "a failed weekly check waits a week too")
        #expect(setup.diagnostics.events.contains { $0.name == "update.check-finished" })
    }

    @Test func anUnreadableOwnVersionFailsWithoutARequest() async {
        let setup = Self.make(running: "unknown")
        let status = await setup.checker.checkNow()
        guard case .failed(.unknownVersion, _) = status else { Issue.record("expected unknownVersion"); return }
        #expect(setup.feed.calls == 0)
    }

    @Test func diagnosticsCarryIdentifiersOnly() async {
        let setup = Self.make()
        setup.feed.set([Self.release("0.2.0")])
        _ = await setup.checker.checkNow()
        let text = String(describing: setup.diagnostics.events)
        #expect(text.contains("available"))
        #expect(!text.contains("github.com"), "no URL in diagnostics")
        #expect(setup.diagnostics.events.allSatisfy { $0.category == .lifecycle })
    }
}
