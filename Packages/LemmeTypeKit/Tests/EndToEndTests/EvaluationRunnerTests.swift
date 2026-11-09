import Domain
import Foundation
import TestSupport
import Testing

/// The evaluation harness drives the production pipeline with corpus audio:
/// scores are computed against human references, corpus files are never
/// touched, the working copy is deleted, and no text reaches a result.
struct EvaluationRunnerTests {
    static let canary = "CANARY-EVAL-5e1a"
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-EvaluationRunner-\(UUID().uuidString)", isDirectory: true)

    private var corpus: URL { root.appendingPathComponent("corpus", isDirectory: true) }
    private var work: URL { root.appendingPathComponent("work", isDirectory: true) }

    private func clip(_ name: String, _ clip: AudioClip = .tone(seconds: 1)) throws -> URL {
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        let url = corpus.appendingPathComponent(name)
        try clip.write(to: url)
        return url
    }

    private func engine(_ script: FakeRecognitionEngine.Script) -> FakeRecognitionEngine {
        FakeRecognitionEngine(
            id: .whisper, script: script, supportedLanguages: ["en", "hi", "te"],
            tasks: [.transcribe, .translateToEnglish])
    }

    private func workFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? []
    }

    @Test func scoresTheDeliveredTextAgainstTheReferenceAndLeavesTheCorpusAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("a.wav")
        let runner = EvaluationRunner(
            engine: engine(.init(text: "ship it on friday")), workDirectory: work)

        let result = try await runner.run(
            EvaluationCase(
                id: "a", audioURL: url, language: "en-US", reference: "Ship it on Wednesday.", category: "commitment"))

        #expect(result.outcome == "delivered")
        #expect(result.producedText)
        #expect(result.score.wordErrorRate == 0.25)
        #expect(result.score.words.substitutions == 1)
        #expect(!result.score.hallucinated)
        #expect(abs(result.audioSeconds - 1) < 0.001)
        #expect(result.stopToDeliverySeconds >= result.inferenceSeconds)
        #expect(result.task == "transcribe")
        #expect(result.writingMode == "clean")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(workFiles().isEmpty)
    }

    @Test(arguments: DictationMode.builtIns)
    func runsEachBuiltInMode(mode: DictationMode) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("m.wav")
        let runner = EvaluationRunner(engine: engine(.init(text: "um ship it")), workDirectory: work)

        let result = try await runner.run(
            EvaluationCase(id: "m", audioURL: url, language: "en-US", reference: "ship it", category: "filler"),
            mode: mode)

        #expect(result.mode == mode.id.rawValue)
        #expect(result.writingMode == mode.writingMode.rawValue)
        #expect((result.style != nil) == !mode.effectiveStyle.isNone)
        #expect(result.translation == nil)
        // Clean Writing and Message remove the filler; Exact never changes words.
        #expect(result.score.words.insertions == (mode.writingMode == .exact ? 1 : 0))
    }

    @Test func aTranslationIsScoredAgainstTheHumanEnglishReference() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("hi.wav")
        let runner = EvaluationRunner(engine: engine(.init(text: "I will come tomorrow")), workDirectory: work)
        let testCase = EvaluationCase(
            id: "hi-1", audioURL: url, language: "hi", reference: "मैं कल आऊँगा।",
            englishReference: "I will come tomorrow.", category: "commitment")

        let result = try await runner.run(testCase, task: .translateToEnglish)

        #expect(result.outcome == "review.translation")
        #expect(result.producedText)
        #expect(result.score.wordErrorRate == 0)
        let translation = try #require(result.translation)
        #expect(translation.violations.isEmpty)
        #expect(translation.chrF > 80)
        await #expect(throws: EvaluationError.missingEnglishReference(caseID: "hi-2")) {
            _ = try await runner.run(
                EvaluationCase(id: "hi-2", audioURL: url, language: "hi", reference: "कल", category: "short"),
                task: .translateToEnglish)
        }
    }

    @Test func aStyleModeIsScoredOnTheTextBeforeTheRewriteAndChecksTheStyle() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("s.wav")
        let rewriter = FakeTextRewriter(script: .text("- Ship it today"))
        let runner = EvaluationRunner(
            engine: engine(.init(text: "ship it today")), workDirectory: work, rewriter: rewriter)
        let mode = DictationMode(
            id: DictationModeID(rawValue: "style-bullets"), name: "Bullets", writingMode: .clean,
            style: StyleOptions(format: .bulletList))

        let result = try await runner.run(
            EvaluationCase(id: "s", audioURL: url, language: "en-US", reference: "Ship it today.", category: "style"),
            mode: mode)

        #expect(result.outcome == "review")
        #expect(result.mode == "style-bullets")
        #expect(result.score.wordErrorRate == 0)
        let style = try #require(result.style)
        #expect(style.applied)
        #expect(style.format == .followed)
        #expect(rewriter.rewriteCount == 1)
    }

    @Test func aStyleModeWithoutARewriterOffersTheOriginal() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("n.wav")
        let runner = EvaluationRunner(engine: engine(.init(text: "ship it")), workDirectory: work)
        let mode = DictationMode(
            id: DictationModeID(rawValue: "style-casual"), name: "Casual", writingMode: .clean,
            style: StyleOptions(tone: .casual))

        let result = try await runner.run(
            EvaluationCase(id: "n", audioURL: url, language: "en-US", reference: "ship it", category: "style"),
            mode: mode)

        let style = try #require(result.style)
        #expect(!style.applied)
        #expect(style.notice != nil)
        #expect(result.score.wordErrorRate == 0)
    }

    @Test func textFromSilenceIsFlaggedAsAHallucination() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("silence.wav", .silence(seconds: 2))
        let runner = EvaluationRunner(engine: engine(.init(text: "Thank you for watching.")), workDirectory: work)

        let result = try await runner.run(
            EvaluationCase(id: "s", audioURL: url, language: "en-US", reference: "", category: "silence"))

        #expect(result.score.textWithoutSpeech)
        #expect(result.score.hallucinated)
    }

    @Test func aFailedRecognitionProducesNoTextAndScoresAsEverythingMissed() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("f.wav")
        let runner = EvaluationRunner(engine: engine(.init(error: .noSpeechDetected)), workDirectory: work)

        let result = try await runner.run(
            EvaluationCase(id: "f", audioURL: url, language: "en-US", reference: "two words", category: "short"))

        #expect(result.outcome == "recognition.no-speech")
        #expect(!result.producedText)
        #expect(result.score.wordErrorRate == 1)
        #expect(result.score.words.deletions == 2)
        #expect(workFiles().isEmpty)
    }

    @Test func theHandheldFlowIsScoredFromItsReview() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("p.wav")
        let runner = EvaluationRunner(
            engine: engine(.init(text: "hello there")), workDirectory: work,
            hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 << 30, deviceClass: .iPhone),
            reviewsEveryResult: true)

        let result = try await runner.run(
            EvaluationCase(id: "p", audioURL: url, language: "en-US", reference: "Hello there.", category: "short"))

        #expect(result.outcome == "review.text")
        #expect(result.producedText)
        #expect(result.score.wordErrorRate == 0)
    }

    @Test func audioThatIsNotSpeechFormatIsRefusedBeforeTheEngineRuns() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("48k.wav", .tone(seconds: 1, sampleRate: 48_000))
        let fake = engine(.init(text: "x"))
        let runner = EvaluationRunner(engine: fake, workDirectory: work)

        await #expect(throws: EvaluationError.unsupportedSampleRate(caseID: "48k")) {
            _ = try await runner.run(
                EvaluationCase(id: "48k", audioURL: url, language: "en-US", reference: "x", category: "format"))
        }
        #expect(fake.recognizeCount == 0)
    }

    @Test func resultsCarryNoSpokenOrReferenceText() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try clip("c.wav")
        let runner = EvaluationRunner(engine: engine(.init(text: Self.canary)), workDirectory: work)

        let result = try await runner.run(
            EvaluationCase(
                id: "c", audioURL: url, language: "en-US", reference: "REFERENCE-\(Self.canary)", category: "privacy"))
        let encoded = try #require(String(bytes: try JSONEncoder().encode(result), encoding: .utf8))

        #expect(!encoded.contains("CANARY"))
        #expect(!encoded.contains("REFERENCE"))
        #expect(encoded.contains("substitutions"))
    }
}
