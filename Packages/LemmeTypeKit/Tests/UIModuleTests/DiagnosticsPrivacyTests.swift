import Domain
import Foundation
import Support
import TestSupport
import Testing

@testable import Audio
@testable import Shortcuts
@testable import UI

/// E1-S7: canary secrets placed in every sensitive input must never reach the
/// exported diagnostics.
@MainActor
struct DiagnosticsPrivacyTests {
    private let canaries = [
        "CANARY-AUDIO-DEVICE-7f3a",
        "CANARY-FIELD-TEXT-91bd",
        "CANARY-CLIPBOARD-44c2",
        "CANARY-APP-NAME-0e5d",
        "CANARY-VOCABULARY-b8a1",
    ]

    @Test func exportedReportContainsNoCanarySecrets() async throws {
        let buffer = DiagnosticsBuffer()
        let permissions = FakePermissions(statuses: [.microphone: .granted, .accessibility: .granted])
        let preferences = FakePreferences(audioInput: .device(id: canaries[0]))
        let source = FakeAudioSource(fallsBack: true)
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "LemmeTypeTests-DiagnosticsPrivacyTests-\(UUID().uuidString)", isDirectory: true))
        let capture = AudioCaptureService(
            source: source, storage: storage, permissions: permissions, diagnostics: buffer)
        let coordinator = RecordingCoordinator(
            capture: capture,
            processor: RecordingSpy(),
            feedback: SilentFeedback(),
            preferences: preferences,
            diagnostics: buffer
        )
        let registrar = FakeHotKeyRegistrar()
        let target = ActivationTarget(
            processIdentifier: 1, bundleIdentifier: "com.example.\(canaries[3])", applicationName: canaries[3],
            focusedElement: nil)
        let capturer = try capturerWithContext(target: target)
        let activation = ActivationController(
            registrar: registrar,
            targetCapturer: capturer,
            shortcut: .defaultDictation,
            mode: .toggle,
            diagnostics: buffer
        )
        activation.onCommand = { coordinator.handle($0) }
        activation.activate()

        try await driveSessions(registrar: registrar, source: source, coordinator: coordinator)
        // Attempts to smuggle text in through identifiers are redacted.
        buffer.record(.lifecycle, "test.attempt", ["field": .id(canaries[1]), "clipboard": .identifier(canaries[2])])
        buffer.record(.lifecycle, "test.attempt", ["vocabulary": .id(canaries[4])])

        let shortcutModel = ShortcutSettingsModel(controller: activation, preferences: preferences)
        let model = DiagnosticsModel(
            buffer: buffer,
            permissions: PermissionsModel(checker: permissions, requester: permissions, diagnostics: buffer),
            shortcut: shortcutModel,
            buildInfo: BuildInfo(version: "1.0", build: "7")
        )
        model.preparePreview()
        let text = try #require(model.preview)

        for canary in canaries {
            #expect(!text.contains(canary), "\(canary) leaked into diagnostics")
        }
        #expect(text.contains("\"recorder.state\""))
        #expect(text.contains("audio.device-disconnected"))
        #expect(text.contains("activation.start"))
        #expect(text.contains("\"captured\""))
    }

    /// E3-S2: surrounding text captured at activation carries a canary too.
    private func capturerWithContext(target: ActivationTarget) throws -> FakeTargetCapturer {
        let capturer = FakeTargetCapturer(target: target)
        let context = try #require(
            CursorContext(
                precedingText: canaries[1], followingText: canaries[1],
                selection: TextSelection(location: 22, length: 0)))
        capturer.contexts[.formatting] = .captured(context, purpose: .formatting)
        return capturer
    }

    /// One completed session and one that fails on device loss.
    private func driveSessions(
        registrar: FakeHotKeyRegistrar,
        source: FakeAudioSource,
        coordinator: RecordingCoordinator
    ) async throws {
        // A session whose audio metadata, target, and surrounding text carry canaries.
        registrar.send(.pressed, .defaultDictation, at: 0)
        await coordinator.settle()
        source.emitTone(seconds: 0.2)
        registrar.send(.released, .defaultDictation, at: 0.1)
        registrar.send(.pressed, .defaultDictation, at: 1)
        await coordinator.settle()
        // A failing session too.
        registrar.send(.released, .defaultDictation, at: 1.1)
        registrar.send(.pressed, .defaultDictation, at: 2)
        await coordinator.settle()
        source.emit(.deviceLost)
        try await Task.sleep(for: .milliseconds(30))
        await coordinator.settle()
    }

    @Test func reportHasTheRequiredFields() throws {
        let buffer = DiagnosticsBuffer()
        buffer.record(.lifecycle, "app.launched", ["mode": .id("live")])
        let permissions = FakePermissions(statuses: [.microphone: .denied])
        let model = DiagnosticsModel(
            buffer: buffer,
            permissions: PermissionsModel(checker: permissions, requester: permissions),
            shortcut: ShortcutSettingsModel(controller: StubShortcutController(), preferences: FakePreferences()),
            buildInfo: BuildInfo(version: "1.2.3", build: "45"),
            osVersion: "Version 27.0",
            hardwareModel: "Mac16,1"
        )

        let report = model.makeReport()

        #expect(report.appVersion == "1.2.3")
        #expect(report.appBuild == "45")
        #expect(report.osVersion == "Version 27.0")
        #expect(report.hardwareModel == "Mac16,1")
        #expect(report.permissions == ["microphone": "denied", "accessibility": "notGranted"])
        #expect(report.events.map(\.name) == ["app.launched"])
    }

    @Test func savingWritesExactlyThePreview() throws {
        let model = DiagnosticsModel(
            buffer: DiagnosticsBuffer(),
            permissions: PermissionsModel(checker: FakePermissions(), requester: FakePermissions()),
            shortcut: ShortcutSettingsModel(controller: StubShortcutController(), preferences: FakePreferences()),
            buildInfo: BuildInfo(version: "1", build: "1")
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        model.save(to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))  // nothing without a preview

        model.preparePreview()
        let preview = try #require(model.preview)
        model.save(to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == preview)
        #expect(model.preview == nil)
    }
}

