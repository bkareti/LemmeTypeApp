import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E6-S5: Delete All Local Data removes what it says and nothing else, and is
/// safe to repeat.
@MainActor
struct PrivacyOverviewModelTests {
    struct Setup {
        let model: PrivacyOverviewModel
        let historyStore: FakeDictationHistoryStore
        let personalizationStore: FakePersonalizationStore
        let diagnostics: DiagnosticsBuffer
        let assets: FakeModelAssetManager
        let sessions: URL
    }

    private func make(
        history: [String] = ["one", "two"], vocabulary: [String] = ["LemmeType"],
        installed: Set<ModelAssetID> = [.whisperBaseEnglish], staleAudio: Bool = true
    ) throws -> Setup {
        let preferences = FakePreferences()
        preferences.historyRetention = .oneWeek
        let historyStore = FakeDictationHistoryStore(
            history: DictationHistory(
                entries: history.map {
                    DictationHistoryEntry(
                        createdAt: Date(), text: $0, mode: "clean", language: "en-US", delivery: .inserted)
                }))
        let service = DictationHistoryService(store: historyStore, preferences: preferences)
        let historyModel = HistorySettingsModel(history: service, copier: FakeTextDelivery())
        let personalizationStore = FakePersonalizationStore(
            library: try PersonalizationLibrary(
                vocabulary: vocabulary.map { VocabularyEntry(term: $0) }, replacements: [], snippets: []))
        let personalization = PersonalizationModel(store: personalizationStore)
        let modes = ModesSettingsModel(
            personalization: personalization, preferences: preferences, engines: [.appleSpeech],
            languages: ["en-US"], runningApplications: { [] }, applicationName: { _ in nil })
        let sessions = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-PrivacyErase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        if staleAudio { try Data("audio".utf8).write(to: sessions.appendingPathComponent("stale.caf")) }
        let capture = AudioCaptureService(
            source: FakeAudioSource(), storage: AudioSessionStorage(directory: sessions),
            permissions: FakePermissions(statuses: [.microphone: .granted]))
        let diagnostics = DiagnosticsBuffer()
        diagnostics.record(.lifecycle, "app.launched")
        diagnostics.record(.recorder, "recorder.started")
        let assets = FakeModelAssetManager(installed: installed)
        let model = PrivacyOverviewModel(
            history: historyModel, personalization: personalization, modes: modes, capture: capture,
            modelAssets: assets, clearDiagnostics: { diagnostics.removeAll() })
        return Setup(
            model: model, historyStore: historyStore, personalizationStore: personalizationStore,
            diagnostics: diagnostics, assets: assets, sessions: sessions)
    }

    private func clean(_ setup: Setup) { try? FileManager.default.removeItem(at: setup.sessions) }

    @Test func deleteAllRemovesHistoryPersonalizationAudioAndDiagnostics() async throws {
        let setup = try make()
        defer { clean(setup) }
        await setup.model.eraseAll()

        #expect(setup.historyStore.history.isEmpty)
        #expect(setup.personalizationStore.library == .empty)
        #expect(setup.diagnostics.snapshot().isEmpty)
        let left = try FileManager.default.contentsOfDirectory(at: setup.sessions, includingPropertiesForKeys: nil)
        #expect(left.isEmpty)
        let result = try #require(setup.model.lastErasure)
        #expect(result.historyEntries == 2)
        #expect(result.personalizationItems == 1)
        #expect(result.diagnosticsEvents == 2)
        #expect(result.modelsRemoved == 0)
    }

    @Test func modelsStayUnlessTheUserChoseToRemoveThem() async throws {
        let setup = try make()
        defer { clean(setup) }
        await setup.model.eraseAll()
        #expect(setup.assets.removeCount == 0)
        #expect(await setup.assets.state(of: .whisperBaseEnglish) == .installed)
    }

    @Test func modelsAreRemovedWhenChosen() async throws {
        let setup = try make()
        defer { clean(setup) }
        setup.model.removesModels = true
        await setup.model.eraseAll()
        #expect(setup.assets.removeCount == 1)
        #expect(await setup.assets.state(of: .whisperBaseEnglish) == .notInstalled)
        #expect(setup.model.lastErasure?.modelsRemoved == 1)
    }

    @Test func runningItTwiceReportsNothingLeft() async throws {
        let setup = try make()
        defer { clean(setup) }
        await setup.model.eraseAll()
        await setup.model.eraseAll()
        #expect(setup.model.lastErasure?.isEmpty == true)
        #expect(setup.model.resultMessage == "There was nothing left to delete.")
    }

    @Test func theMessageNamesWhatWasDeleted() async throws {
        let setup = try make()
        defer { clean(setup) }
        await setup.model.eraseAll()
        let message = try #require(setup.model.resultMessage)
        #expect(message.contains("2 saved dictations"))
        #expect(message.contains("diagnostic events"))
    }

    @Test func nothingIsReportedBeforeAnythingRuns() throws {
        let setup = try make()
        defer { clean(setup) }
        #expect(setup.model.lastErasure == nil)
        #expect(setup.model.resultMessage == nil)
        #expect(setup.model.removesModels == false)
    }
}
