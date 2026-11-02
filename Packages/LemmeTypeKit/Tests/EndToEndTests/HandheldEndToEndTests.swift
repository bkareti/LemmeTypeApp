import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E8-S2: the iPhone and iPad dictation path with fakes only at the operating-system
/// edges (audio session, microphone permission, pasteboard, app lifecycle). Real
/// recording service, coordinator, pipeline, and Quick Dictation model. Real devices,
/// real speech, and other apps are on the manual checklist (docs/testing/ios-feasibility.md).
@MainActor
@Suite(.serialized)
struct HandheldEndToEndTests {
    static let canary = "CANARY-SPOKEN-77c2"

    /// The pasteboard: records every write, so a test can see exactly what was copied and for how long.
    @MainActor
    final class FakePasteboardWriter: ExpiringPasteboardWriting {
        private(set) var writes: [(text: String, lifetime: TimeInterval)] = []
        func write(_ text: String, lifetime: TimeInterval) { writes.append((text, lifetime)) }
    }

    @MainActor
    final class Harness {
        let source = FakeAudioSource()
        let storage = AudioSessionStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LemmeTypeTests-EndToEndHandheld-\(UUID().uuidString)", isDirectory: true))
        let engine: FakeRecognitionEngine
        let pasteboard = FakePasteboardWriter()
        let diagnostics = RecordingDiagnostics()
        let feedback = SilentFeedback()
        let preferences: FakePreferences
        let coordinator: RecordingCoordinator
        let model: QuickDictationModel

        init(
            language: String = "en-US", output: SpeechOutput = .original, mode: DictationModeID = .exact,
            microphone: PermissionStatus = .granted, script: FakeRecognitionEngine.Script = .init(text: canary),
            availability: EngineAvailability = .ready, limits: RecordingLimits = .handheld
        ) {
            engine = FakeRecognitionEngine(
                id: .whisper, availability: availability, script: script, supportedLanguages: ["en", "hi", "te"],
                assets: .downloadable(.whisperBaseEnglish), capabilities: [.languageDetection],
                tasks: [.transcribe, .translateToEnglish])
            preferences = FakePreferences(dictationLanguage: language)
            preferences.speechOutput = output
            preferences.dictationMode = mode
            let permissions = FakePermissions(statuses: [.microphone: microphone])
            let copier = ExpiringTextCopier(writer: pasteboard, lifetime: { .twoMinutes })
            coordinator = RecordingCoordinator(
                capture: AudioCaptureService(
                    source: source, storage: storage, permissions: permissions, diagnostics: diagnostics),
                processor: TranscriptionPipeline(
                    engines: [engine], delivery: NoTargetDelivery(), copier: copier, diagnostics: diagnostics,
                    hardware: HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 << 30, deviceClass: .iPhone),
                    reviewsEveryResult: true),
                feedback: feedback, preferences: preferences, textCopier: copier,
                finishedDisplay: .seconds(60), failureDisplay: .seconds(60), attentionDisplay: .seconds(60),
                diagnostics: diagnostics, limits: limits)
            model = QuickDictationModel(
                recorder: coordinator, feedback: feedback, microphoneStatus: { permissions.status(for: .microphone) },
                requestMicrophone: { await permissions.requestMicrophoneAccess() }, openSettings: {},
                lifetime: { .twoMinutes })
        }

        func dictate(seconds: Double = 0.4) async {
            model.start()
            await coordinator.settle()
            source.emitTone(seconds: seconds)
            model.stop()
            await coordinator.settle()
        }

