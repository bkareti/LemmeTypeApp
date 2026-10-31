import Domain
import TestSupport
import Testing

/// E9-S3: whether a language and output can run, and what is missing.
struct LanguageReadinessTests {
    private static let mac = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)
    private static let intel = HardwareProfile(isAppleSilicon: false, physicalMemoryBytes: 16 << 30)

    private func whisper(_ availability: EngineAvailability = .ready) -> FakeRecognitionEngine {
        FakeRecognitionEngine(
            id: .whisper, availability: availability, supportedLanguages: ["en", "hi", "te"],
            assets: .downloadable(.whisperBaseEnglish), capabilities: [.languageDetection],
            tasks: [.transcribe, .translateToEnglish])
    }

    private let apple = FakeRecognitionEngine(
        id: .appleSpeech, supportedLanguages: ["en-US", "en-GB"], assets: .systemManaged)

    @Test func plainEnglishDictationIsNotBeyondEnglish() {
        #expect(!LanguageReadiness.isBeyondEnglishDictation(language: "en-US", output: .original))
        #expect(!LanguageReadiness.isBeyondEnglishDictation(language: "en-GB", output: .original))
        #expect(LanguageReadiness.isBeyondEnglishDictation(language: "en-US", output: .english))
        #expect(LanguageReadiness.isBeyondEnglishDictation(language: "hi", output: .original))
        #expect(LanguageReadiness.isBeyondEnglishDictation(language: SpokenLanguages.automatic, output: .original))
    }

    @Test func englishOutputTranslatesEveryLanguageExceptEnglish() {
        #expect(RecognitionTask.required(for: "hi", output: .english) == .translateToEnglish)
        #expect(RecognitionTask.required(for: "te", output: .english) == .translateToEnglish)
        #expect(RecognitionTask.required(for: SpokenLanguages.automatic, output: .english) == .translateToEnglish)
        #expect(RecognitionTask.required(for: "en-US", output: .english) == .transcribe)
        #expect(RecognitionTask.required(for: "hi", output: .original) == .transcribe)
    }

    @Test func readyNamesTheEngineThatWillRun() async {
        let readiness = await LanguageReadiness.evaluate(
            language: "hi", output: .english, engines: [apple, whisper()], hardware: Self.mac)
        #expect(readiness == .ready(engine: .whisper))
        #expect(readiness.isReady)
    }

    @Test func aMissingModelNamesTheModelToDownload() async {
        let engine = whisper()
        engine.setAvailability(.assetsMissing, for: RecognitionNeed(language: "hi"))
        let hindi = await LanguageReadiness.evaluate(
            language: "hi", output: .original, engines: [apple, engine], hardware: Self.mac)
        #expect(hindi == .needsModel(.whisperSmall))

        engine.setAvailability(.assetsMissing, for: RecognitionNeed(language: "te", task: .translateToEnglish))
        let translated = await LanguageReadiness.evaluate(
            language: "te", output: .english, engines: [engine], hardware: Self.mac)
        #expect(translated == .needsModel(.whisperSmall))
    }

    @Test func englishRecommendsTheEnglishOnlyBaseModel() {
        let model = ModelCatalog.recommendedModel(for: RecognitionNeed(language: "en-US"), hardware: Self.mac)
        #expect(model?.id == .whisperBaseEnglish)
        let hindi = ModelCatalog.recommendedModel(for: RecognitionNeed(language: "hi"), hardware: Self.mac)
        #expect(hindi?.id == .whisperSmall)
    }

    @Test func aMacThatCannotRunAnyModelIsUnsupportedNotMissing() async {
        let engine = whisper(.assetsMissing)
        let readiness = await LanguageReadiness.evaluate(
            language: "hi", output: .original, engines: [engine], hardware: Self.intel)
        #expect(readiness == .unsupportedOnThisMac(.hardware))
    }

    @Test func aLanguageNoEngineOffersHasNoEngine() async {
        let tamil = await LanguageReadiness.evaluate(
            language: "ta", output: .original, engines: [apple, whisper()], hardware: Self.mac)
        #expect(tamil == .noEngine)
        let appleOnly = await LanguageReadiness.evaluate(
            language: "hi", output: .original, engines: [apple], hardware: Self.mac)
        #expect(appleOnly == .noEngine)
    }

    @Test func automaticNeedsAnEngineThatCanDetect() async {
        let detecting = await LanguageReadiness.evaluate(
            language: SpokenLanguages.automatic, output: .original, engines: [apple, whisper()], hardware: Self.mac)
        #expect(detecting == .ready(engine: .whisper))
        let none = await LanguageReadiness.evaluate(
            language: SpokenLanguages.automatic, output: .original, engines: [apple], hardware: Self.mac)
        #expect(none == .noEngine)
    }

    @Test func aChosenEngineThatCannotServeTheLanguageIsReportedNotSwapped() async {
        let engine = whisper(.permissionUnavailable)
        let readiness = await LanguageReadiness.evaluate(
            language: "hi", output: .original, engines: [engine],
            preference: EnginePreference(selected: .whisper), hardware: Self.mac)
        #expect(readiness == .engineNotReady(.permissionUnavailable))
    }

    @Test func identifiersAreStableDiagnosticsNames() {
        #expect(LanguageReadiness.needsModel(.whisperSmall).identifier == "needs-model")
        #expect(LanguageReadiness.unsupportedOnThisMac(.insufficientMemory).identifier == "unsupported.insufficient-memory")
        #expect(DictationIssue.languageUnavailable(.noEngine).identifier == "language.no-engine")
        #expect(DictationIssue.reviewTranslation.identifier == "review.translation")
        #expect(RecognitionError.languageUncertain.identifier == "recognition.language-uncertain")
    }
}
