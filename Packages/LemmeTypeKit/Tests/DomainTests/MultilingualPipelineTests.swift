import Domain
import Foundation
import TestSupport
import Testing

/// E9-S4 and E9-S5: the pipeline requests translation only when asked, writes
/// non-English text Exact, and holds a translation for review.
struct MultilingualPipelineTests {
    private func whisper(
        text: String, detected: String? = nil, error: RecognitionError? = nil,
        availability: EngineAvailability = .ready
    ) -> FakeRecognitionEngine {
        FakeRecognitionEngine(
            id: .whisper, availability: availability,
            script: .init(text: text, error: error, detectedLanguage: detected),
            supportedLanguages: ["en", "hi", "te"], assets: .downloadable(.whisperBaseEnglish),
            capabilities: [.languageDetection], tasks: [.transcribe, .translateToEnglish])
    }

    private func session(
        language: String, output: SpeechOutput = .original, mode: WritingMode = .clean
    ) throws -> DictationSession {
        try FileManager.default.createDirectory(
            at: TranscriptionPipelineTests.directory, withIntermediateDirectories: true)
        let url = TranscriptionPipelineTests.directory.appendingPathComponent("\(UUID().uuidString).placeholder")
        try Data("not audio".utf8).write(to: url)
        return DictationSession(
            audio: RecordedAudio(fileURL: url, duration: 2, format: .speech),
            target: ActivationTarget(
                processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit",
                focusedElement: nil),
            mode: mode, language: language, speechOutput: output)
    }

    private func exists(_ session: DictationSession) -> Bool {
        FileManager.default.fileExists(atPath: session.audio.fileURL.path)
    }

    // MARK: Original language

    @Test func hindiOriginalIsTranscribedAndOnlySpacingChanges() async throws {
        let engine = whisper(text: "  नमस्ते   दुनिया  ")
        let delivery = FakeTextDelivery()
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: delivery)
            .process(try session(language: "hi")) { _ in }

