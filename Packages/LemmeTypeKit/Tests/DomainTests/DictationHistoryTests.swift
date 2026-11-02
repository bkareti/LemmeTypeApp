import Domain
import Foundation
import Testing

struct DictationHistoryTests {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    static func entry(_ text: String = "hello there", age: TimeInterval = 0) -> DictationHistoryEntry {
        DictationHistoryEntry(
            createdAt: epoch.addingTimeInterval(-age), text: text, mode: "clean", language: "en-US",
            delivery: .inserted)
    }

    // MARK: Retention

    @Test func retentionIsOffByDefaultInTheEnumOrder() {
        #expect(HistoryRetention.allCases.first == .off)
        #expect(HistoryRetention.off.isOn == false)
        let others = HistoryRetention.allCases.dropFirst()
        #expect(others.allSatisfy { $0.isOn })
    }

    @Test func retentionPeriodsAreTheDocumentedOnes() {
        let day: TimeInterval = 86_400
        #expect(HistoryRetention.oneDay.maximumAge == day)
        #expect(HistoryRetention.oneWeek.maximumAge == 7 * day)
        #expect(HistoryRetention.oneMonth.maximumAge == 30 * day)
        #expect(HistoryRetention.untilDeleted.maximumAge == nil)
    }

    // MARK: Value type

    @Test func entriesAreKeptNewestFirst() {
        let history = DictationHistory(entries: [Self.entry("old", age: 100), Self.entry("new", age: 1)])
        #expect(history.entries.map(\.text) == ["new", "old"])
    }

    @Test func appendKeepsOrderAndCountsWords() {
        var history = DictationHistory(entries: [Self.entry("older", age: 50)])
        history.append(Self.entry("one two  three\nfour", age: 0))
        #expect(history.entries.first?.words == 4)
        #expect(history.count == 2)
    }

    @Test func theEntryCapDropsTheOldest() {
        var history = DictationHistory.empty
        for index in 0..<(DictationHistory.entryLimit + 5) {
            history.append(Self.entry("entry \(index)", age: TimeInterval(DictationHistory.entryLimit + 5 - index)))
        }
        #expect(history.count == DictationHistory.entryLimit)
        #expect(history.entries.first?.text == "entry \(DictationHistory.entryLimit + 4)")
        #expect(!history.entries.contains { $0.text == "entry 0" })
    }

    @Test func purgeRemovesOnlyExpiredEntries() {
        var history = DictationHistory(entries: [
            Self.entry("today", age: 3_600), Self.entry("last week", age: 8 * 86_400),
            Self.entry("last month", age: 40 * 86_400),
        ])
        #expect(history.expiredCount(for: .oneWeek, now: Self.epoch) == 2)
        #expect(history.expiredCount(for: .untilDeleted, now: Self.epoch) == 0)
        let removed = history.purge(for: .oneWeek, now: Self.epoch)
        #expect(removed == 2)
        #expect(history.entries.map(\.text) == ["today"])
        let removedAgain = history.purge(for: .untilDeleted, now: Self.epoch)
        #expect(removedAgain == 0)
    }

    @Test func removeDeletesOneEntry() {
        var history = DictationHistory(entries: [Self.entry("a", age: 2), Self.entry("b", age: 1)])
        let id = history.entries[0].id
        let first = history.remove(id: id)
        let second = history.remove(id: id)
        #expect(first)
        #expect(!second)
        #expect(history.count == 1)
        history.removeAll()
        #expect(history.isEmpty)
    }

    // MARK: Privacy by construction

    @Test func anEntryHoldsOnlyTheDocumentedFields() throws {
        let data = try JSONEncoder().encode(Self.entry())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "createdAt", "text", "mode", "language", "delivery", "words"])
    }

    @Test func descriptionsNeverShowTheText() {
        let entry = Self.entry("CANARY-HISTORY-9c1")
        #expect(!String(describing: entry).contains("CANARY"))
        #expect(!String(reflecting: entry).contains("CANARY"))
    }

    // MARK: Archive

    @Test func archiveRoundTripsAndKeepsTheVersion() throws {
        let history = DictationHistory(entries: [Self.entry("first", age: 5), Self.entry("second", age: 1)])
        let data = try DictationHistoryArchive(history).encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("com.lemmetype.history"))
        let decoded = try DictationHistoryArchive.decode(data)
        #expect(decoded == history)
    }

    /// A file written by the first version stays readable (migration guard).
    @Test func aStoredVersionOneSampleStillDecodes() throws {
        let sample = """
            {
              "entries" : [
                {
                  "createdAt" : "2026-11-01T09:30:00Z",
                  "delivery" : "copied",
                  "id" : "6F9619FF-8B86-4D11-B42D-00C04FC964FF",
                  "language" : "hi",
                  "mode" : "message",
                  "text" : "Please send the report.",
                  "words" : 4
                }
              ],
              "format" : "com.lemmetype.history",
              "formatVersion" : 1
            }
            """
        let history = try DictationHistoryArchive.decode(Data(sample.utf8))
        #expect(history.count == 1)
        #expect(history.entries[0].text == "Please send the report.")
        #expect(history.entries[0].delivery == .copied)
        #expect(history.entries[0].language == "hi")
    }

    @Test func aNewerVersionIsRefused() {
        let newer = #"{"format":"com.lemmetype.history","formatVersion":99,"entries":[]}"#
        #expect(throws: DictationHistoryError.unsupportedVersion) {
            try DictationHistoryArchive.decode(Data(newer.utf8))
        }
    }

    @Test func somethingElseIsUnreadable() {
        for junk in ["not json", #"{"format":"other","formatVersion":1,"entries":[]}"#, "{}"] {
            #expect(throws: DictationHistoryError.unreadable) {
                try DictationHistoryArchive.decode(Data(junk.utf8))
            }
        }
    }

    @Test func errorIdentifiersAreStable() {
        #expect(DictationHistoryError.unreadable.identifier == "history.unreadable")
        #expect(DictationHistoryError.unsupportedVersion.identifier == "history.unsupported-version")
        #expect(DictationHistoryError.storageFailure.identifier == "history.storage-failure")
    }
}
