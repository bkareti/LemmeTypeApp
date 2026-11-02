import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import UI

final class StubUpdateChecker: UpdateChecking {
    private struct State {
        var next: UpdateStatus
        var checks = 0
    }
    private let state: Mutex<State>
    init(_ next: UpdateStatus = .unknown) { state = Mutex(State(next: next)) }
    var next: UpdateStatus {
        get { state.withLock { $0.next } }
        set { state.withLock { $0.next = newValue } }
    }
    var checks: Int { state.withLock { $0.checks } }
    var status: UpdateStatus { next }
    func checkNow() async -> UpdateStatus {
        state.withLock {
            $0.checks += 1
            return $0.next
        }
    }
    func checkIfDue() async {}
}

/// E7-S3: the Updates section of General settings.
@MainActor
struct UpdatesSettingsModelTests {
    struct Setup {
        let model: UpdatesSettingsModel
        let checker: StubUpdateChecker
        let preferences: FakePreferences
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(_ status: UpdateStatus, opened: @escaping @MainActor (URL) -> Void = { _ in }) -> Setup {
        let checker = StubUpdateChecker(status)
        let preferences = FakePreferences()
        let model = UpdatesSettingsModel(
            checker: checker, preferences: preferences, appVersion: "0.1.0", openPage: opened)
        return Setup(model: model, checker: checker, preferences: preferences)
    }

    @Test func nothingIsCheckedUntilTheUserAsks() {
        let setup = make(.upToDate(checkedAt: date))
        #expect(setup.checker.checks == 0)
        #expect(setup.model.status == .unknown)
        #expect(setup.model.checksWeekly == false)
        #expect(setup.preferences.checksForUpdatesWeekly == false)
        #expect(setup.model.summary == "Not checked yet.")
    }

    @Test func aClickChecksOnceAndShowsTheResult() async {
        let release = FakeUpdateFeed.release("0.2.0")
        let setup = make(.available(release, checkedAt: date))
        await setup.model.check()
        #expect(setup.checker.checks == 1)
        #expect(setup.model.availableRelease == release)
        #expect(setup.model.summary == "LemmeType 0.2.0 is available.")
    }

    @Test func upToDateSaysSo() async {
        let setup = make(.upToDate(checkedAt: date))
        await setup.model.check()
        #expect(setup.model.summary == "LemmeType 0.1.0 is up to date.")
        #expect(setup.model.availableRelease == nil)
    }

    @Test func theDownloadPageOpensOnlyWhenAReleaseIsAvailable() async {
        var opened: [URL] = []
        let release = FakeUpdateFeed.release("0.2.0")
        let setup = make(.available(release, checkedAt: date), opened: { opened.append($0) })
        setup.model.openReleasePage()
        #expect(opened.isEmpty, "nothing to open before a check")
        await setup.model.check()
        setup.model.openReleasePage()
        #expect(opened == [release.pageURL])
        setup.checker.next = .upToDate(checkedAt: date)
        await setup.model.check()
        setup.model.openReleasePage()
        #expect(opened.count == 1)
    }

    @Test(arguments: [
        (UpdateError.offline, "Couldn’t reach GitHub. Check your connection and try again."),
        (.rateLimited, "GitHub is limiting requests right now. Try again later."),
        (.badResponse, "GitHub’s answer wasn’t what LemmeType expected. Try again later."),
        (.untrustedLink, "GitHub’s answer wasn’t what LemmeType expected. Try again later."),
    ])
    func failuresAreShownInPlainWords(error: UpdateError, message: String) async {
        let setup = make(.failed(error, checkedAt: date))
        await setup.model.check()
        #expect(setup.model.summary == message)
        #expect(setup.model.availableRelease == nil)
    }

    @Test func noReleaseAndBusySessionsAreNotErrors() async {
        let none = make(.noReleases(checkedAt: date))
        await none.model.check()
        #expect(none.model.summary == "No newer version has been published.")
        let busy = make(.deferred)
        await busy.model.check()
        #expect(busy.model.summary.hasPrefix("A dictation is in progress"))
    }

    @Test func theWeeklyCheckIsAnExplicitSetting() {
        let setup = make(.unknown)
        setup.model.setChecksWeekly(true)
        #expect(setup.model.checksWeekly && setup.preferences.checksForUpdatesWeekly)
        setup.model.setChecksWeekly(false)
        #expect(!setup.model.checksWeekly && !setup.preferences.checksForUpdatesWeekly)
    }

    @Test func refreshShowsAResultTheWeeklyCheckFound() async {
        let release = FakeUpdateFeed.release("0.3.0")
        let setup = make(.available(release, checkedAt: date))
        await setup.model.refresh()
        #expect(setup.model.availableRelease == release)
    }

    @Test func aCheckInProgressIsNotStartedTwice() async {
        let setup = make(.checking)
        await setup.model.refresh()
        #expect(setup.model.isChecking)
        await setup.model.check()
        #expect(setup.checker.checks == 0)
    }
}