        #expect(outcome == .delivered(.accessibility))
        #expect(engine.lastTask == .transcribe)
        #expect(delivery.delivered == ["नमस्ते दुनिया"])
    }

    @Test func teluguTextIsNeverCleanedLikeEnglish() async throws {
        // "um" and a repeated word would be removed, and a period added, by English Clean Writing.
        let engine = whisper(text: "um నేను నేను రేపు వస్తాను")
        let delivery = FakeTextDelivery()
        _ = await TranscriptionPipeline(engines: [engine], delivery: delivery)
            .process(try session(language: "te", mode: .clean)) { _ in }
        #expect(delivery.delivered == ["um నేను నేను రేపు వస్తాను"])
    }

    @Test func originalOutputNeverRequestsTranslationInAnyWritingMode() async throws {
        for mode in WritingMode.allCases {
            let engine = whisper(text: "hello")
            _ = await TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery())
                .process(try session(language: "hi", output: .original, mode: mode)) { _ in }
            #expect(engine.lastTask == .transcribe, "\(mode)")
        }
    }

    @Test func nonEnglishDoesNotLoseNumbersOrLatinNames() async throws {
        let engine = whisper(text: "मीटिंग 3 बजे Priya के साथ")
        let delivery = FakeTextDelivery()
        _ = await TranscriptionPipeline(engines: [engine], delivery: delivery)
            .process(try session(language: "hi")) { _ in }
        #expect(delivery.delivered == ["मीटिंग 3 बजे Priya के साथ"])
    }

    // MARK: Translation

    @Test func englishOutputRequestsTranslationAndHoldsItForReview() async throws {
        let engine = whisper(text: "ship it on Wednesday")
        let delivery = FakeTextDelivery()
        let hindi = try session(language: "hi", output: .english)
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: delivery).process(hindi) { _ in }

        #expect(engine.lastTask == .translateToEnglish)
        // The translation gets English Clean Writing, but nothing is delivered.
        #expect(
            outcome
                == .needsAttention(
                    .reviewTranslation, engine: .whisper, alternatives: [], transcript: "Ship it on Wednesday."))
        #expect(delivery.delivered.isEmpty)
        #expect(delivery.copied.isEmpty)
        #expect(exists(hindi), "the recording is kept so Translate Again works")
    }

    @Test func translateAgainReusesTheSameRecording() async throws {
        let engine = whisper(text: "ship it")
        let hindi = try session(language: "hi", output: .english)
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery())
        _ = await pipeline.process(hindi) { _ in }
        _ = await pipeline.process(hindi) { _ in }
        #expect(engine.recognizeCount == 2)
        #expect(exists(hindi))
    }

    @Test func insertAfterReviewDeliversOnceAndDeletesTheAudio() async throws {
        let delivery = FakeTextDelivery()
        let hindi = try session(language: "hi", output: .english)
        let outcome = await TranscriptionPipeline(engines: [whisper(text: "ok")], delivery: delivery)
            .deliver("Ship it.", for: hindi)
        #expect(outcome == .delivered(.accessibility))
        #expect(delivery.delivered == ["Ship it."])
        #expect(!exists(hindi))
    }

    @Test func englishSpeechWithEnglishOutputIsNotTranslatedOrReviewed() async throws {
        let engine = whisper(text: "ship it")
        let delivery = FakeTextDelivery()
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: delivery)
            .process(try session(language: "en-US", output: .english)) { _ in }
        #expect(outcome == .delivered(.accessibility))
        #expect(engine.lastTask == .transcribe)
    }

    @Test func automaticThatHearsEnglishDeliversWithoutReview() async throws {
        let engine = whisper(text: "ship it", detected: "en")
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery())
            .process(try session(language: SpokenLanguages.automatic, output: .english)) { _ in }
        #expect(outcome == .delivered(.accessibility))
    }

    @Test func automaticThatHearsTeluguIsTranslatedAndReviewed() async throws {
        let engine = whisper(text: "ship it", detected: "te")
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery())
            .process(try session(language: SpokenLanguages.automatic, output: .english)) { _ in }
        #expect(engine.lastTask == .translateToEnglish)
        guard case .needsAttention(.reviewTranslation, _, _, let text?) = outcome else {
            Issue.record("expected a review, got \(outcome)")
            return
        }
        #expect(text == "Ship it.")
    }

    @Test func aVoiceEditInstructionIsOnlyTranscribedNeverTranslated() async throws {
        let engine = whisper(text: "make it shorter")
        var editing = try session(language: "hi", output: .english)
        editing = DictationSession(
            audio: editing.audio, target: editing.target, mode: .clean, purpose: .editing, language: "hi",
            speechOutput: .english)
        _ = await TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery()).process(editing) { _ in }
        #expect(engine.lastTask == .transcribe)
    }

    // MARK: Uncertain language, unavailable engines

    @Test func uncertainDetectionOffersEveryLanguageAndKeepsTheRecording() async throws {
        let engine = whisper(text: "x", error: .languageUncertain)
        let delivery = FakeTextDelivery()
        let spoken = try session(language: SpokenLanguages.automatic)
        let outcome = await TranscriptionPipeline(engines: [engine], delivery: delivery).process(spoken) { _ in }

        guard case .needsAttention(let issue, _, let alternatives, nil) = outcome else {
            Issue.record("expected attention, got \(outcome)")
            return
        }
        #expect(issue == .recognitionFailed(.languageUncertain))
        #expect(
            issue.actions(alternatives: alternatives) == [
                .useLanguage("en"), .useLanguage("hi"), .useLanguage("te"), .discard,
            ])
        #expect(delivery.delivered.isEmpty, "uncertain detection must not insert anything")
        #expect(exists(spoken))
    }

    @Test func aLanguageNoEngineServesIsNoEngineAvailable() async throws {
        let apple = FakeRecognitionEngine(id: .appleSpeech, supportedLanguages: ["en-US"])
        let outcome = await TranscriptionPipeline(engines: [apple], delivery: FakeTextDelivery())
            .process(try session(language: "hi")) { _ in }
        #expect(outcome == .needsAttention(.noEngineAvailable, engine: nil, alternatives: [], transcript: nil))
    }

    @Test func aMissingModelIsReportedBeforeRecordingForOtherLanguagesOnly() async throws {
        let engine = whisper(text: "x", availability: .assetsMissing)
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery())

        let hindi = await pipeline.languageIssue(language: "hi", output: .original, enginePreference: .automatic)
        #expect(hindi == .languageUnavailable(.needsModel(.whisperSmall)))
        #expect(hindi?.actions(alternatives: []) == [.chooseLanguage, .discard])

        // Plain English keeps its existing behaviour: recording starts and the pipeline asks afterwards.
        let english = await pipeline.languageIssue(language: "en-US", output: .original, enginePreference: .automatic)
        #expect(english == nil)
    }

    // MARK: Privacy

    @Test func diagnosticsNameLanguageAndTaskButNeverTheText() async throws {
        let canary = "CANARY-SPOKEN-TEXT-2c7e"
        let diagnostics = RecordingDiagnostics()
        let engine = whisper(text: canary)
        _ = await TranscriptionPipeline(engines: [engine], delivery: FakeTextDelivery(), diagnostics: diagnostics)
            .process(try session(language: "hi", output: .english)) { _ in }

        let json = String(describing: diagnostics.events)
        #expect(!json.contains(canary))
        #expect(!json.localizedCaseInsensitiveContains("CANARY"))
        #expect(json.contains("\"language\""))
        #expect(json.contains("translate-to-english"))
        #expect(json.contains("review.translation"))
    }
}
