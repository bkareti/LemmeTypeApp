import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

/// Engine and mode selection (E2-S9).
@MainActor
struct DictationSettingsModelTests {
    let apple = FakeRecognitionEngine(
        id: .appleSpeech, supportedLanguages: ["en-US", "en-GB"], assets: .systemManaged)
    let whisper = FakeRecognitionEngine(
        id: .whisper, availability: .assetsMissing, supportedLanguages: ["en"],
        assets: .downloadable(.whisperBaseEnglish))
    let preferences = FakePreferences()

    func makeModel(assets: FakeModelAssetManager = FakeModelAssetManager()) async -> DictationSettingsModel {
        let model = DictationSettingsModel(
            engines: [apple, whisper], modelAssets: assets, preferences: preferences,
            speechAuthorizer: FakeSpeechAuthorizer(status: .notRequested))
        await model.refresh()
        return model
    }

    @Test func everyEngineShowsReadinessLocationLanguageAndDownload() async {
        let model = await makeModel()

        #expect(model.rows.map(\.id) == [.appleSpeech, .whisper])
        #expect(model.rows.map(\.availability) == [.ready, .assetsMissing])
        #expect(model.rows.allSatisfy { $0.location == .onDevice })
        #expect(model.rows[0].availability.statusTitle == "Ready")
        #expect(model.rows[1].availability.statusTitle == "Download required")
        #expect(model.rows[1].model == .notInstalled)
        #expect(model.rows[0].detail.contains("On this Mac"))
        #expect(model.rows[0].detail.contains("macOS dictation"))
        #expect(model.rows[1].detail.contains("download"))
        #expect(model.rows[1].detail.contains("MB"))
    }

    @Test func automaticChoosesAReadyLocalEngineAndSaysWhich() async {
        let model = await makeModel()
        #expect(model.selectedEngine == nil)
        #expect(model.effectiveEngine == .appleSpeech)
        #expect(model.automaticExplanation.contains("Apple Speech"))
        #expect(model.menuEngineSummary == "Engine: Automatic (Apple Speech) · On this Mac")

        apple.setAvailability(.permissionUnavailable)
        await model.refresh()
        #expect(model.effectiveEngine == nil)
        #expect(!model.hasReadyEngine)
        #expect(model.automaticExplanation == "No on-device engine is ready yet.")
    }

    @Test func choosingAnEngineIsStoredForTheNextSession() async {
        let model = await makeModel()
        model.selectEngine(.whisper)
        #expect(preferences.selectedEngine == .whisper)
        #expect(preferences.enginePreference == EnginePreference(selected: .whisper))
        model.selectEngine(nil)
        #expect(preferences.selectedEngine == nil)
    }

    @Test func unavailableSelectedEngineIsShownAndNeverSwappedSilently() async {
        let model = await makeModel()
        model.selectEngine(.whisper)

        #expect(model.effectiveEngine == nil)
        #expect(model.blockedEngine?.id == .whisper)
        #expect(model.blockedEngine?.availability == .assetsMissing)
        #expect(preferences.selectedEngine == .whisper)  // still the user's choice

        model.setFallsBackToReadyEngine(true)  // the approved automatic policy
        #expect(preferences.fallsBackToReadyEngine)
        #expect(model.effectiveEngine == .appleSpeech)
        #expect(model.blockedEngine == nil)
    }

    @Test func exactAndCleanAreDescribedBeforeSelection() async {
        let model = await makeModel()
        #expect(WritingMode.exact.summary != WritingMode.clean.summary)
        #expect(WritingMode.exact.summary.contains("exactly"))
        #expect(WritingMode.clean.summary.contains("never changed"))
        model.setWritingMode(.clean)
        #expect(preferences.writingMode == .clean)
        #expect(model.writingMode == .clean)
    }

    @Test func languagesComeFromTheEnginesAndChangeAvailability() async {
        let model = await makeModel()
        #expect(model.languages == ["en-US", "en-GB", "en"])
        model.setLanguage("en-GB")
        #expect(preferences.dictationLanguage == "en-GB")
    }

    @Test func downloadNeedsConfirmationWithSizeAndSpace() async throws {
        let assets = FakeModelAssetManager()
        let model = await makeModel(assets: assets)

        await model.offerDownload(of: .whisperBaseEnglish)
        let offer = try #require(model.downloadOffer)
        #expect(offer.hasEnoughSpace)
        #expect(offer.confirmationMessage.contains("MIT"))
        #expect(assets.installCount == 0)  // nothing starts before confirmation

        model.confirmDownload()
        whisper.setAvailability(.ready)
        while model.isDownloading(.whisperBaseEnglish) { await Task.yield() }
        #expect(assets.installCount == 1)
        #expect(model.rows[1].model == .installed)
        #expect(model.rows[1].isReady)
    }

    @Test func insufficientSpaceExplainsAndDoesNotStart() async throws {
        let assets = FakeModelAssetManager(availableBytes: 1_000)
        let model = await makeModel(assets: assets)
        await model.offerDownload(of: .whisperBaseEnglish)
        #expect(model.downloadOffer?.hasEnoughSpace == false)
        model.confirmDownload()
        #expect(assets.installCount == 0)
        guard case .insufficientStorage = model.modelError else {
            Issue.record("expected insufficient storage, got \(String(describing: model.modelError))")
            return
        }
    }

    @Test func removingAModelUnloadsItsEngineAndKeepsTheSelection() async {
        let assets = FakeModelAssetManager(installed: [.whisperBaseEnglish])
        whisper.setAvailability(.ready)
        let model = await makeModel(assets: assets)
        model.selectEngine(.whisper)

        whisper.setAvailability(.assetsMissing)
        await model.removeModel(.whisperBaseEnglish)

        #expect(assets.removeCount == 1)
        #expect(whisper.unloadCount == 1)
        #expect(model.rows[1].model == .notInstalled)
        #expect(model.selectedEngine == .whisper)  // the next session asks
        #expect(model.blockedEngine?.id == .whisper)
    }

    @Test func clipboardFallbackSettingsArePersisted() async {
        let model = await makeModel()
        model.setClipboardFallback(.copyOnly)
        model.setRestoreDelay(1)
        #expect(preferences.clipboardFallback == ClipboardFallbackPolicy(fallback: .copyOnly, restoreDelay: 1))
    }

    @Test func speechRecognitionCanBeRequestedFromSettings() async {
        let authorizer = FakeSpeechAuthorizer(status: .notRequested)
        let model = DictationSettingsModel(
            engines: [apple], modelAssets: FakeModelAssetManager(), preferences: preferences,
            speechAuthorizer: authorizer)
        await model.allowSpeechRecognition()
        #expect(authorizer.requestCount == 1)
    }
}
