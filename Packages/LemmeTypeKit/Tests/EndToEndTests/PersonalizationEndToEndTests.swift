import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import Delivery
@testable import Shortcuts
@testable import UI

/// Epic 4 end to end (E4-S9), with fakes only at the operating-system edges:
/// shortcut → real `ActivationController` → real `RecordingCoordinator` with
/// the personalization library and modes → real `TranscriptionPipeline` →
/// real `DictationTextDelivery` → a fake app's text field.
@MainActor
@Suite(.serialized)
struct PersonalizationEndToEndTests {
    /// Every personalization string is a canary that must never reach diagnostics.
    static let canaries = [
        "CANARYTERM", "canary spoken", "CANARYWRITTEN", "canary trigger", "CANARYSNIPPET", "Canary Mode",
    ]

    static func library() throws -> (PersonalizationLibrary, DictationMode) {
        let chat = DictationMode(name: "Canary Mode", finalPunctuation: .omit)
        let library = try PersonalizationLibrary(
            vocabulary: [VocabularyEntry(term: "CANARYTERM", soundsLike: ["canary term"])],
            replacements: [Replacement(spoken: "canary spoken", written: "CANARYWRITTEN")],
            snippets: [Snippet(trigger: "canary trigger", expansion: "CANARYSNIPPET\nline two")],
            modes: [
                chat, DictationMode(id: DictationModeID(rawValue: "custom-copy"), name: "Copy Only", output: .copy),
            ],
            appRules: [AppModeRule(bundleIdentifier: "com.example.Chat", mode: chat.id)])
        return (library, chat)
    }

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "LemmeTypeTests-PersonalizationEndToEnd-\(UUID().uuidString)", isDirectory: true))
        let registrar = FakeHotKeyRegistrar()
        let driver: FakeAccessibilityDriver
        let field: FakeTextElement
        let diagnostics = DiagnosticsBuffer()
        let copier = FakeTextDelivery()
        let preferences = FakePreferences(writingMode: .clean)
        let personalization: PersonalizationModel
        let activation: ActivationController
        let coordinator: RecordingCoordinator

        init(spoken: String, bundleIdentifier: String = "com.example.Editor") throws {
            field = FakeTextElement(text: "", selection: TextSelection(location: 0, length: 0))
            driver = FakeAccessibilityDriver(focused: field)
            personalization = PersonalizationModel(store: FakePersonalizationStore(), diagnostics: diagnostics)
            personalization.replace(with: try PersonalizationEndToEndTests.library().0)
            let pasteboard = FakePasteboard()
            let delivery = DictationTextDelivery(
                driver: driver, pasteboard: pasteboard,
                keystroke: FakePasteKeystroke(pasteboard: pasteboard, driver: driver),
                policy: { ClipboardFallbackPolicy(fallback: .off) }, diagnostics: diagnostics,
                sleep: { _ in await Task.yield() })
            let model = personalization
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage,
                    permissions: FakePermissions(statuses: [.microphone: .granted]), diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: spoken))],
                    delivery: delivery, copier: copier, diagnostics: diagnostics),
                feedback: SilentFeedback(), preferences: preferences, textCopier: copier,
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), attentionDisplay: .seconds(60),
                personalization: { model.library }, diagnostics: diagnostics)
            let driver = self.driver
            activation = ActivationController(
                registrar: registrar,
                targetCapturer: StaticCapturer {
                    FakeAccessibilityDriver.target(
                        for: driver.focusedElement()?.element, bundleIdentifier: bundleIdentifier)
                },
                shortcut: .defaultDictation, editShortcut: nil, mode: .pushToTalk, diagnostics: diagnostics)
            activation.onCommand = { [coordinator] in coordinator.handle($0) }
            coordinator.onSessionEnded = { [activation] in activation.sessionEnded() }
            activation.activate()
        }

        func dictate() async {
            registrar.send(.pressed, .defaultDictation, at: 0)
            await coordinator.settle()
            source.emitTone(seconds: 0.3)
            registrar.send(.released, .defaultDictation, at: 1)
            await coordinator.settle()
        }

        var report: String { String(describing: diagnostics.snapshot()) }

        func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }
    }

    @MainActor
    final class StaticCapturer: TargetCapturing {
        let capture: @MainActor () -> ActivationTarget

        init(_ capture: @escaping @MainActor () -> ActivationTarget) {
            self.capture = capture
        }

        func captureTarget(purpose: ContextPurpose) -> ActivationTarget? { capture() }
    }

    @Test func vocabularyAndReplacementReachTheField() async throws {
        let harness = try Harness(spoken: "canary term met canary spoken")
        defer { harness.cleanUp() }
        await harness.dictate()
        #expect(harness.field.text == "CANARYTERM met CANARYWRITTEN.")
    }

    @Test func snippetIsInsertedExactly() async throws {
        let harness = try Harness(spoken: "Canary trigger.")
        defer { harness.cleanUp() }
        await harness.dictate()
        #expect(harness.field.text == "CANARYSNIPPET\nline two")
    }

    @Test func appRuleChoosesItsModeOnlyInThatApp() async throws {
        let chat = try Harness(spoken: "see you soon", bundleIdentifier: "com.example.Chat")
        defer { chat.cleanUp() }
        await chat.dictate()
        #expect(chat.field.text == "See you soon")

        let editor = try Harness(spoken: "see you soon")
        defer { editor.cleanUp() }
        await editor.dictate()
        #expect(editor.field.text == "See you soon.")
    }

    @Test func copyOnlyModeLeavesTheFieldAlone() async throws {
        let harness = try Harness(spoken: "copy this")
        defer { harness.cleanUp() }
        harness.preferences.dictationMode = DictationModeID(rawValue: "custom-copy")
        await harness.dictate()
        #expect(harness.field.text.isEmpty)
        #expect(harness.copier.copied == ["Copy this."])
        #expect(harness.coordinator.lastDelivery == .copied)
    }

    @Test func exportImportRoundTripKeepsTheBehaviour() async throws {
        let harness = try Harness(spoken: "canary spoken")
        defer { harness.cleanUp() }
        let data = try harness.personalization.exportData()
        await harness.personalization.deleteAll()
        harness.personalization.replace(with: try harness.personalization.readImport(data).get())
        await harness.dictate()
        #expect(harness.field.text == "CANARYWRITTEN.")
    }

    @Test func personalizationNeverReachesDiagnostics() async throws {
        for spoken in ["canary term canary spoken", "canary trigger"] {
            let harness = try Harness(spoken: spoken, bundleIdentifier: "com.example.Chat")
            defer { harness.cleanUp() }
            await harness.dictate()
            _ = try harness.personalization.exportData()
            let report = harness.report.lowercased()
            for canary in Self.canaries {
                #expect(!report.contains(canary.lowercased()), "\(canary)")
            }
            #expect(report.contains("app-rule"))
        }
    }
}
