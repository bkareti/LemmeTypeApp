import Domain
import Foundation
import Observation
import Support

/// Runs dictation sessions: turns shortcut, menu, and overlay commands into
/// recorder transitions and capture calls, one at a time and in order. The
/// overlay and menu observe ``state``.
@MainActor
@Observable
public final class RecordingCoordinator {
    public enum RecoveryAction: Equatable, Sendable {
        case openPermissions
        case openAudioSettings
        case tryAgain
    }

    public private(set) var state: RecorderState = .idle
    /// Current meter value while recording; 0 otherwise.
    public private(set) var level: Float = 0
    public private(set) var recordingStartedAt: Date?

    /// Called when a session ends for any reason, so the shortcut can re-arm.
    public var onSessionEnded: @MainActor () -> Void = {}
    /// Opens a settings pane for a recovery action.
    public var onOpenSettings: @MainActor (SettingsNavigation.Pane) -> Void = { _ in }

    private var machine = RecorderStateMachine()
    public let capture: any AudioCapturing
    private let consumer: any RecordingConsumer
    private let feedback: any RecordingFeedback
    private let preferences: any AppPreferences
    private let finishedDisplay: Duration
    private let failureDisplay: Duration
    private let diagnostics: any DiagnosticsRecording

    private var queue: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var target: ActivationTarget?

    public init(
        capture: any AudioCapturing,
        consumer: any RecordingConsumer,
        feedback: any RecordingFeedback,
        preferences: any AppPreferences,
        finishedDisplay: Duration = .seconds(1.5),
        failureDisplay: Duration = .seconds(8),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.diagnostics = diagnostics
        self.capture = capture
        self.consumer = consumer
        self.feedback = feedback
        self.preferences = preferences
        self.finishedDisplay = finishedDisplay
        self.failureDisplay = failureDisplay
    }

    public var failure: AudioCaptureError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    public var recoveryAction: RecoveryAction? {
        switch failure {
        case .microphonePermissionMissing: .openPermissions
        case .noInputDevice, .deviceDisconnected: .openAudioSettings
        case .interrupted, .engineFailure, .storageFailure, .alreadyCapturing, .notCapturing: .tryAgain
        case nil: nil
        }
    }

    // MARK: Commands

    public func handle(_ command: ActivationCommand) {
        switch command {
        case .start(let target): requestStart(target: target)
        case .stop: requestStop()
        case .cancel: requestCancel()
        }
    }

    public func requestStart(target: ActivationTarget?) {
        enqueue { await $0.start(target: target) }
    }

    public func requestStop() {
        enqueue { await $0.stop() }
    }

    public func requestCancel() {
        enqueue { await $0.cancel() }
    }

    /// Hides a finished session's overlay.
    public func dismiss() {
        dismissTask?.cancel()
        if machine.handle(.reset) {
            sync()
        }
    }

    public func perform(_ action: RecoveryAction) {
        dismiss()
        switch action {
        case .openPermissions: onOpenSettings(.permissions)
        case .openAudioSettings: onOpenSettings(.audio)
        case .tryAgain: requestStart(target: nil)
        }
    }

    /// Waits for every queued command. For tests and app termination.
    public func settle() async {
        while let current = queue {
            await current.value
            if queue == current { break }
        }
    }

    // MARK: Transitions

    private func enqueue(_ operation: @escaping @MainActor (RecordingCoordinator) async -> Void) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func start(target: ActivationTarget?) async {
        guard machine.handle(.activate) else { return }
        dismissTask?.cancel()
        sync()
        self.target = target
        do {
            let events = try await capture.start(input: preferences.audioInput)
            guard machine.handle(.captureStarted) else {
                await capture.cancel()
                return
            }
            recordingStartedAt = Date()
            sync()
            feedback.play(.start)
            feedback.announce(String(localized: "Recording started", bundle: .module))
            eventsTask = Task { [weak self] in
                for await event in events {
                    self?.receive(event)
                }
            }
        } catch {
            await fail(error)
        }
    }

    private func receive(_ event: AudioCaptureEvent) {
        switch event {
        case .level(let value) where state == .recording:
            level = value
        case .failed(let error):
            enqueue { await $0.fail(error) }
        case .level, .audio, .fellBackToSystemDefault:
            break
        }
    }

    private func stop() async {
        guard machine.handle(.stopRequested) else { return }
        level = 0
        sync()
        do {
            let recording = try await capture.stop()
            guard machine.handle(.captureFinished) else { return }
            sync()
            feedback.play(.stop)
            feedback.announce(String(localized: "Recording stopped", bundle: .module))
            try await consumer.consume(recording, target: target)
            guard machine.handle(.processingFinished) else { return }
            sync()
            finishSession(displayFor: finishedDisplay)
        } catch {
            await fail(error)
        }
    }

    private func cancel() async {
        guard machine.handle(.cancel) else { return }
        await capture.cancel()
        level = 0
        sync()
        feedback.announce(String(localized: "Recording cancelled", bundle: .module))
        finishSession(displayFor: finishedDisplay)
    }

    private func fail(_ error: AudioCaptureError) async {
        guard machine.handle(.fail(error)) else { return }
        await capture.cancel()  // releases the microphone and deletes partial audio
        level = 0
        sync()
        feedback.announce(String(localized: "Recording failed. \(error.userMessage)", bundle: .module))
        Log.audio.error("Session failed: \(error.identifier, privacy: .public)")
        finishSession(displayFor: failureDisplay)
    }

    private func finishSession(displayFor duration: Duration) {
        target = nil
        recordingStartedAt = nil
        eventsTask?.cancel()
        eventsTask = nil
        onSessionEnded()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func sync() {
        guard state != machine.state else { return }
        state = machine.state
        diagnostics.record(.recorder, "recorder.state", ["state": .id(Self.diagnosticName(for: state))])
    }

    static func diagnosticName(for state: RecorderState) -> String {
        switch state {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .stopping: "stopping"
        case .processing: "processing"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed(let error): "failed.\(error.identifier)"
        }
    }
}
