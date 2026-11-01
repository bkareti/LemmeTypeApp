import Domain
import Foundation
import TestSupport
import Testing

@testable import Recognition

/// E9-S2: language- and task-aware model selection, detection, and uncertainty.
struct WhisperEngineLanguageTests {
    private let fixtures = RecordingFixtures()
    private static let appleSilicon16GB = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)

    private func makeEngine(
        installed: Set<ModelAssetID>, choice: WhisperModelChoice = .automatic, runtime: FakeWhisperRuntime
    ) -> WhisperEngine {
        WhisperEngine(
            assets: FakeModelAssetManager(installed: installed), hardware: Self.appleSilicon16GB, runtime: runtime,
            settings: { WhisperRunSettings(choice: choice) })
    }

    private func request(
        _ language: String, task: RecognitionTask = .transcribe
    ) throws -> RecognitionRequest {
        let base = try fixtures.make(.tone(seconds: 1.5), language: language)
        return RecognitionRequest(audio: base.audio, language: language, task: task)
    }

    private func probabilities(_ values: [String: Float]) -> [LanguageProbability] {
        values.map { LanguageProbability(code: $0.key, probability: $0.value) }
    }

    @Test func englishOnlyInstallsNeedAMultilingualDownloadForOtherLanguagesAndTranslation() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(installed: [.whisperBaseEnglish, .whisperSmallEnglish], runtime: runtime)
        #expect(await engine.availability() == .ready)
        #expect(await engine.availability(for: RecognitionNeed(language: "hi")) == .assetsMissing)
        #expect(
            await engine.availability(for: RecognitionNeed(language: "hi", task: .translateToEnglish))
                == .assetsMissing)
        await #expect(throws: RecognitionError.assetsMissing) {
            try await engine.recognize(try request("hi")) { _ in }
        }
        #expect(runtime.loadCount == 0)
    }

    @Test func aMultilingualModelServesHindiAndTranslation() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(installed: [.whisperSmall], runtime: runtime)
        #expect(await engine.availability(for: RecognitionNeed(language: "hi")) == .ready)
        #expect(await engine.availability(for: RecognitionNeed(language: "te", task: .translateToEnglish)) == .ready)

        let transcript = try await engine.recognize(try request("hi")) { _ in }
        #expect(transcript.language == "hi")
        #expect(transcript.spokenLanguage == "hi")
        #expect(runtime.receivedInferences.last?.language == "hi")
        #expect(runtime.receivedInferences.last?.task == .transcribe)
        #expect(runtime.loadedFiles == ["ggml-small.bin"])

        let translated = try await engine.recognize(try request("hi", task: .translateToEnglish)) { _ in }
        #expect(translated.language == "en")
        #expect(translated.spokenLanguage == "hi")
        #expect(runtime.receivedInferences.last?.task == .translateToEnglish)
    }

    @Test func englishUsesAnEnglishOnlyModelFirstThenTheMultilingualOne() async throws {
        defer { fixtures.removeAll() }
        let both = FakeWhisperRuntime()
        let bothEngine = makeEngine(installed: [.whisperBase, .whisperBaseEnglish], runtime: both)
        _ = try await bothEngine.recognize(try request("en-US")) { _ in }
        #expect(both.loadedFiles == ["ggml-base.en.bin"])

        let multilingualOnly = FakeWhisperRuntime()
        let engine = makeEngine(installed: [.whisperBase], runtime: multilingualOnly)
        let transcript = try await engine.recognize(try request("en-US")) { _ in }
        #expect(transcript.language == "en")
        #expect(multilingualOnly.loadedFiles == ["ggml-base.bin"])
    }

    @Test func aChosenEnglishModelIsALanguageProblemForHindiNotAMissingDownload() async {
        let runtime = FakeWhisperRuntime()
        let engine = makeEngine(
            installed: [.whisperBaseEnglish, .whisperBase], choice: .specific(.whisperBaseEnglish), runtime: runtime)
        #expect(await engine.availability(for: RecognitionNeed(language: "hi")) == .unsupported(.language))
    }

    @Test func aChosenMultilingualModelThatIsNotInstalledIsMissing() async {
        let engine = makeEngine(
            installed: [.whisperBaseEnglish], choice: .specific(.whisperSmall), runtime: FakeWhisperRuntime())
        #expect(await engine.availability(for: RecognitionNeed(language: "hi")) == .assetsMissing)
    }

    // MARK: Automatic detection

    @Test func automaticDetectsTheMostProbableCandidate() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime(
            probabilities: probabilities(["te": 0.82, "hi": 0.08, "en": 0.05, "ta": 0.01]))
        let engine = makeEngine(installed: [.whisperBase], runtime: runtime)
        let transcript = try await engine.recognize(try request(SpokenLanguages.automatic)) { _ in }
        #expect(runtime.detectionCount == 1)
        #expect(runtime.receivedInferences.last?.language == "te")
        #expect(transcript.spokenLanguage == "te")
    }

    @Test func automaticNeverGuessesWhenNoCandidateIsClearlyAhead() async throws {
        defer { fixtures.removeAll() }
        let runtime = FakeWhisperRuntime(probabilities: probabilities(["hi": 0.40, "te": 0.38, "en": 0.12]))
        let engine = makeEngine(installed: [.whisperBase], runtime: runtime)
        await #expect(throws: RecognitionError.languageUncertain) {
            try await engine.recognize(try request(SpokenLanguages.automatic)) { _ in }
        }
        #expect(runtime.receivedInferences.isEmpty, "uncertain detection must not transcribe")
    }

    @Test func automaticRefusesALanguageOutsideTheEvaluationSet() async throws {
        defer { fixtures.removeAll() }
        // Tamil holds most of the probability; Telugu is merely the closest candidate.
        let runtime = FakeWhisperRuntime(probabilities: probabilities(["ta": 0.85, "te": 0.10, "hi": 0.02]))
        let engine = makeEngine(installed: [.whisperBase], runtime: runtime)
        await #expect(throws: RecognitionError.languageUncertain) {
            try await engine.recognize(try request(SpokenLanguages.automatic)) { _ in }
        }
    }

    @Test func automaticNeedsAnInstalledModelThatCanDetect() async {
        let englishOnly = makeEngine(installed: [.whisperBaseEnglish], runtime: FakeWhisperRuntime())
        #expect(
            await englishOnly.availability(for: RecognitionNeed(language: SpokenLanguages.automatic)) == .assetsMissing)
        let chosen = makeEngine(
            installed: [.whisperBaseEnglish], choice: .specific(.whisperBaseEnglish), runtime: FakeWhisperRuntime())
        #expect(
            await chosen.availability(for: RecognitionNeed(language: SpokenLanguages.automatic))
                == .unsupported(.language))
    }

    @Test func detectionChoiceIsPureAndUsesTheDocumentedThresholds() {
        let sure = [
            LanguageProbability(code: "hi", probability: 0.7), LanguageProbability(code: "en", probability: 0.2),
        ]
        #expect(WhisperEngine.choose(from: sure, among: ["en", "hi", "te"]) == "hi")
        #expect(WhisperEngine.choose(from: [], among: ["en", "hi", "te"]) == nil)
        let borderline = [
            LanguageProbability(code: "hi", probability: 0.35), LanguageProbability(code: "en", probability: 0.35),
        ]
        #expect(WhisperEngine.choose(from: borderline, among: ["en", "hi", "te"]) == nil)
    }

    @Test func warmUpPreparesTheModelTheSettingsNeed() async throws {
        let runtime = FakeWhisperRuntime()
        let engine = WhisperEngine(
            assets: FakeModelAssetManager(installed: [.whisperBaseEnglish, .whisperSmall]),
            hardware: Self.appleSilicon16GB, runtime: runtime,
            settings: { WhisperRunSettings(warmUpNeed: RecognitionNeed(language: "hi")) })
        try await engine.prepare()
        #expect(runtime.loadedFiles == ["ggml-small.bin"])
    }
}
