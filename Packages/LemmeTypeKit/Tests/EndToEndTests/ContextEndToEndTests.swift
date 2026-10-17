import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import Delivery
@testable import Shortcuts
@testable import UI

/// Epic 3 end to end (E3-S7), with fakes only at the operating-system edges:
/// shortcut press → real `ActivationController` → `CursorContextReader` over
/// a fake app's field → real `RecordingCoordinator` and `TranscriptionPipeline`
/// (formatter or rewriter) → real `DictationTextDelivery` → the same field.
@MainActor
@Suite(.serialized)
struct ContextEndToEndTests {
    /// Captures like `AccessibilityTargetCapturer`, but from the fake driver.
    @MainActor
    final class FieldCapturer: TargetCapturing {
        let driver: FakeAccessibilityDriver
        let reader: CursorContextReader<FakeAccessibilityDriver>
        let bundleIdentifier: String

        init(driver: FakeAccessibilityDriver, policy: @escaping @Sendable () -> ContextPolicy, bundleIdentifier: String)
        {
            self.driver = driver
            self.reader = CursorContextReader(driver: driver, policy: policy)
            self.bundleIdentifier = bundleIdentifier
        }

        func captureTarget(purpose: ContextPurpose) -> ActivationTarget? {
            let focused = driver.focusedElement()?.element
            let target = FakeAccessibilityDriver.target(for: focused, bundleIdentifier: bundleIdentifier)
            return target.with(context: reader.read(for: target, purpose: purpose))
        }
    }

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeTests-ContextEndToEnd-\(UUID().uuidString)", isDirectory: true))
        let registrar = FakeHotKeyRegistrar()
        let driver: FakeAccessibilityDriver
        let diagnostics = DiagnosticsBuffer()
        let rewriter: FakeTextRewriter
        let preferences: FakePreferences
        let activation: ActivationController
        let coordinator: RecordingCoordinator

