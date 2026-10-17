import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E3-S5 and E3-S6: voice-editing sessions in the recorder, and the context
/// status the overlay shows.
@MainActor
struct RecordingCoordinatorEditingTests {
    private let source = FakeAudioSource()
    private let feedback = FakeFeedback()
    private let delivery = FakeTextDelivery()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-RecordingEditing-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(rewriter: FakeTextRewriter) -> RecordingCoordinator {
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "shout it"))],
            delivery: delivery, rewriter: rewriter)
        return RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: pipeline, feedback: feedback, preferences: FakePreferences(), textCopier: delivery,
            finishedDisplay: .milliseconds(50), failureDisplay: .seconds(60), attentionDisplay: .seconds(60))
    }

    private func target(selected: String?) throws -> ActivationTarget {
        guard let selected else {
            return FakeTargetCapturer.textEdit.with(context: .blocked(.noSelection, purpose: .editing))
        }
        let context = try #require(
            CursorContext(
                precedingText: "", followingText: "", selection: TextSelection(location: 0, length: selected.count),
                selectedText: selected))
        return FakeTargetCapturer.textEdit.with(context: .captured(context, purpose: .editing))
    }

    @Test func editingSessionRewritesTheSelection() async throws {
        let coordinator = makeCoordinator(rewriter: FakeTextRewriter())

        coordinator.handle(.startEditing(try target(selected: "quiet words")))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        #expect(coordinator.activePurpose == .editing)
        #expect(feedback.announcements.last == "Editing selection. Say what to change.")
        source.emitTone(seconds: 0.3)
        coordinator.handle(.stop)
        await coordinator.settle()

        #expect(coordinator.state == .completed)
        #expect(delivery.delivered == ["QUIET WORDS"])
    }

    @Test func blockedEditNeverRecords() async throws {
        let coordinator = makeCoordinator(rewriter: FakeTextRewriter())

        coordinator.handle(.startEditing(try target(selected: nil)))
        await coordinator.settle()

        #expect(coordinator.state == .needsAttention(.editingUnavailable(.noSelection)))
        #expect(coordinator.attentionActions == [.discard])
        #expect(source.startCount == 0)
        #expect(delivery.delivered.isEmpty)
        coordinator.perform(.discard)
        await coordinator.settle()
        #expect(coordinator.state == .idle)
    }

    @Test func unavailableModelIsReportedBeforeRecording() async throws {
        let coordinator = makeCoordinator(rewriter: FakeTextRewriter(availability: .notEnabled))

        coordinator.handle(.startEditing(try target(selected: "text")))
        await coordinator.settle()

        #expect(coordinator.state == .needsAttention(.rewriterUnavailable(.notEnabled)))
        #expect(coordinator.attentionActions == [.openContextSettings, .discard])
        #expect(source.startCount == 0)
    }

    @Test func openContextSettingsGoesToTheContextPane() async throws {
        let coordinator = makeCoordinator(rewriter: FakeTextRewriter(availability: .notEnabled))
        var opened: [SettingsNavigation.Pane] = []
        coordinator.onOpenSettings = { opened.append($0) }

        coordinator.handle(.startEditing(try target(selected: "text")))
        await coordinator.settle()
        coordinator.perform(.openContextSettings)
        await coordinator.settle()

        #expect(opened == [.context])
    }

    @Test func reportsContextStatus() async throws {
        let coordinator = makeCoordinator(rewriter: FakeTextRewriter())
        let context = try #require(
            CursorContext(precedingText: "Hi", followingText: "", selection: TextSelection(location: 2, length: 0)))

        coordinator.handle(.start(FakeTargetCapturer.textEdit.with(context: .captured(context, purpose: .formatting))))
        await coordinator.settle()

        #expect(coordinator.activeContext?.statusText == "Using text near the cursor")
        #expect(feedback.announcements.last == "Recording started. Exact Dictation. Using text near the cursor")
        coordinator.handle(.cancel)
        await coordinator.settle()
        #expect(coordinator.activeContext == nil)

        #expect(ContextCapture.blocked(.excludedApp, purpose: .formatting).statusText == "Context off for this app")
        #expect(ContextCapture.blocked(.disabled, purpose: .formatting).statusText == nil)
        #expect(ContextCapture.notRequested.statusText == nil)
    }
}
