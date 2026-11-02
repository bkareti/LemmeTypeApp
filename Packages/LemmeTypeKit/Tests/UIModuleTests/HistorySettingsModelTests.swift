import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import UI

/// E6-S4: history is off on a fresh install, and every change that deletes
/// something asks first.
@MainActor
struct HistorySettingsModelTests {
    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    struct Setup {
        let model: HistorySettingsModel
        let service: DictationHistoryService
        let store: FakeDictationHistoryStore
        let preferences: FakePreferences
        let copier: FakeTextDelivery
        let clock: Clock
    }

    private func make(retention: HistoryRetention = .off, entries: [String] = []) async -> Setup {
        let clock = Clock()
        let preferences = FakePreferences()
        preferences.historyRetention = retention
        let store = FakeDictationHistoryStore(
            history: DictationHistory(
                entries: entries.enumerated().map { index, text in
                    DictationHistoryEntry(
                        createdAt: clock.now.addingTimeInterval(-TimeInterval(index) * 60), text: text,
                        mode: "clean", language: "en-US", delivery: .inserted)
                }))
        let service = DictationHistoryService(
            store: store, preferences: preferences, now: { clock.now })
        let copier = FakeTextDelivery()
        let model = HistorySettingsModel(history: service, copier: copier)
        await model.refresh()
        return Setup(
            model: model, service: service, store: store, preferences: preferences, copier: copier, clock: clock)
    }

    @Test func aFreshInstallHasHistoryOffAndEmpty() async {
        let setup = await make()
        #expect(setup.model.hasLoaded)
        #expect(!setup.model.isOn)
        #expect(setup.model.retention == .off)
        #expect(setup.model.entries.isEmpty)
        #expect(setup.store.saveCount == 0)
    }

    @Test func turningHistoryOnChoosesOneWeekWithoutAsking() async {
        let setup = await make()
        await setup.model.setOn(true)
        #expect(setup.model.retention == .oneWeek)
        #expect(setup.preferences.historyRetention == .oneWeek)
        #expect(setup.model.pendingChange == nil)
    }

    @Test func turningHistoryOffAsksBeforeDeletingAndCancelKeepsEverything() async {
        let setup = await make(retention: .oneWeek, entries: ["one", "two"])
        #expect(setup.model.entries.count == 2)

        await setup.model.setOn(false)

        #expect(setup.model.pendingChange == .init(retention: .off, removes: 2))
        #expect(setup.model.retention == .oneWeek, "nothing changed yet")
        setup.model.cancelPendingChange()
        #expect(setup.model.pendingChange == nil)
        #expect(setup.model.retention == .oneWeek)
        #expect(setup.model.entries.count == 2)
        #expect(setup.store.deleteCount == 0)
    }

    @Test func confirmingTurnsHistoryOffAndDeletesTheEntries() async {
        let setup = await make(retention: .oneWeek, entries: ["one", "two"])
        await setup.model.setOn(false)

        await setup.model.confirmPendingChange()

        #expect(setup.model.retention == .off)
        #expect(setup.model.entries.isEmpty)
        #expect(setup.store.history.isEmpty)
        #expect(setup.model.message?.contains("2") == true)
    }

    @Test func turningHistoryOffWithNothingSavedNeedsNoConfirmation() async {
        let setup = await make(retention: .oneWeek)
        await setup.model.setOn(false)
        #expect(setup.model.pendingChange == nil)
        #expect(setup.model.retention == .off)
    }

    @Test func aShorterPeriodAsksOnlyWhenItWouldDeleteSomething() async {
        let setup = await make(retention: .untilDeleted, entries: ["recent"])
        await setup.model.choose(.oneDay)
        #expect(setup.model.pendingChange == nil, "nothing is older than a day")
        #expect(setup.model.retention == .oneDay)

        setup.clock.advance(3 * 86_400)
        await setup.model.refresh()
        #expect(setup.model.entries.isEmpty, "expired entries disappear on refresh")
    }

    @Test func aShorterPeriodThatExpiresEntriesAsksFirst() async {
        let setup = await make(retention: .untilDeleted, entries: ["a", "b"])
        setup.clock.advance(40 * 86_400)

        await setup.model.choose(.oneMonth)

        #expect(setup.model.pendingChange == .init(retention: .oneMonth, removes: 2))
        await setup.model.confirmPendingChange()
        #expect(setup.model.entries.isEmpty)
        #expect(setup.model.retention == .oneMonth)
    }

    @Test func deleteOneRemovesItFromTheScreenAndTheStore() async throws {
        let setup = await make(retention: .oneWeek, entries: ["keep", "drop"])
        let drop = try #require(setup.model.entries.last)

        await setup.model.delete(drop)

        #expect(setup.model.entries.map(\.text) == ["keep"])
        #expect(setup.store.history.entries.map(\.text) == ["keep"])
    }

    @Test func deleteAllEmptiesTheScreenAndTheStore() async {
        let setup = await make(retention: .oneWeek, entries: ["a", "b", "c"])
        await setup.model.deleteAll()
        #expect(setup.model.entries.isEmpty)
        #expect(setup.store.history.isEmpty)
        #expect(setup.model.message != nil)
    }

    @Test func copyPutsTheEntryTextOnTheClipboard() async throws {
        let setup = await make(retention: .oneWeek, entries: ["copy this"])
        await setup.model.copy(try #require(setup.model.entries.first))
        #expect(setup.copier.copied == ["copy this"])
    }

    @Test func exportIsVersionedJsonWithTheEntries() async throws {
        let setup = await make(retention: .oneWeek, entries: ["export me"])
        let data = try #require(await setup.model.exportData())
        let decoded = try DictationHistoryArchive.decode(data)
        #expect(decoded.entries.map(\.text) == ["export me"])
    }

    @Test func anUnreadableFileIsShownAndTheListStartsEmpty() async {
        let clock = Clock()
        let preferences = FakePreferences()
        preferences.historyRetention = .oneWeek
        let service = DictationHistoryService(
            store: FakeDictationHistoryStore(issue: .unreadable), preferences: preferences, now: { clock.now })
        let model = HistorySettingsModel(history: service, copier: FakeTextDelivery())
        await model.refresh()
        #expect(model.issue == .unreadable)
        #expect(model.entries.isEmpty)
    }
}
