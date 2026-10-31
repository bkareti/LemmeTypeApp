import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import Delivery
@testable import UI

/// E9-S6: the multilingual loop with fakes only at the operating-system edges.
/// Real recording service, coordinator, pipeline, and text delivery; a fake
/// multilingual engine; a fake app text field. Real models and real speech are
/// on the manual checklist (docs/testing/manual-acceptance.md).
@MainActor
@Suite(.serialized)
struct MultilingualEndToEndTests {
    static let hindi = "कल मीटिंग तीन बजे है"
    static let canary = "CANARY-SPOKEN-9d41"

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeTests-EndToEndLanguage-\(UUID().uuidString)", isDirectory: true))
        let engine: FakeRecognitionEngine
        let driver: FakeAccessibilityDriver
        let copier = FakeTextDelivery()
        let diagnostics = RecordingDiagnostics()
        let preferences: FakePreferences
        let coordinator: RecordingCoordinator

        init(
            field: FakeTextElement, language: String, output: SpeechOutput = .original,
            script: FakeRecognitionEngine.Script, mode: WritingMode = .clean
        ) {
            engine = FakeRecognitionEngine(
                id: .whisper, script: script, supportedLanguages: ["en", "hi", "te"],
                assets: .downloadable(.whisperBaseEnglish), capabilities: [.languageDetection],
                tasks: [.transcribe, .translateToEnglish])
            driver = FakeAccessibilityDriver(focused: field)
            let pasteboard = FakePasteboard(items: [[FakePasteboard.plainText: Data("canary-clipboard".utf8)]])
            let keystroke = FakePasteKeystroke(pasteboard: pasteboard, driver: driver)
            preferences = FakePreferences(dictationLanguage: language, writingMode: mode)
            preferences.speechOutput = output
            let delivery = DictationTextDelivery(
                driver: driver, pasteboard: pasteboard, keystroke: keystroke,
                policy: { [preferences] in preferences.clipboardFallback }, diagnostics: diagnostics,
                sleep: { _ in await Task.yield() })
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage,
                    permissions: FakePermissions(statuses: [.microphone: .granted]), diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [engine], delivery: delivery, diagnostics: diagnostics,
                    hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)),
                feedback: SilentFeedback(), preferences: preferences, textCopier: copier,
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), attentionDisplay: .seconds(60),
                diagnostics: diagnostics)
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

        func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }
    }

    // MARK: Original language

    @Test func hindiOriginalIsInsertedOnceWithoutEnglishRules() async {
        let field = FakeTextElement(text: "नोट: ")
        let harness = Harness(field: field, language: "hi", script: .init(text: " \(Self.hindi) "))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.coordinator.state == .completed)
        #expect(field.text == "नोट: \(Self.hindi)")
        #expect(field.writes.count == 1)
        #expect(harness.engine.lastTask == .transcribe)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func teluguOriginalIsInsertedOnce() async {
        let field = FakeTextElement()
        let harness = Harness(field: field, language: "te", script: .init(text: "రేపు కలుద్దాం"))
        defer { harness.cleanUp() }
        await harness.dictate(into: field)
        #expect(field.text == "రేపు కలుద్దాం")
        #expect(harness.engine.lastLanguage == "te")
    }

    // MARK: Translation with review

    @Test func hindiToEnglishIsReviewedAndOnlyInsertedWhenTheUserChoosesInsert() async {
        let field = FakeTextElement(text: "Hi Ana. ")
        let harness = Harness(
            field: field, language: "hi", output: .english, script: .init(text: "the meeting is at three tomorrow"))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.coordinator.state == .needsAttention(.reviewTranslation))
        #expect(harness.coordinator.reviewText == "The meeting is at three tomorrow.")
        #expect(field.text == "Hi Ana. ", "nothing is inserted before the user chooses")
        #expect(field.writes.isEmpty && field.pastes.isEmpty)
        #expect(!harness.leftoverAudio.isEmpty, "the recording is kept for Translate Again")

        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(field.text == "Hi Ana. The meeting is at three tomorrow.")
        #expect(field.writes.count == 1)
        #expect(harness.coordinator.state == .completed)
        #expect(harness.coordinator.reviewText == nil)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func aChangedFieldDuringReviewRefusesInsertAndCopyStillWorks() async {
        let field = FakeTextElement()
        let other = FakeTextElement()
        let harness = Harness(field: field, language: "hi", output: .english, script: .init(text: "see you soon"))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.driver.focus(other)  // the user clicked elsewhere while reading
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.targetChanged)))
        #expect(field.writes.isEmpty && other.writes.isEmpty && other.pastes.isEmpty)

        harness.coordinator.perform(.copyText)
        await harness.coordinator.settle()
        #expect(harness.copier.copied == ["See you soon."])
        #expect(harness.leftoverAudio.isEmpty)
    }

    // MARK: Automatic detection

    @Test func uncertainDetectionAsksForALanguageThenInsertsInIt() async {
        let field = FakeTextElement()
        let harness = Harness(
            field: field, language: SpokenLanguages.automatic, script: .init(text: "x", error: .languageUncertain))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        #expect(harness.coordinator.state == .needsAttention(.recognitionFailed(.languageUncertain)))
        #expect(field.writes.isEmpty, "uncertain detection must not insert or guess English")

        harness.engine.setScript(.init(text: Self.hindi))
        harness.coordinator.perform(.useLanguage("hi"))
        await harness.coordinator.settle()

        #expect(field.text == Self.hindi)
        #expect(harness.engine.lastLanguage == "hi")
        #expect(harness.leftoverAudio.isEmpty)
    }

    // MARK: Failures leave the destination untouched

    @Test func aMissingModelIsRefusedBeforeRecordingAndLeavesNoAudio() async {
        let field = FakeTextElement(text: "unchanged")
        let harness = Harness(field: field, language: "hi", script: .init(text: Self.hindi))
        defer { harness.cleanUp() }
        harness.engine.setAvailability(.assetsMissing, for: RecognitionNeed(language: "hi"))

        harness.coordinator.handle(.start(FakeAccessibilityDriver.target(for: field)))
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .needsAttention(.languageUnavailable(.needsModel(.whisperSmall))))
        #expect(!harness.source.isRunning)
        #expect(field.text == "unchanged" && field.writes.isEmpty)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func cancellingATranslationDeliversNothingAndDeletesTheAudio() async {
        let field = FakeTextElement()
        let harness = Harness(
            field: field, language: "hi", output: .english, script: .init(text: "x", delay: .seconds(5)))
        defer { harness.cleanUp() }

        harness.coordinator.handle(.start(FakeAccessibilityDriver.target(for: field)))
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.4)
        harness.coordinator.handle(.stop)
        harness.coordinator.handle(.cancel)
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .cancelled)
        #expect(field.writes.isEmpty && harness.coordinator.reviewText == nil)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func aModelThatCannotLoadUnderMemoryPressureLeavesTheFieldUntouchedAndDiscardCleansUp() async {
        let field = FakeTextElement(text: "keep")
        let harness = Harness(
            field: field, language: "hi", output: .english, script: .init(text: "x", error: .modelLoadFailed))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)

        #expect(harness.coordinator.state == .needsAttention(.recognitionFailed(.modelLoadFailed)))
        #expect(field.text == "keep" && field.writes.isEmpty)
        harness.coordinator.perform(.discard)
        await harness.coordinator.settle()
        #expect(harness.leftoverAudio.isEmpty)
        #expect(harness.coordinator.reviewText == nil)
    }

    // MARK: Privacy

    @Test func spokenAndTranslatedTextNeverReachDiagnostics() async {
        let field = FakeTextElement()
        let harness = Harness(
            field: field, language: "hi", output: .english, script: .init(text: Self.canary.lowercased()))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(field.text.localizedCaseInsensitiveContains("canary-spoken"))
        #expect(!harness.diagnosticsText.localizedCaseInsensitiveContains("canary"))
        #expect(!harness.diagnosticsText.contains(Self.hindi))
        #expect(harness.diagnosticsText.contains("translate-to-english"))
    }

    @Test func translationMakesNoURLLoadingRequests() async {
        NetworkRecorder.reset()
        URLProtocol.registerClass(NetworkRecorder.self)
        defer { URLProtocol.unregisterClass(NetworkRecorder.self) }
        let field = FakeTextElement()
        let harness = Harness(field: field, language: "te", output: .english, script: .init(text: "see you"))
        defer { harness.cleanUp() }

        await harness.dictate(into: field)
        harness.coordinator.perform(.insertText)
        await harness.coordinator.settle()

        #expect(field.text == "See you.")
        #expect(NetworkRecorder.requests == 0)
    }
}
