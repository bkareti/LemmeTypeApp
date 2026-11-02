import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E6-S8: Epic 6 end to end, with real files in a temporary folder and canary
/// text. Defaults leave nothing; History records exactly what was accepted;
/// Delete All Local Data leaves nothing.
@MainActor
@Suite(.serialized)
struct PrivacyEndToEndTests {
    static let canary = "CANARY-PRIVACY-7d2e"

    /// A throwaway "Application Support" with the real file stores inside it.
    @MainActor
    final class Disk {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-PrivacyE2E-\(UUID().uuidString)", isDirectory: true)
        let historyStore: FileDictationHistoryStore
        let personalizationStore: FilePersonalizationStore
        let preferences = FakePreferences()

        init() {
            historyStore = FileDictationHistoryStore(
                directory: root.appendingPathComponent("History", isDirectory: true))
            personalizationStore = FilePersonalizationStore(
                directory: root.appendingPathComponent("Personalization", isDirectory: true))
        }

        var service: DictationHistoryService {
            DictationHistoryService(store: historyStore, preferences: preferences)
        }

        /// Every file under the root.
        var files: [URL] {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
            else { return [] }
            return walker.compactMap { $0 as? URL }.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            }
        }

        func filesContaining(_ text: String) -> [URL] {
            files.filter { (try? Data(contentsOf: $0))?.range(of: Data(text.utf8)) != nil }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    private func dictation(
        _ disk: Disk, spoken: String, into field: FakeTextElement = FakeTextElement(), style: StyleOptions = .none,
        rewriter: FakeTextRewriter = FakeTextRewriter()
    ) throws -> StyleRewritingEndToEndTests.Harness {
        try StyleRewritingEndToEndTests.Harness(
            field: field, spoken: spoken, style: style, writing: .clean, rewriter: rewriter, history: disk.service)
    }

    // MARK: Defaults

    @Test func aDefaultRunLeavesNothingOnDisk() async throws {
        let disk = Disk()
        defer { disk.cleanUp() }
        #expect(disk.preferences.historyRetention == .off)
        let field = FakeTextElement()
        let harness = try dictation(disk, spoken: "send the report \(Self.canary)", into: field)
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(field.text.contains(Self.canary.lowercased()) || field.text.contains(Self.canary), "text was inserted")
        #expect(!FileManager.default.fileExists(atPath: disk.root.appendingPathComponent("History").path))
        #expect(disk.filesContaining(Self.canary).isEmpty)
        #expect(disk.files.isEmpty, "nothing at all was written: \(disk.files)")
        harness.expectNothingKept()
    }

    // MARK: History on

    @Test func historyRecordsExactlyTheTextTheUserAccepted() async throws {
        let disk = Disk()
        defer { disk.cleanUp() }
        disk.preferences.historyRetention = .oneWeek
        let field = FakeTextElement()
        let rewritten = "Hi,\n\nPlease send the report on Friday.\n\nThanks,"
        let harness = try dictation(
            disk, spoken: "send the report on Friday", into: field, style: StyleRewritingEndToEndTests.email,
            rewriter: FakeTextRewriter(script: .text(rewritten)))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        #expect(await disk.service.snapshot().entries.isEmpty, "nothing is recorded before the user chooses")
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        let entries = await disk.service.snapshot().entries
        #expect(entries.map(\.text) == [rewritten], "the rewrite, not the original")
        #expect(entries.first?.delivery == .inserted)
        #expect(disk.files.count == 1)

        // The file is private and holds only the documented keys.
        let file = disk.historyStore.fileURL
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let stored = try #require(object["entries"] as? [[String: Any]])
        #expect(
            Set(try #require(stored.first).keys) == [
                "id", "createdAt", "text", "mode", "language", "delivery", "words",
            ])
    }

    @Test func discardingARewriteRecordsNothing() async throws {
        let disk = Disk()
        defer { disk.cleanUp() }
        disk.preferences.historyRetention = .oneWeek
        let field = FakeTextElement()
        let harness = try dictation(
            disk, spoken: "send the report on Friday", into: field, style: StyleRewritingEndToEndTests.email,
            rewriter: FakeTextRewriter(script: .text("Hi,\n\nPlease send the report on Friday.\n\nThanks,")))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.discard)
        await harness.coordinator.settle()

        #expect(await disk.service.snapshot().entries.isEmpty)
        #expect(disk.files.isEmpty)
    }

    @Test func copyingTheOriginalRecordsTheOriginalOnly() async throws {
        let disk = Disk()
        defer { disk.cleanUp() }
        disk.preferences.historyRetention = .untilDeleted
        let field = FakeTextElement()
        let harness = try dictation(
            disk, spoken: "send the report on Friday", into: field, style: StyleRewritingEndToEndTests.email,
            rewriter: FakeTextRewriter(script: .text("Hi,\n\nPlease send the report on Friday.\n\nThanks,")))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.toggleReviewOriginal()
        harness.coordinator.perform(.copyText)
        await harness.coordinator.settle()

        let entries = await disk.service.snapshot().entries
        #expect(entries.map(\.text) == ["Send the report on Friday."])
        #expect(entries.first?.delivery == .copied)
    }

    // MARK: Delete all

    @Test func deleteAllLocalDataLeavesNothingBehind() async throws {
        let disk = Disk()
        defer { disk.cleanUp() }
        disk.preferences.historyRetention = .oneWeek
        let field = FakeTextElement()
        let harness = try dictation(disk, spoken: "send the report \(Self.canary)", into: field)
        defer { harness.cleanUp() }
        await harness.dictate(into: field)
        #expect(!disk.filesContaining(Self.canary).isEmpty, "the history file exists before the erase")

        var library = PersonalizationLibrary.empty
        try library.upsert(VocabularyEntry(term: "LemmeTypeCanary"))
        try await disk.personalizationStore.save(library)
        #expect(disk.files.count == 2)

        let personalization = PersonalizationModel(store: disk.personalizationStore)
        await personalization.load()
        let historyModel = HistorySettingsModel(history: disk.service, copier: FakeTextDelivery())
        let modes = ModesSettingsModel(
            personalization: personalization, preferences: disk.preferences, engines: [.appleSpeech],
            languages: ["en-US"], runningApplications: { [] }, applicationName: { _ in nil })
        let sessions = disk.root.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: sessions.appendingPathComponent("leftover.caf"))
        let capture = AudioCaptureService(
            source: FakeAudioSource(), storage: AudioSessionStorage(directory: sessions),
            permissions: FakePermissions(statuses: [.microphone: .granted]))
        let model = PrivacyOverviewModel(
            history: historyModel, personalization: personalization, modes: modes, capture: capture,
            modelAssets: FakeModelAssetManager(), clearDiagnostics: { 0 })

        await model.eraseAll()

        #expect(disk.files.isEmpty, "files left after Delete All Local Data: \(disk.files)")
        #expect(disk.filesContaining(Self.canary).isEmpty)
        #expect(await disk.service.snapshot().entries.isEmpty)
    }
}
