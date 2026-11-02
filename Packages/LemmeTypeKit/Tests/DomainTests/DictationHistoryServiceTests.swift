import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

/// E6-S3: what is recorded, what never is, and that "off" touches nothing.
struct DictationHistoryServiceTests {
    static let canary = "CANARY-HISTORY-4f7b"

    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    struct Setup {
        let service: DictationHistoryService
        let store: FakeDictationHistoryStore
        let preferences: FakePreferences
        let diagnostics: RecordingDiagnostics
        let clock: Clock
    }

    static func make(
        _ retention: HistoryRetention = .oneWeek, store: FakeDictationHistoryStore = FakeDictationHistoryStore()
    ) -> Setup {
        let preferences = FakePreferences()
        preferences.historyRetention = retention
        let diagnostics = RecordingDiagnostics()
        let clock = Clock()
        let service = DictationHistoryService(
            store: store, preferences: preferences, diagnostics: diagnostics, now: { clock.now })
        return Setup(service: service, store: store, preferences: preferences, diagnostics: diagnostics, clock: clock)
    }

    static func session(
        bundle: String? = "com.example.Editor", purpose: SessionPurpose = .dictation, language: String = "en-US"
    ) -> DictationSession {
        DictationSession(
            audio: RecordedAudio(
                fileURL: URL(fileURLWithPath: "/nonexistent/history.caf"), duration: 1, format: .speech),
            target: ActivationTarget(
                processIdentifier: 7, bundleIdentifier: bundle, applicationName: "Editor", focusedElement: nil),
            mode: .clean, purpose: purpose, language: language)
    }

    // MARK: Off

    @Test func withRetentionOffNothingIsReadOrWritten() async {
        let setup = Self.make(.off)

        await setup.service.record(Self.canary, for: Self.session(), delivery: .inserted)
        await setup.service.purgeExpired()

        #expect(setup.store.loadCount == 0)
        #expect(setup.store.saveCount == 0)
        #expect(setup.store.deleteCount == 0)
        #expect(setup.store.history.isEmpty)
    }

    // MARK: Recording