/// Every expected failure maps to a concise message and a recovery action.
@MainActor
struct RecoveryGuidanceTests {
    @Test(arguments: [
        AudioCaptureError.microphonePermissionMissing, .noInputDevice, .deviceDisconnected, .interrupted,
        .engineFailure(code: 1), .storageFailure, .alreadyCapturing, .notCapturing,
    ])
    func audioFailuresHaveAMessageAndAnAction(error: AudioCaptureError) async {
        let source = FakeAudioSource(startError: error)
        let coordinator = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source,
                storage: AudioSessionStorage(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-RecoveryGuidance-\(UUID().uuidString)")),
                permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: RecordingSpy(),
            feedback: SilentFeedback(),
            preferences: FakePreferences()
        )

        coordinator.requestStart(target: nil)
        await coordinator.settle()

        #expect(coordinator.failure == error)
        #expect(!error.userMessage.isEmpty)
        #expect(error.userMessage.count < 120)
        #expect(coordinator.recoveryAction != nil)
    }

    @Test func shortcutFailuresHaveAMessageAndCanChooseAnother() {
        let errors: [ShortcutError] = [
            .invalid(.missingModifier), .invalid(.modifierOnly), .invalid(.reservedForCancel),
            .invalid(.systemShortcut), .unavailable, .registrationFailed(code: -9878),
        ]
        for error in errors {
            let message = ShortcutSettingsModel.message(for: error)
            #expect(!message.isEmpty && message.count < 120)
        }
        // Recovery: recording a different shortcut is always available (see ShortcutSettingsModelTests).
    }

    @Test func errorIdentifiersAreStableAndSafe() {
        let identifiers =
            [
                AudioCaptureError.microphonePermissionMissing, .noInputDevice, .deviceDisconnected, .interrupted,
                .alreadyCapturing, .notCapturing, .engineFailure(code: 1), .storageFailure,
            ].map(\.identifier)
            + [ShortcutError.unavailable, .invalid(.missingModifier), .registrationFailed(code: 1)].map(\.identifier)
            + [LoginItemError().identifier]
        #expect(identifiers.allSatisfy(DiagnosticValue.isSafeIdentifier))
        #expect(identifiers.contains("audio.device-disconnected"))
    }
}

@MainActor
private final class SilentFeedback: RecordingFeedback {
    func announce(_ message: String) {}
    func play(_ sound: FeedbackSound) {}
}

@MainActor
private final class StubShortcutController: DictationShortcutControlling {
    let shortcut = KeyboardShortcut.defaultDictation
    let mode = ActivationMode.pushToTalk
    let registrationError: ShortcutError? = nil
    func activate() {}
    func suspend() {}
    func change(to shortcut: KeyboardShortcut) throws(ShortcutError) {}
    func change(to mode: ActivationMode) {}
    let editShortcut: KeyboardShortcut? = .defaultVoiceEdit
    let editRegistrationError: ShortcutError? = nil
    func changeEdit(to shortcut: KeyboardShortcut?) throws(ShortcutError) {}
}
