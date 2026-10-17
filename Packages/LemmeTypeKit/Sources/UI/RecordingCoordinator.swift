import Domain
import Foundation
import Observation
import Support

/// Runs dictation sessions: turns shortcut, menu, and overlay commands into
/// recorder transitions, capture calls, and processing, one at a time and in
/// order. The overlay and menu observe ``state``.
///
/// Each finished recording becomes one ``DictationSession`` that this
/// coordinator owns until it is delivered, cancelled, or discarded; results
/// from any other session are ignored (see `RecordingCoordinator+Processing`).
@MainActor
@Observable
public final class RecordingCoordinator {
    public enum RecoveryAction: Equatable, Sendable {
        case openPermissions
        case openAudioSettings
        case tryAgain
    }

    public internal(set) var state: RecorderState = .idle
    /// Current meter value while recording; 0 otherwise.
    public private(set) var level: Float = 0
    public private(set) var recordingStartedAt: Date?
    /// What processing is doing, while ``state`` is `.processing`.
    public internal(set) var processingPhase: ProcessingPhase?
    /// Recognition progress (0...1) when the engine reports it.
    public internal(set) var processingProgress: Double?
    /// How the last completed session's text was delivered.
    public internal(set) var lastDelivery: DeliveryMethod?
    /// Choices for the current ``attention`` issue.
    public internal(set) var attentionActions: [DictationAction] = []
    /// The mode the next session will use, shown before and during recording.
    /// Stored in preferences (Settings may also change it there).
    public var writingMode: WritingMode {
        didSet { preferences.writingMode = writingMode }
    }
    /// The writing mode captured when the current recording started; shown
    /// in the overlay and stored with the session.
    public private(set) var activeMode: WritingMode?

    /// Called when a session ends for any reason, so the shortcut can re-arm.
    public var onSessionEnded: @MainActor () -> Void = {}
    /// Opens a settings pane for a recovery action.
    public var onOpenSettings: @MainActor (SettingsNavigation.Pane) -> Void = { _ in }
    /// Saves a copy of a kept recording where the user chooses (Save Audio…).
    public var onSaveAudio: @MainActor (URL) async -> Void = { _ in }

    var machine = RecorderStateMachine()
    public let capture: any AudioCapturing
    let processor: any DictationProcessing
    let feedback: any RecordingFeedback
    let preferences: any AppPreferences
    let speechAuthorizer: (any SpeechRecognitionAuthorizing)?
    let textCopier: (any TextCopying)?
    let finishedDisplay: Duration
    let failureDisplay: Duration
    let attentionDisplay: Duration
    let diagnostics: any DiagnosticsRecording

    var queue: Task<Void, Never>?
    var processingTask: Task<Void, Never>?
    var updatesTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var target: ActivationTarget?
    /// The session being processed or waiting for a decision.
    var session: DictationSession?
    /// Text kept in memory for Copy / Retry Delivery; never logged.
    var pendingTranscript: String?

    public init(
        capture: any AudioCapturing,
        processor: any DictationProcessing,
        feedback: any RecordingFeedback,
        preferences: any AppPreferences,
        speechAuthorizer: (any SpeechRecognitionAuthorizing)? = nil,
        textCopier: (any TextCopying)? = nil,
        finishedDisplay: Duration = .seconds(1.5),
        failureDisplay: Duration = .seconds(8),
        attentionDisplay: Duration = .seconds(120),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.diagnostics = diagnostics
        self.capture = capture
        self.processor = processor
        self.feedback = feedback
        self.preferences = preferences
        self.writingMode = preferences.writingMode
        self.speechAuthorizer = speechAuthorizer
        self.textCopier = textCopier
        self.finishedDisplay = finishedDisplay
        self.failureDisplay = failureDisplay
        self.attentionDisplay = attentionDisplay
    }

    public var failure: AudioCaptureError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    /// The processing issue waiting for the user's decision, if any.
    public var attention: DictationIssue? {
        if case .needsAttention(let issue) = state { return issue }
        return nil
    }

    /// Recording, processing, or holding a recording for a decision.
    public var hasActiveSession: Bool {
        state.isCapturing || state == .processing || attention != nil
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

    /// Hides a finished session's overlay. A kept recording is deleted.
    public func dismiss() {
        dismissTask?.cancel()
        if machine.handle(.reset) {
            discardSession()
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

    /// Waits for every queued command and any processing. For tests and app termination.
    public func settle() async {
        while true {
            let queued = queue
            let processing = processingTask
            await queued?.value
            await processing?.value
            if queue == queued && processingTask == processing { return }
        }
    }

    // MARK: Transitions

    func enqueue(_ operation: @escaping @MainActor (RecordingCoordinator) async -> Void) {
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
        discardSession()  // a recording kept for a decision is replaced by the new one
        sync()
        self.target = target
        writingMode = preferences.writingMode  // Settings may have changed it
        activeMode = writingMode
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
            let session = DictationSession(
                audio: recording, target: target, mode: activeMode ?? writingMode,
                language: preferences.dictationLanguage)
            self.session = session
            startProcessing(session)
        } catch {
            await fail(error)
        }
    }

    private func cancel() async {
        guard machine.handle(.cancel) else { return }
        stopProcessing()
        await capture.cancel()
        discardSession()
        level = 0
        sync()
        feedback.announce(String(localized: "Recording cancelled", bundle: .module))
        finishSession(displayFor: finishedDisplay)
    }

    private func fail(_ error: AudioCaptureError) async {
        guard machine.handle(.fail(error)) else { return }
        stopProcessing()
        await capture.cancel()  // releases the microphone and deletes partial audio
        discardSession()
        level = 0
        sync()
        feedback.announce(String(localized: "Recording failed. \(error.userMessage)", bundle: .module))
        Log.audio.error("Session failed: \(error.identifier, privacy: .public)")
        finishSession(displayFor: failureDisplay)
    }

    /// Ends the visible session. A session waiting for a decision keeps its
    /// recording until it is dismissed.
    func finishSession(displayFor duration: Duration) {
        target = nil
        activeMode = nil
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

    func cancelPendingDismiss() {
        dismissTask?.cancel()
    }

    func sync() {
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
        case .needsAttention(let issue): "needs-attention.\(issue.identifier)"
        }
    }
}
