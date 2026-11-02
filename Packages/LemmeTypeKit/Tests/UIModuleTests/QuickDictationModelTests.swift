import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E8-S6, E8-S7: the Quick Dictation screen over the shared recorder.
@MainActor
struct QuickDictationModelTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let copier = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-QuickDictation-\(UUID().uuidString)", isDirectory: true))

    private func makeModel(
        microphone: PermissionStatus = .granted,
        inbox: LaunchRequestInbox? = nil,
        lifetime: CopiedTextLifetime = .twoMinutes
    ) -> QuickDictationModel {
        let recorder = RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: microphone])),
            processor: processor, feedback: feedback, preferences: FakePreferences(),
            textCopier: copier, finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50))
        return QuickDictationModel(
            recorder: recorder, feedback: feedback, microphoneStatus: { microphone },
            requestMicrophone: { .granted }, openSettings: {}, lifetime: { lifetime }, launchRequests: inbox)
    }

    private func review(_ text: String) -> DictationOutcome {
        .needsAttention(.reviewText, engine: .whisper, alternatives: [], transcript: text)
    }

    private func dictate(_ model: QuickDictationModel) async {
        model.start()
        await model.recorder.settle()
        source.emitTone(seconds: 0.3)
        model.stop()
        await model.recorder.settle()
    }

    @Test func aFinishedDictationIsShownForReviewAndNothingIsCopiedYet() async {
        processor.script([review("Ship it Friday")])
        let model = makeModel()

        await dictate(model)

        #expect(model.screen == .review(text: "Ship it Friday"))
        #expect(copier.copied.isEmpty)
        #expect(model.copiedFor == nil)
    }

    @Test func copyPutsExactlyTheReviewedTextOnTheClipboardOnceAndConfirms() async {
        processor.script([review("Ship it Friday")])
        let model = makeModel(lifetime: .tenMinutes)
        await dictate(model)

        await model.copy()

        #expect(copier.copied == ["Ship it Friday"])
        #expect(model.copiedFor == .tenMinutes)
        #expect(feedback.announcements.contains(QuickDictationModel.copiedMessage(for: .tenMinutes)))
        #expect(feedback.sounds.last == .stop)
    }

    @Test func discardCopiesNothingAndReturnsToReady() async throws {
        processor.script([review("Private words")])
        let model = makeModel()
        await dictate(model)

        model.discard()
        await model.recorder.settle()

        #expect(copier.copied.isEmpty)
        #expect(model.screen == .ready)
    }

    @Test func dictatingAgainDropsTheResultAndRecordsAgain() async {
        processor.script([review("First try")])
        let model = makeModel()
        await dictate(model)

        model.dictateAgain()
        await model.recorder.settle()

        #expect(model.screen == .recording)
        #expect(copier.copied.isEmpty)
        model.cancel()
        await model.recorder.settle()
    }

    @Test func theFirstStartExplainsTheMicrophoneBeforeAskingTheSystem() async {
        let model = makeModel(microphone: .notRequested)

        model.start()
        await model.recorder.settle()

        #expect(model.isExplainingMicrophone)
        #expect(model.screen == .ready)
        #expect(!source.isRunning)

        model.cancelExplanation()
        #expect(!model.isExplainingMicrophone)
        #expect(model.screen == .ready)
    }

    @Test func deniedMicrophoneNeverRecordsAndOffersSettings() async {
        let model = makeModel(microphone: .denied)

        model.start()
        await model.recorder.settle()

        #expect(model.screen == .failed(.microphonePermissionMissing))
        #expect(!source.isRunning)
    }

    @Test func aShortcutRequestStartsOnceAndAnExpiredOneStartsNothing() async {
        let now = TestNow()
        let inbox = LaunchRequestInbox(lifetime: 10, now: { now.date })
        let model = makeModel(inbox: inbox)

        inbox.post()
        model.startIfRequestedByShortcut()
        await model.recorder.settle()
        #expect(model.screen == .recording)
        model.cancel()
        await model.recorder.settle()

        model.startIfRequestedByShortcut()  // already used
        await model.recorder.settle()
        #expect(model.screen == .ready)

        inbox.post()
        now.advance(by: 60)
        model.startIfRequestedByShortcut()  // expired
        await model.recorder.settle()
        #expect(model.screen == .ready)
        #expect(!source.isRunning)
    }

    @Test func aShortcutRequestWithoutMicrophoneAccessExplainsInsteadOfRecording() async {
        let inbox = LaunchRequestInbox()
        let model = makeModel(microphone: .notRequested, inbox: inbox)

        inbox.post()
        model.startIfRequestedByShortcut()
        await model.recorder.settle()

        #expect(model.isExplainingMicrophone)
        #expect(!source.isRunning)
    }

    @Test func aCancelledOrFailedDictationNeverTouchesTheClipboard() async {
        let model = makeModel()
        model.start()
        await model.recorder.settle()
        model.cancel()
        await model.recorder.settle()

        #expect(copier.copied.isEmpty)
        #expect(model.screen == .ready)
    }
}