        var leftoverAudio: [URL] {
            (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
        }

        var diagnosticsText: String { String(describing: diagnostics.events) }

        func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }
    }

    // MARK: Quick Dictation with each built-in mode

    @Test(arguments: [DictationModeID.exact, .clean, .message])
    func dictationIsReviewedInEachBuiltInModeAndCopiedOnlyOnRequest(mode: DictationModeID) async throws {
        let spoken = "  um so ship   it on wednesday  "
        let harness = Harness(mode: mode, script: .init(text: spoken))
        defer { harness.cleanUp() }

        await harness.dictate()

        let reviewed = try #require(harness.coordinator.reviewText)
        #expect(harness.model.screen == .review(text: reviewed))
        #expect(reviewed.contains("ship"))
        if mode == .exact { #expect(reviewed == "um so ship it on wednesday") }
        if mode == .clean { #expect(reviewed != "um so ship it on wednesday") }
        #expect(harness.pasteboard.writes.isEmpty, "nothing is copied before Copy")
        #expect(harness.leftoverAudio.isEmpty, "the audio is gone once the text is final")

        await harness.model.copy()

        #expect(harness.pasteboard.writes.map(\.text) == [reviewed])
        #expect(harness.pasteboard.writes.first?.lifetime == 120)
        #expect(harness.model.copiedFor == .twoMinutes)
        #expect(harness.model.screen == .ready)
    }

    @Test func aTranslationIsReviewedAndOnlyCopiedWhenTheUserChoosesCopy() async {
        let harness = Harness(
            language: "hi", output: .english, script: .init(text: "the meeting is at three tomorrow"))
        defer { harness.cleanUp() }

        await harness.dictate()

        #expect(harness.model.screen == .review(text: "the meeting is at three tomorrow"))
        #expect(harness.model.reviewKind == .translation)
        #expect(harness.engine.lastTask == .translateToEnglish)
        #expect(harness.pasteboard.writes.isEmpty)

        await harness.model.copy()
        #expect(harness.pasteboard.writes.map(\.text) == ["the meeting is at three tomorrow"])
    }

    // MARK: Cancellation, limits, and the app leaving the screen

    @Test func cancellingLeavesTheClipboardUntouchedAndDeletesTheAudio() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.model.start()
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.3)

        harness.model.cancel()
        await harness.coordinator.settle()

        #expect(harness.model.screen == .ready)
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.leftoverAudio.isEmpty)
        #expect(!harness.source.isRunning)
    }

    @Test func discardingAReviewLeavesTheClipboardUntouched() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        await harness.dictate()

        harness.model.discard()
        await harness.coordinator.settle()

        #expect(harness.model.screen == .ready)
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.coordinator.reviewText == nil)
    }

    @Test func theTimeLimitStopsTheRecordingAndTheTextIsStillReviewed() async throws {
        let harness = Harness(limits: RecordingLimits(maximumDuration: .milliseconds(100)))
        defer { harness.cleanUp() }
        harness.model.start()
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.3)

        try await Task.sleep(for: .milliseconds(300))
        await harness.coordinator.settle()

        #expect(!harness.source.isRunning)
        #expect(harness.model.screen == .review(text: Self.canary))
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test func theAppLeavingTheForegroundEndsTheRecordingWithoutLosingTheDictation() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.model.start()
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.3)

        harness.coordinator.stopForSystemReason()
        await harness.coordinator.settle()

        #expect(!harness.source.isRunning)
        #expect(harness.model.screen == .review(text: Self.canary))
    }

    @Test func anInterruptionEndsTheSessionAndNothingIsCopied() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.model.start()
        await harness.coordinator.settle()
        harness.source.emitTone(seconds: 0.2)

        harness.source.emit(.interrupted)
        // The event crosses two async streams before the coordinator sees it.
        for _ in 0..<100 where harness.model.screen != .failed(.interrupted) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await harness.coordinator.settle()

        #expect(harness.model.screen == .failed(.interrupted))
        #expect(!harness.source.isRunning)
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.leftoverAudio.isEmpty)
    }

    // MARK: Missing model, revoked permission

    @Test func aMissingModelIsReportedAndNothingIsCopied() async {
        let harness = Harness(availability: .assetsMissing)
        defer { harness.cleanUp() }

        await harness.dictate()

        guard case .attention(let issue) = harness.model.screen else {
            Issue.record("expected the model problem to be shown, got \(harness.model.screen)")
            return
        }
        #expect(issue.identifier.hasPrefix("engine."))
        #expect(harness.pasteboard.writes.isEmpty)
        harness.model.discard()
        await harness.coordinator.settle()
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func aSilentRecordingTellsTheUserToCheckTheMicrophoneAndCopiesNothing() async {
        let harness = Harness(script: .init(error: .silentAudio))
        defer { harness.cleanUp() }

        await harness.dictate()

        #expect(harness.model.screen == .attention(.recognitionFailed(.silentAudio)))
        #expect(harness.model.screen != .attention(.recognitionFailed(.noSpeechDetected)))
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.diagnosticsText.contains("recognition.silent-audio"))
        harness.model.discard()
        await harness.coordinator.settle()
        #expect(harness.leftoverAudio.isEmpty)
    }

    @Test func aDeniedMicrophoneNeverRecords() async {
        let harness = Harness(microphone: .denied)
        defer { harness.cleanUp() }

        harness.model.start()
        await harness.coordinator.settle()

        #expect(harness.model.screen == .failed(.microphonePermissionMissing))
        #expect(harness.source.startCount == 0)
        #expect(harness.leftoverAudio.isEmpty)
    }

    // MARK: Privacy canaries

    @Test func spokenWordsReachOnlyTheScreenAndTheExplicitCopy() async {
        let harness = Harness()
        defer { harness.cleanUp() }

        await harness.dictate()
        await harness.model.copy()

        #expect(harness.pasteboard.writes.map(\.text) == [Self.canary], "the words go to the clipboard once, on Copy")
        #expect(!harness.diagnosticsText.contains(Self.canary), "never in diagnostics")
        #expect(!harness.diagnosticsText.contains("meeting"))
        #expect(harness.leftoverAudio.isEmpty)
        #expect(harness.coordinator.reviewText == nil, "the text is dropped from memory after Copy")
    }
}
