import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// Dictation sessions after recording: decisions, retries, and isolation (E2-S5).
@MainActor
struct RecordingSessionTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let processor = RecordingSpy()
    private let preferences = FakePreferences(writingMode: .clean)
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-RecordingSessionTests-\(UUID().uuidString)", isDirectory: true))

    private var leftoverFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func makeCoordinator(copier: FakeTextDelivery, authorizer: FakeSpeechAuthorizer? = nil)
        -> RecordingCoordinator
    {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor,
            feedback: feedback,
            preferences: preferences,
            speechAuthorizer: authorizer,
            textCopier: copier,
            finishedDisplay: .milliseconds(50),
            failureDisplay: .milliseconds(50),
            attentionDisplay: .seconds(60)
        )
    }

    private func record(_ coordinator: RecordingCoordinator) async {
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        await coordinator.settle()
    }

    private static let failed = DictationOutcome.needsAttention(
        .recognitionFailed(.engineFailure(code: 3)), engine: .appleSpeech, alternatives: [.whisper], transcript: nil)

    @Test func failureKeepsTheRecordingUntilTheUserDecides() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([Self.failed])

        await record(coordinator)

        #expect(coordinator.state == .needsAttention(.recognitionFailed(.engineFailure(code: 3))))
        #expect(coordinator.attentionActions == [.retry, .useEngine(.whisper), .saveAudio, .discard])
        #expect(coordinator.hasActiveSession)
        #expect(leftoverFiles.count == 1)

        coordinator.perform(.discard)
        await coordinator.settle()
        #expect(coordinator.state == .idle)
        #expect(leftoverFiles.isEmpty)
    }

    @Test func retryReusesTheSameRecordingAndEngine() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([Self.failed])
        await record(coordinator)

        coordinator.perform(.retry)
        await coordinator.settle()

        #expect(coordinator.state == .completed)
        #expect(processor.consumed.count == 2)
        #expect(processor.consumed[0].fileURL == processor.consumed[1].fileURL)
        #expect(processor.engines == [nil, .appleSpeech])
        #expect(leftoverFiles.isEmpty)
    }

    @Test func choosingAnotherEngineRetriesWithIt() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([Self.failed])
        await record(coordinator)

        coordinator.perform(.useEngine(.whisper))
        await coordinator.settle()

        #expect(processor.engines.last == .whisper)
        #expect(coordinator.state == .completed)
    }

    @Test func savingAudioHandsTheFileToTheAppAndKeepsTheDecisionOpen() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([Self.failed])
        var saved: [URL] = []
        coordinator.onSaveAudio = { saved.append($0) }
        await record(coordinator)

        coordinator.perform(.saveAudio)
        await coordinator.settle()

        #expect(saved == processor.consumed.map(\.fileURL))
        #expect(coordinator.attention != nil)
        coordinator.perform(.discard)
        await coordinator.settle()
        #expect(leftoverFiles.isEmpty)
    }

    @Test func copyTextFinishesTheSessionAndDeletesAudio() async {
        let copier = FakeTextDelivery()
        let coordinator = makeCoordinator(copier: copier)
        processor.script([
            .needsAttention(
                .deliveryFailed(.targetChanged), engine: .appleSpeech, alternatives: [], transcript: "hello")
        ])
        await record(coordinator)
        #expect(coordinator.attentionActions == [.copyText, .retryDelivery, .discard])

        coordinator.perform(.copyText)
        await coordinator.settle()

        #expect(copier.copied == ["hello"])
        #expect(coordinator.state == .completed)
        #expect(coordinator.lastDelivery == .copied)
        #expect(leftoverFiles.isEmpty)
    }

    @Test func retryDeliveryRedeliversTheKeptTranscript() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([
            .needsAttention(
                .deliveryFailed(.targetChanged), engine: .appleSpeech, alternatives: [], transcript: "hello")
        ])
        await record(coordinator)

        coordinator.perform(.retryDelivery)
        await coordinator.settle()

        #expect(processor.deliveries == ["hello"])
        #expect(coordinator.state == .completed)
        #expect(coordinator.lastDelivery == .paste)
    }

    @Test func allowSpeechRecognitionPromptsOnceThenOpensSettings() async {
        let authorizer = FakeSpeechAuthorizer(status: .notRequested, answer: .denied)
        let coordinator = makeCoordinator(copier: FakeTextDelivery(), authorizer: authorizer)
        processor.script([
            .needsAttention(
                .recognitionFailed(.permissionDenied), engine: .appleSpeech, alternatives: [], transcript: nil)
        ])
        await record(coordinator)
        #expect(coordinator.attentionActions.first == .allowSpeechRecognition)

        coordinator.perform(.allowSpeechRecognition)
        coordinator.perform(.allowSpeechRecognition)
        await coordinator.settle()

        #expect(authorizer.requestCount == 1)
        #expect(authorizer.openedSettingsCount == 1)
        #expect(coordinator.attention != nil)
        #expect(leftoverFiles.count == 1)
        coordinator.perform(.discard)
        await coordinator.settle()
    }

    @Test func cancelDuringProcessingDeletesAudioAndIgnoresTheLateResult() async throws {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([.delivered(.accessibility)], delay: .milliseconds(300))
        coordinator.handle(.start(nil))
        await coordinator.settle()
        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        try await Task.sleep(for: .milliseconds(50))
        #expect(coordinator.state == .processing)

        coordinator.requestCancel()
        await coordinator.settle()
        try await Task.sleep(for: .milliseconds(400))

        #expect(coordinator.state == .cancelled || coordinator.state == .idle)
        #expect(coordinator.lastDelivery == nil)
        #expect(leftoverFiles.isEmpty)
    }

    @Test func aNewRecordingReplacesASessionWaitingForADecision() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        processor.script([Self.failed])
        await record(coordinator)
        let kept = processor.consumed[0].fileURL

        await record(coordinator)

        #expect(!FileManager.default.fileExists(atPath: kept.path))
        #expect(coordinator.state == .completed)
    }

    @Test func sessionsCarryTheWritingModeAndLanguageAtStart() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        await record(coordinator)
        #expect(processor.modes == [.clean])
        #expect(coordinator.state == .completed)
    }

    @Test func theActiveWritingModeIsShownAndStoredWithTheNextSession() async {
        let coordinator = makeCoordinator(copier: FakeTextDelivery())
        #expect(coordinator.writingMode == .clean)
        #expect(coordinator.writingMode.displayName == "Clean Writing")

        coordinator.writingMode = .exact
        await record(coordinator)

        #expect(preferences.writingMode == .exact)
        #expect(processor.modes == [.exact])
    }
}
