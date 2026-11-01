import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import Delivery
@testable import UI

/// E10-S5: tone and style with fakes only at the operating-system edges and
/// the model: real recording service, coordinator, pipeline, preservation
/// check, and text delivery. The real model is the opt-in test in `EditingTests`.
@MainActor
@Suite(.serialized)
struct StyleRewritingEndToEndTests {
    static let canary = "CANARY-DRAFT-5e2a"
    static let email = StyleOptions(tone: .professional, format: .email)

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeTests-EndToEndStyle-\(UUID().uuidString)", isDirectory: true))
        let engine: FakeRecognitionEngine
        let rewriter: FakeTextRewriter
        let driver: FakeAccessibilityDriver
        let copier = FakeTextDelivery()
        let diagnostics = RecordingDiagnostics()
        let coordinator: RecordingCoordinator

        init(
            field: FakeTextElement, spoken: String, style: StyleOptions, writing: WritingMode = .clean,
            rewriter: FakeTextRewriter, language: String = "en-US", output: SpeechOutput = .original
        ) throws {
            engine = FakeRecognitionEngine(
                id: .whisper, script: .init(text: spoken), supportedLanguages: ["en", "hi", "te"],
                assets: .downloadable(.whisperBaseEnglish), capabilities: [.languageDetection],
                tasks: [.transcribe, .translateToEnglish])
            self.rewriter = rewriter
            driver = FakeAccessibilityDriver(focused: field)
            let pasteboard = FakePasteboard(items: [[FakePasteboard.plainText: Data("canary-clipboard".utf8)]])
            let keystroke = FakePasteKeystroke(pasteboard: pasteboard, driver: driver)
            let mode = DictationMode(
                name: "Styled", language: language, speechOutput: output, writingMode: writing, style: style)
            var library = PersonalizationLibrary.empty
            try library.upsert(mode)
            let preferences = FakePreferences()
            preferences.dictationMode = mode.id
            let delivery = DictationTextDelivery(
                driver: driver, pasteboard: pasteboard, keystroke: keystroke,
                policy: { preferences.clipboardFallback }, diagnostics: diagnostics,
                sleep: { _ in await Task.yield() })
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage,
                    permissions: FakePermissions(statuses: [.microphone: .granted]), diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [engine], delivery: delivery, rewriter: rewriter, diagnostics: diagnostics),
                feedback: SilentFeedback(), preferences: preferences, textCopier: copier,
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), attentionDisplay: .seconds(60),
                personalization: { library }, diagnostics: diagnostics)
        }

        func dictate(into field: FakeTextElement) async {
            coordinator.handle(.start(FakeAccessibilityDriver.target(for: field)))
            await coordinator.settle()
            source.emitTone(seconds: 0.4)
            coordinator.handle(.stop)
            await coordinator.settle()
        }

        var leftoverAudio: [URL] {
            (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
        }

        var diagnosticsText: String { String(describing: diagnostics.events) }

        /// Nothing about the draft is held after the session ends.
        func expectNothingKept(sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(coordinator.reviewText == nil, sourceLocation: sourceLocation)
            #expect(coordinator.reviewOriginal == nil, sourceLocation: sourceLocation)
            #expect(coordinator.reviewStyle == nil, sourceLocation: sourceLocation)
            #expect(leftoverAudio.isEmpty, sourceLocation: sourceLocation)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }
    }

    private static let draft = "Hi,\n\nPlease send the report on Friday.\n\nThanks,"

    @Test func insertTypesTheRewriteOnceAndKeepsNothing() async throws {
        let field = FakeTextElement(text: "Re: report\n")
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(script: .text(Self.draft)))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        #expect(harness.coordinator.state == .needsAttention(.reviewRewrite(nil)))
        #expect(field.text == "Re: report\n" && field.writes.isEmpty, "nothing is inserted before the user chooses")

        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(field.text == "Re: report\n\(Self.draft)")
        #expect(field.writes.count == 1)
        #expect(harness.coordinator.state == .completed)
        harness.expectNothingKept()
    }

    @Test func useOriginalTypesTheTextFromBeforeTheRewrite() async throws {
        let field = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(script: .text(Self.draft)))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.useOriginal)
        await harness.coordinator.settle()

        #expect(field.text == "Send the report on Friday.")
        harness.expectNothingKept()
    }

    @Test func regenerateKeepsTheOriginalAndNeverRecognisesAgain() async throws {
        let field = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(
                script: .sequence([Self.draft, "Hello,\n\nKindly send the report on Friday.\n\nThanks,"])))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.regenerate)
        await harness.coordinator.settle()

        #expect(harness.engine.recognizeCount == 1)
        #expect(harness.coordinator.reviewText == "Hello,\n\nKindly send the report on Friday.\n\nThanks,")
        #expect(harness.coordinator.reviewOriginal == "Send the report on Friday.")
        #expect(field.writes.isEmpty)
    }

    @Test func discardCopyAndCancelKeepNothingAndNeverInsert() async throws {
        for choice in [DictationAction.discard, .copyText] {
            let field = FakeTextElement(text: "keep")
            let harness = try Harness(
                field: field, spoken: "send the report on Friday", style: Self.email,
                rewriter: FakeTextRewriter(script: .text(Self.draft)))
            defer { harness.cleanUp() }
            await harness.dictate(into: field)
            harness.coordinator.perform(choice)
            await harness.coordinator.settle()
            #expect(field.text == "keep" && field.writes.isEmpty, "\(choice)")
            harness.expectNothingKept()
            #expect(harness.copier.copied == (choice == .copyText ? [Self.draft] : []))
        }
    }

    @Test func aChangedFieldDuringReviewRefusesInsert() async throws {
        let field = FakeTextElement()
        let other = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(script: .text(Self.draft)))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.driver.focus(other)
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.targetChanged)))
        #expect(field.writes.isEmpty && other.writes.isEmpty && other.pastes.isEmpty)
    }

    // MARK: Who is rewritten

    @Test func exactDictationTypesVerbatimAndNeverCallsTheModel() async throws {
        let field = FakeTextElement()
        let rewriter = FakeTextRewriter(script: .text("changed"))
        let harness = try Harness(
            field: field, spoken: "um send it  Friday", style: Self.email, writing: .exact, rewriter: rewriter)
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(field.text == "um send it Friday")
        #expect(rewriter.rewriteCount == 0)
        #expect(harness.coordinator.state == .completed)
    }

    @Test func aTranslationCanBeStyledAndTheOriginalIsTheEnglishTranslation() async throws {
        let field = FakeTextElement()
        let rewriter = FakeTextRewriter(script: .text(Self.draft))
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email, rewriter: rewriter,
            language: "hi", output: .english)
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.engine.lastTask == .translateToEnglish)
        #expect(harness.coordinator.reviewOriginal == "Send the report on Friday.")
        #expect(rewriter.languages == ["en"])
        #expect(field.writes.isEmpty)
    }

    // MARK: Failure keeps the original, visibly

    @Test func anUnavailableModelOffersTheOriginalWithAReasonAndNeverCallsItASuccess() async throws {
        let field = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(availability: .notEnabled))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.coordinator.attention == .reviewRewrite(.unavailable(.notEnabled)))
        #expect(harness.coordinator.attention?.userMessage.contains("Not rewritten") == true)
        #expect(harness.coordinator.reviewText == "Send the report on Friday.")
        #expect(harness.diagnosticsText.contains("\"rewritten\""))
        let review = harness.diagnostics.events.first { $0.name == "session.review" }
        #expect(review?.attributes["rewritten"] == .flag(false))
        #expect(review?.attributes["notice"] == .id("rewrite.not-enabled"))

        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()
        #expect(field.text == "Send the report on Friday.")
    }

    @Test func aRewriteThatChangesAFactIsRejected() async throws {
        let field = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "send the report on Friday", style: Self.email,
            rewriter: FakeTextRewriter(script: .text("Hi,\n\nPlease send the report on Monday.\n\nThanks,")))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.coordinator.attention == .reviewRewrite(.meaningChanged([.dateChanged])))
        #expect(harness.coordinator.reviewText == "Send the report on Friday.")
        #expect(harness.coordinator.attentionActions == [.insertText, .copyText, .discard])
    }

    // MARK: Privacy

    @Test func draftTextNeverReachesDiagnosticsOrTheNetwork() async throws {
        NetworkRecorder.reset()
        URLProtocol.registerClass(NetworkRecorder.self)
        defer { URLProtocol.unregisterClass(NetworkRecorder.self) }
        let field = FakeTextElement()
        let harness = try Harness(
            field: field, spoken: "see \(Self.canary.lowercased()) on Friday", style: Self.email,
            rewriter: FakeTextRewriter(
                script: .text("Hi,\n\nPlease see \(Self.canary.lowercased()) on Friday.\n\nThanks,")))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.regenerate)
        await harness.coordinator.settle()
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(field.text.localizedCaseInsensitiveContains("canary-draft"))
        #expect(!harness.diagnosticsText.localizedCaseInsensitiveContains("canary"))
        #expect(harness.diagnosticsText.contains("professional-email-original"))
        #expect(NetworkRecorder.requests == 0)
        harness.expectNothingKept()
    }
}
