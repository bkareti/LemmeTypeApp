import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Audio
@testable import Delivery
@testable import UI

/// The whole local loop with fakes only at the operating-system edges
/// (E2-S10): a recorded fixture → real `AudioCaptureService` → real
/// `RecordingCoordinator` → real `TranscriptionPipeline` and `TextCleaner` →
/// real `DictationTextDelivery` → a fake app's text field and clipboard.
@MainActor
@Suite(.serialized)
struct DictationEndToEndTests {
    nonisolated static let spoken = "um let's meet on Tuesday sorry Wednesday"

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeTests-EndToEnd-\(UUID().uuidString)", isDirectory: true))
        let engine: FakeRecognitionEngine
        let driver: FakeAccessibilityDriver
        let pasteboard: FakePasteboard
        let copier = FakeTextDelivery()
        let diagnostics = RecordingDiagnostics()
        let preferences: FakePreferences
        let coordinator: RecordingCoordinator
        let keystroke: FakePasteKeystroke

        init(
            field: FakeTextElement, spoken: String = DictationEndToEndTests.spoken, mode: WritingMode = .clean,
            clipboard: [[String: Data]] = [[FakePasteboard.plainText: Data("canary-clipboard".utf8)]],
            recognitionDelay: Duration = .zero
        ) {
            engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: spoken, delay: recognitionDelay))
            driver = FakeAccessibilityDriver(focused: field)
            pasteboard = FakePasteboard(items: clipboard)
            keystroke = FakePasteKeystroke(pasteboard: pasteboard, driver: driver)
            preferences = FakePreferences(writingMode: mode)
            let delivery = DictationTextDelivery(
                driver: driver, pasteboard: pasteboard, keystroke: keystroke,
                policy: { [preferences] in preferences.clipboardFallback }, diagnostics: diagnostics,
                sleep: { _ in await Task.yield() })
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage,
                    permissions: FakePermissions(statuses: [.microphone: .granted]), diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [engine], write: TextCleaner.write, delivery: delivery, diagnostics: diagnostics),
                feedback: SilentFeedback(),
                preferences: preferences,
                textCopier: copier,
                finishedDisplay: .seconds(60),
                failureDisplay: .seconds(60),
                attentionDisplay: .seconds(60),
                diagnostics: diagnostics)
        }

        func dictate(into target: ActivationTarget?) async {
            coordinator.handle(.start(target))
            await coordinator.settle()
            source.emitTone(seconds: 0.4)
            coordinator.handle(.stop)
            await coordinator.settle()
        }

        var leftoverAudio: [URL] {
            (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
        }

        /// Everything diagnostics would export, as text.
        var diagnosticsText: String { String(describing: diagnostics.events) }

        func cleanUp() {
            try? FileManager.default.removeItem(at: storage.directory)
        }
    }

    @Test func cleanWritingIsInsertedOnceIntoTheCapturedField() async {
        let field = FakeTextElement(text: "Hi Ana. ")
        let harness = Harness(field: field)
        defer { harness.cleanUp() }

        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))

        #expect(harness.coordinator.state == .completed)
        #expect(harness.coordinator.lastDelivery == .accessibility)
        #expect(field.text == "Hi Ana. Let's meet on Wednesday.")
        #expect(field.writes.count == 1)
        #expect(harness.leftoverAudio.isEmpty)
        #expect(harness.pasteboard.transientWriteCount == 0)  // clipboard untouched
        let delivered = harness.diagnostics.events.first { $0.name == "session.delivered" }
        #expect(delivered?.attributes["processingSeconds"] != nil)
        #expect(delivered?.attributes["recognitionSeconds"] != nil)
        #expect(delivered?.attributes["audioSeconds"] != nil)
        #expect(!harness.diagnosticsText.contains("Wednesday"))
        #expect(!harness.diagnosticsText.lowercased().contains("tuesday"))
    }

    @Test func exactDictationIsDeliveredVerbatim() async {
        let field = FakeTextElement()
        let harness = Harness(field: field, mode: .exact)
        defer { harness.cleanUp() }
        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))
        #expect(field.text == Self.spoken)
    }

    @Test func appsThatIgnoreAccessibilityGetAPasteAndKeepTheirClipboard() async {
        var behavior = FakeTextElement.Behavior()
        behavior.appliesWrites = false  // Electron-style
        let field = FakeTextElement(behavior: behavior)
        let previous: [[String: Data]] = [["public.png": Data([0x89, 0x50]), "public.rtf": Data("{\\rtf1}".utf8)]]
        let harness = Harness(field: field, clipboard: previous)
        defer { harness.cleanUp() }

        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))

        #expect(harness.coordinator.lastDelivery == .paste)
        #expect(field.text == "Let's meet on Wednesday.")
        #expect(field.pastes.count == 1)
        #expect(harness.pasteboard.items == previous)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func focusChangeDuringProcessingNeverTypesElsewhereAndTheTextIsRecoverable() async {
        let field = FakeTextElement()
        let other = FakeTextElement()
        let harness = Harness(field: field, recognitionDelay: .milliseconds(50))
        defer { harness.cleanUp() }

        harness.coordinator.handle(.start(FakeAccessibilityDriver.target(for: field)))
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.4)
        harness.coordinator.handle(.stop)
        harness.driver.focus(other)  // the user clicks into another field while processing
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.targetChanged)))
        #expect(other.writes.isEmpty && other.pastes.isEmpty && field.writes.isEmpty)
        #expect(harness.coordinator.attentionActions == [.copyText, .retryDelivery, .discard])

        harness.driver.focus(field)
        harness.coordinator.perform(.retryDelivery)
        await harness.coordinator.settle()
        #expect(field.text == "Let's meet on Wednesday.")
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func passwordFieldsGetNothingAndCopyIsOffered() async {
        var behavior = FakeTextElement.Behavior()
        behavior.isSecure = true
        let field = FakeTextElement(behavior: behavior)
        let harness = Harness(field: field)
        defer { harness.cleanUp() }

        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))

        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.secureField)))
        #expect(field.writes.isEmpty && field.pastes.isEmpty)
        #expect(!harness.driver.readSecureField)
        harness.coordinator.perform(.copyText)
        await harness.coordinator.settle()
        #expect(harness.copier.copied == ["Let's meet on Wednesday."])
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func cancelDuringRecognitionDeliversNothingAndDeletesAudio() async {
        let field = FakeTextElement()
        let harness = Harness(field: field, recognitionDelay: .seconds(5))
        defer { harness.cleanUp() }

        harness.coordinator.handle(.start(FakeAccessibilityDriver.target(for: field)))
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.4)
        harness.coordinator.handle(.stop)
        harness.coordinator.handle(.cancel)
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .cancelled)
        #expect(field.writes.isEmpty)
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func theLocalLoopMakesNoURLLoadingRequests() async {
        // In-process guard; scripts/check-network-silence.sh watches the real
        // app's sockets from outside.
        NetworkRecorder.reset()
        URLProtocol.registerClass(NetworkRecorder.self)
        defer { URLProtocol.unregisterClass(NetworkRecorder.self) }
        let field = FakeTextElement()
        let harness = Harness(field: field)
        defer { harness.cleanUp() }

        await harness.dictate(into: FakeAccessibilityDriver.target(for: field))

        #expect(field.text == "Let's meet on Wednesday.")
        #expect(NetworkRecorder.requests == 0)
    }
}

@MainActor
final class SilentFeedback: RecordingFeedback {
    func announce(_ message: String) {}
    func play(_ sound: FeedbackSound) {}
}

/// Counts any request URL loading would make in this process.
final class NetworkRecorder: URLProtocol {
    private static let count = Mutex(0)
    static var requests: Int { count.withLock { $0 } }
    static func reset() { count.withLock { $0 = 0 } }

    // Observes requests only; this test proves the loop makes none.
    // swiftlint:disable:next no_network_apis
    override static func canInit(with request: URLRequest) -> Bool {
        count.withLock { $0 += 1 }
        return false
    }
}