    @Test func oneAcceptedResultMakesOneEntryWithTheDocumentedFields() async throws {
        let setup = Self.make()

        await setup.service.record("  Send the report.  ", for: Self.session(language: "hi"), delivery: .copied)

        let entries = setup.store.history.entries
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.text == "Send the report.")
        #expect(entry.mode == "clean")
        #expect(entry.language == "hi")
        #expect(entry.delivery == .copied)
        #expect(entry.words == 3)
        #expect(entry.createdAt == setup.clock.now)
    }

    @Test func newestEntryComesFirst() async {
        let setup = Self.make()
        await setup.service.record("first", for: Self.session(), delivery: .inserted)
        setup.clock.advance(60)
        await setup.service.record("second", for: Self.session(), delivery: .inserted)
        #expect(await setup.service.snapshot().entries.map(\.text) == ["second", "first"])
    }

    @Test func entriesOlderThanTheRetentionAreRemovedWhenTheNextOneIsRecorded() async {
        let setup = Self.make(.oneDay)
        await setup.service.record("yesterday", for: Self.session(), delivery: .inserted)
        setup.clock.advance(2 * 86_400)
        await setup.service.record("today", for: Self.session(), delivery: .inserted)
        #expect(setup.store.history.entries.map(\.text) == ["today"])
    }

    @Test func purgeExpiredRemovesAgedEntries() async {
        let setup = Self.make(.oneDay)
        await setup.service.record("old", for: Self.session(), delivery: .inserted)
        setup.clock.advance(3 * 86_400)
        await setup.service.purgeExpired()
        #expect(setup.store.history.isEmpty)
        #expect(await setup.service.snapshot().entries.isEmpty)
    }

    // MARK: Never recorded

    @Test func voiceEditingIsNeverRecorded() async {
        let setup = Self.make()
        await setup.service.record("edited", for: Self.session(purpose: .editing), delivery: .inserted)
        #expect(setup.store.saveCount == 0)
    }

    @Test func excludedAndSensitiveAppsAreNeverRecorded() async {
        let setup = Self.make()
        setup.preferences.contextExcludedApplications = ["com.example.Private"]

        await setup.service.record("secret", for: Self.session(bundle: "com.example.Private"), delivery: .inserted)
        await setup.service.record("secret", for: Self.session(bundle: "com.1password.1password"), delivery: .copied)

        #expect(setup.store.saveCount == 0)
        await setup.service.record("fine", for: Self.session(bundle: "com.example.Other"), delivery: .inserted)
        #expect(setup.store.history.count == 1)
    }

    @Test func anUnknownAppIsTreatedLikeAnyOtherApp() async {
        let setup = Self.make()
        await setup.service.record("hello", for: Self.session(bundle: nil), delivery: .inserted)
        #expect(setup.store.history.count == 1)
    }

    @Test func emptyAndOversizedResultsAreNotRecorded() async {
        let setup = Self.make()
        await setup.service.record("   \n ", for: Self.session(), delivery: .inserted)
        await setup.service.record(
            String(repeating: "a", count: DictationHistory.maximumTextLength + 1), for: Self.session(),
            delivery: .inserted)
        #expect(setup.store.saveCount == 0)
    }

    // MARK: Changing

    @Test func turningHistoryOffDeletesEveryEntry() async throws {
        let setup = Self.make()
        await setup.service.record("one", for: Self.session(), delivery: .inserted)
        #expect(await setup.service.entriesRemoved(by: .off) == 1)

        try await setup.service.apply(.off)

        #expect(setup.preferences.historyRetention == .off)
        #expect(setup.store.history.isEmpty)
        #expect(setup.store.deleteCount == 1)
    }

    @Test func aShorterPeriodReportsAndDeletesWhatItExpires() async throws {
        let setup = Self.make(.untilDeleted)
        await setup.service.record("old", for: Self.session(), delivery: .inserted)
        setup.clock.advance(3 * 86_400)
        await setup.service.record("recent", for: Self.session(), delivery: .inserted)

        #expect(await setup.service.entriesRemoved(by: .oneDay) == 1)
        #expect(await setup.service.entriesRemoved(by: .untilDeleted) == 0)
        try await setup.service.apply(.oneDay)

        #expect(setup.store.history.entries.map(\.text) == ["recent"])
    }

    @Test func deleteOneAndDeleteAll() async throws {
        let setup = Self.make()
        await setup.service.record("keep", for: Self.session(), delivery: .inserted)
        setup.clock.advance(10)
        await setup.service.record("drop", for: Self.session(), delivery: .inserted)
        let drop = try #require(setup.store.history.entries.first)

        try await setup.service.delete(drop.id)
        #expect(setup.store.history.entries.map(\.text) == ["keep"])

        try await setup.service.deleteAll()
        #expect(setup.store.history.isEmpty)
        #expect(await setup.service.snapshot().entries.isEmpty)
    }

    @Test func exportIsVersionedJsonOfTheEntries() async throws {
        let setup = Self.make()
        await setup.service.record("export me", for: Self.session(), delivery: .inserted)

        let data = try await setup.service.exportData()

        let decoded = try DictationHistoryArchive.decode(data)
        #expect(decoded.entries.map(\.text) == ["export me"])
        #expect(String(data: data, encoding: .utf8)?.contains("\"formatVersion\"") == true)
    }

    // MARK: Failure and privacy

    @Test func aFailedSaveDoesNotThrowAndIsReportedByIdentifierOnly() async {
        let setup = Self.make()
        setup.store.failSaves(with: .storageFailure)

        await setup.service.record(Self.canary, for: Self.session(), delivery: .inserted)

        #expect(setup.diagnostics.events.contains { $0.name == "history.save-failed" })
        #expect(!String(describing: setup.diagnostics.events).contains(Self.canary))
    }

    @Test func anUnreadableFileIsReportedInTheSnapshot() async {
        let setup = Self.make(store: FakeDictationHistoryStore(issue: .unreadable))
        let snapshot = await setup.service.snapshot()
        #expect(snapshot.issue == .unreadable)
        #expect(snapshot.entries.isEmpty)
    }

    @Test func diagnosticsNeverCarryTheDictatedText() async throws {
        let setup = Self.make()
        await setup.service.record(Self.canary, for: Self.session(), delivery: .inserted)
        try await setup.service.delete(try #require(setup.store.history.entries.first).id)
        await setup.service.record(Self.canary, for: Self.session(), delivery: .copied)
        try await setup.service.apply(.off)

        let report = String(describing: setup.diagnostics.events)
        #expect(!report.contains(Self.canary))
        #expect(setup.diagnostics.events.contains { $0.name == "history.recorded" })
        #expect(setup.diagnostics.events.allSatisfy { $0.category == .history })
    }
}