        init(
            field: FakeTextElement, spoken: String, mode: WritingMode = .clean,
            preferences: FakePreferences = FakePreferences(usesFormattingContext: true),
            rewriter: FakeTextRewriter = FakeTextRewriter(), bundleIdentifier: String = "com.example.Editor"
        ) {
            preferences.writingMode = mode
            self.preferences = preferences
            self.rewriter = rewriter
            driver = FakeAccessibilityDriver(focused: field)
            let pasteboard = FakePasteboard()
            let delivery = DictationTextDelivery(
                driver: driver, pasteboard: pasteboard,
                keystroke: FakePasteKeystroke(pasteboard: pasteboard, driver: driver),
                policy: { ClipboardFallbackPolicy(fallback: .off) }, diagnostics: diagnostics,
                sleep: { _ in await Task.yield() })
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage,
                    permissions: FakePermissions(statuses: [.microphone: .granted]), diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: spoken))],
                    delivery: delivery, rewriter: rewriter, diagnostics: diagnostics),
                feedback: SilentFeedback(), preferences: preferences, textCopier: FakeTextDelivery(),
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), attentionDisplay: .seconds(60),
                diagnostics: diagnostics)
            activation = ActivationController(
                registrar: registrar,
                targetCapturer: FieldCapturer(
                    driver: driver, policy: { [preferences] in preferences.contextPolicy },
                    bundleIdentifier: bundleIdentifier),
                shortcut: .defaultDictation, editShortcut: .defaultVoiceEdit, mode: .pushToTalk,
                diagnostics: diagnostics)
            activation.onCommand = { [coordinator] in coordinator.handle($0) }
            coordinator.onSessionEnded = { [activation] in activation.sessionEnded() }
            activation.activate()
        }

        /// Holds `shortcut`, speaks, releases.
        func press(_ shortcut: KeyboardShortcut, beforeRelease: () -> Void = {}) async {
            registrar.send(.pressed, shortcut, at: 0)
            await coordinator.settle()
            source.emitTone(seconds: 0.3)
            beforeRelease()
            registrar.send(.released, shortcut, at: 1)
            await coordinator.settle()
        }

        var report: String {
            String(describing: diagnostics.snapshot())
        }

        func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }
    }

    private static func field(_ text: String, caretAt marker: Character = "|") -> FakeTextElement {
        let index = text.firstIndex(of: marker) ?? text.endIndex
        let location = text[..<index].utf16.count
        let content = text.replacingOccurrences(of: String(marker), with: "")
        return FakeTextElement(text: content, selection: TextSelection(location: location, length: 0))
    }

    // MARK: Context-aware formatting

    @Test func midSentenceDictationJoinsTheSentence() async {
        let field = Self.field("We met on Monday and| later.")
        let harness = Harness(field: field, spoken: "then we left")
        defer { harness.cleanUp() }

        await harness.press(.defaultDictation)

        #expect(field.text == "We met on Monday and then we left later.")
        #expect(harness.coordinator.state == .completed)
    }

    @Test func sentenceStartDictationKeepsCapitals() async {
        let field = Self.field("Done.|")
        let harness = Harness(field: field, spoken: "then we left")
        defer { harness.cleanUp() }

        await harness.press(.defaultDictation)

        #expect(field.text == "Done. Then we left.")
    }

    @Test func contextOffByDefaultBehavesLikeEpic2() async {
        let field = Self.field("We met and|")
        let harness = Harness(field: field, spoken: "then we left", preferences: FakePreferences())
        defer { harness.cleanUp() }

        await harness.press(.defaultDictation)

        #expect(field.text == "We met andThen we left.")  // Epic 2 behaviour: no context, no join
        #expect(field.textReads.isEmpty)
    }

    @Test func excludedAppIsNeverRead() async {
        let field = Self.field("Secret plans and|")
        let preferences = FakePreferences(
            usesFormattingContext: true, contextExcludedApplications: ["com.example.Editor"])
        let harness = Harness(field: field, spoken: "more", preferences: preferences)
        defer { harness.cleanUp() }

        await harness.press(.defaultDictation)

        #expect(field.textReads.isEmpty)
        #expect(harness.coordinator.state == .completed)
        #expect(harness.report.contains("excluded-app"))
    }

    @Test func passwordFieldIsNeitherReadNorTyped() async {
        var behavior = FakeTextElement.Behavior()
        behavior.isSecure = true
        let field = FakeTextElement(text: "hunter2", behavior: behavior)
        let harness = Harness(field: field, spoken: "password")
        defer { harness.cleanUp() }

        await harness.press(.defaultDictation)
        await harness.press(.defaultVoiceEdit)

        #expect(field.textReads.isEmpty)
        #expect(field.writes.isEmpty)
        #expect(!harness.driver.readSecureField)
    }

    // MARK: Voice editing

    @Test func voiceEditReplacesTheSelection() async {
        let field = FakeTextElement(
            text: "Please send the report today.", selection: TextSelection(location: 16, length: 6))
        let harness = Harness(field: field, spoken: "make it loud", rewriter: FakeTextRewriter())
        defer { harness.cleanUp() }

        await harness.press(.defaultVoiceEdit)

        #expect(field.text == "Please send the REPORT today.")
        #expect(field.writes == ["REPORT"])
        #expect(harness.rewriter.instructions == ["make it loud"])
    }

    @Test func refusalLeavesTheTextUnchanged() async {
        let field = FakeTextElement(text: "Keep this.", selection: TextSelection(location: 0, length: 4))
        let harness = Harness(
            field: field, spoken: "rewrite", rewriter: FakeTextRewriter(script: .failure(.refused)))
        defer { harness.cleanUp() }

        await harness.press(.defaultVoiceEdit)

        #expect(field.text == "Keep this.")
        #expect(field.writes.isEmpty)
        #expect(harness.coordinator.state == .needsAttention(.rewriteFailed(.refused)))
    }

    @Test func changedSelectionIsNotReplaced() async {
        let field = FakeTextElement(text: "Alpha beta gamma", selection: TextSelection(location: 6, length: 4))
        let harness = Harness(field: field, spoken: "shout")
        defer { harness.cleanUp() }

        await harness.press(.defaultVoiceEdit) {
            field.select(TextSelection(location: 0, length: 5))  // the user selects something else
        }

        #expect(field.text == "Alpha beta gamma")
        #expect(harness.coordinator.state == .needsAttention(.deliveryFailed(.targetChanged)))
    }

    @Test func noSelectionNeverRecords() async {
        let field = Self.field("Nothing selected|")
        let harness = Harness(field: field, spoken: "shout")
        defer { harness.cleanUp() }

        harness.registrar.send(.pressed, .defaultVoiceEdit, at: 0)
        await harness.coordinator.settle()

        #expect(harness.coordinator.state == .needsAttention(.editingUnavailable(.noSelection)))
        #expect(harness.source.startCount == 0)
    }

    // MARK: Privacy

    @Test func contextSelectionInstructionAndResultNeverReachDiagnostics() async {
        let field = FakeTextElement(
            text: "CANARY-PRECEDING-a1 CANARY-SELECTED-b2 CANARY-FOLLOWING-c3",
            selection: TextSelection(location: 20, length: 18))
        let harness = Harness(
            field: field, spoken: "CANARY-INSTRUCTION-d4", rewriter: FakeTextRewriter(script: .text("CANARY-RESULT-e5"))
        )
        defer { harness.cleanUp() }

        await harness.press(.defaultVoiceEdit)
        field.select(TextSelection(location: 20, length: 0))
        await harness.press(.defaultDictation)

        let report = harness.report
        for canary in ["PRECEDING-a1", "SELECTED-b2", "FOLLOWING-c3", "INSTRUCTION-d4", "RESULT-e5"] {
            #expect(!report.contains(canary), "\(canary) leaked into diagnostics")
        }
        #expect(report.contains("rewriteSeconds"))
        #expect(report.contains("captured"))
    }
}
