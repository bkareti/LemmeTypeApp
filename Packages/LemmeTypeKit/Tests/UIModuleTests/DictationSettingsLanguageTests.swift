import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

/// E9-S3: the language and output controls, and the readiness they show.
@MainActor
struct DictationSettingsLanguageTests {
    let apple = FakeRecognitionEngine(
        id: .appleSpeech, supportedLanguages: ["en-US", "en-GB"], assets: .systemManaged)
    let whisper = FakeRecognitionEngine(
        id: .whisper, supportedLanguages: ["en", "hi", "te"], assets: .downloadable(.whisperBaseEnglish),
        capabilities: [.languageDetection], tasks: [.transcribe, .translateToEnglish])
    let preferences = FakePreferences()
    /// Model fit is judged against a fixed Mac, not the machine running the tests.
    static let mac = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)

    func makeModel(
        engines: [FakeRecognitionEngine]? = nil, scope: LanguageScope = .allLanguages
    ) async -> DictationSettingsModel {
        let model = DictationSettingsModel(
            engines: engines ?? [apple, whisper], modelAssets: FakeModelAssetManager(), preferences: preferences,
            hardware: Self.mac, languageScope: scope)
        await model.refresh()
        return model
    }

    @Test func languageAndOutputAreIndependentChoicesStoredForTheNextSession() async {
        let model = await makeModel()
        model.setLanguage("hi")
        model.setSpeechOutput(.english)
        #expect(preferences.dictationLanguage == "hi")
        #expect(preferences.speechOutput == .english)

        model.setSpeechOutput(.original)
        #expect(preferences.dictationLanguage == "hi", "changing the output must not change the language")
        model.setLanguage("te")
        #expect(preferences.speechOutput == .original, "changing the language must not change the output")
    }

    @Test func theLanguageMenuOffersAutomaticEnglishRegionsAndTheEvaluationLanguages() async {
        let model = await makeModel()
        #expect(model.languageChoices == [SpokenLanguages.automatic, "en-US", "en-GB", "hi", "te"])
        #expect(DictationSettingsModel.settingLanguageName(SpokenLanguages.automatic) == "Automatic")
        #expect(DictationSettingsModel.settingLanguageName("hi") == "Hindi · हिन्दी")
    }

    // MARK: English-only scope (ADR 0029)

    @Test func anEnglishOnlyBuildOffersEnglishRegionsWithoutAutomaticOrOtherLanguages() async {
        let model = await makeModel(scope: .englishOnly)
        #expect(model.languageChoices == ["en-US", "en-GB"])
        #expect(model.speechOutputChoices == [.original], "nothing to translate, so the output picker is hidden")
        #expect(model.readiness == .ready(engine: .appleSpeech))
    }

    @Test func anEnglishOnlyBuildKeepsAStoredOtherLanguageVisibleSoItCanBeChangedBack() async {
        preferences.dictationLanguage = "hi"
        let model = await makeModel(scope: .englishOnly)
        #expect(model.languageChoices == ["en-US", "en-GB", "hi"])
        model.setLanguage("en-US")
        #expect(model.languageChoices == ["en-US", "en-GB"])
    }

    @Test func everyLanguageStaysOfferedWhenTheScopeIsAllLanguages() async {
        let model = await makeModel(scope: .allLanguages)
        #expect(model.languageChoices == [SpokenLanguages.automatic, "en-US", "en-GB", "hi", "te"])
        #expect(model.speechOutputChoices == SpeechOutput.allCases)
    }

    @Test func theCloudScopeOffersTeluguButNeitherAutomaticNorHindi() async {
        let model = await makeModel(scope: .englishWithCloud)
        #expect(model.languageChoices == ["en-US", "en-GB", "te"])
        #expect(model.speechOutputChoices == [.original])
    }

    @Test func automaticIsOfferedOnlyWhenAnEngineCanDetect() async {
        let model = await makeModel(engines: [apple])
        #expect(model.languageChoices == ["en-US", "en-GB"])
        let englishOnly = FakeRecognitionEngine(id: .whisper, supportedLanguages: ["en"], assets: .none)
        let model2 = await makeModel(engines: [englishOnly])
        #expect(model2.languageChoices == ["en-US"])
    }

    @Test func aStoredLanguageThatIsNoLongerOfferedStaysVisible() async {
        preferences.dictationLanguage = "ta"
        let model = await makeModel()
        #expect(model.languageChoices.last == "ta")
        #expect(model.readiness == .noEngine)
    }

    @Test func englishDictationIsReadyAndShowsNoEvaluationBadge() async {
        let model = await makeModel()
        #expect(model.readiness == .ready(engine: .appleSpeech))
        #expect(model.languageStatus == .validated)
        #expect(model.languageStatus?.badge == nil)
    }

    @Test func hindiShowsTheEvaluationBadge() async {
        let model = await makeModel()
        model.setLanguage("hi")
        await model.refresh()
        #expect(model.languageStatus == .evaluation)
        #expect(model.languageStatus?.badge == "Evaluation")
        #expect(model.readiness == .ready(engine: .whisper))
    }

    @Test func teluguSaysItIsNotReliableButCanStillBeChosen() async {
        let model = await makeModel()
        model.setLanguage("te")
        await model.refresh()
        #expect(model.languageStatus == .unreliable)
        #expect(model.languageStatus?.badge == "Not reliable")
        #expect(model.languageStatus?.explanation?.contains("Whisper Small") == true)
        #expect(model.readiness == .ready(engine: .whisper))
    }

    @Test func aMissingModelIsExplainedWithTheModelAndItsSize() async {
        whisper.setAvailability(.assetsMissing, for: RecognitionNeed(language: "hi"))
        let model = await makeModel()
        model.setLanguage("hi")
        await model.refresh()

        #expect(model.readiness == .needsModel(.whisperSmall))
        let message = model.readiness.userMessage
        #expect(message.contains("Whisper Small (Multilingual)"))
        #expect(message.contains("MB"))
        #expect(message.contains("Models"))
    }

    @Test func translationReadinessFollowsTheOutputChoice() async {
        whisper.setAvailability(.assetsMissing, for: RecognitionNeed(language: "hi", task: .translateToEnglish))
        let model = await makeModel()
        model.setLanguage("hi")
        await model.refresh()
        #expect(model.readiness.isReady, "original Hindi does not need the translation model")

        model.setSpeechOutput(.english)
        await model.refresh()
        #expect(model.readiness == .needsModel(.whisperSmall))
    }

    @Test func theMenuLineAppearsOnlyBeyondPlainEnglishAndSaysWhetherItIsReady() async {
        let model = await makeModel()
        #expect(!LanguageReadiness.isBeyondEnglishDictation(language: model.language, output: model.speechOutput))

        model.setLanguage("hi")
        model.setSpeechOutput(.english)
        await model.refresh()
        #expect(model.menuLanguageSummary == "Language: Hindi · हिन्दी → English · Ready")

        whisper.setAvailability(.assetsMissing, for: RecognitionNeed(language: "hi", task: .translateToEnglish))
        await model.refresh()
        #expect(model.menuLanguageSummary == "Language: Hindi · हिन्दी → English · Not ready")
    }

    @Test func outputDescriptionsSayWhetherAnythingIsTranslated() {
        #expect(SpeechOutput.original.summary.contains("Nothing is translated"))
        #expect(SpeechOutput.english.summary.contains("read the translation"))
    }
}
