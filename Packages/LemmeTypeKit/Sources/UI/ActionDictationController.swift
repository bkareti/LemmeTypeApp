import Domain
import Foundation

/// Dictation from the Action Button with another app in front (ADR 0032).
///
/// It drives the same recorder and pipeline as Quick Dictation, so modes, cloud
/// speech, and translation behave identically. The one difference is the end:
/// the finished text goes to the LemmeType keyboard instead of waiting on the
/// Quick Dictation screen. The text also stays in that screen's review, in
/// memory, so a dictation is not lost if the keyboard was not open.
@MainActor
public final class ActionDictationController {
    /// A dictation started here is running, so leaving the app must not stop it.
    public private(set) var isActive = false

    private let recorder: RecordingCoordinator
    private let handoff: any KeyboardHandoffPublishing
    private let presenter: any ActionDictationPresenting
    private let backgroundTime: any BackgroundTimeRequesting
    private let gate: BackgroundDictationGate
    private let prepare: @MainActor () async -> Void
    private let pollInterval: Duration
    private let resultRetention: Duration
    private let failureDisplay: Duration

    private var followTask: Task<Void, Never>?
    private var retentionTask: Task<Void, Never>?

    public init(
        recorder: RecordingCoordinator,
        handoff: any KeyboardHandoffPublishing,
        presenter: any ActionDictationPresenting,
        backgroundTime: any BackgroundTimeRequesting,
        gate: BackgroundDictationGate,
        prepare: @escaping @MainActor () async -> Void = {},
        pollInterval: Duration = .milliseconds(200),
        resultRetention: Duration = .seconds(KeyboardHandoff.lifetime),
        failureDisplay: Duration = .seconds(4)
    ) {
        self.recorder = recorder
        self.handoff = handoff
        self.presenter = presenter
        self.backgroundTime = backgroundTime
        self.gate = gate
        self.prepare = prepare
        self.pollInterval = pollInterval
        self.resultRetention = resultRetention
        self.failureDisplay = failureDisplay
    }

    /// One press starts a dictation and the next stops it. A press while the
    /// text is being written is ignored, so a double press cannot lose it.
    public func toggle() async {
        await prepare()
        switch recorder.state {
        case .recording: stop()
        case .preparing, .stopping, .processing: break
        default: await start()
        }
    }

    /// The microphone stops at once; the text follows.
    public func stop() {
        guard recorder.state == .recording else { return }
        if isActive { beginBackgroundTime() }
        recorder.requestStop()
    }

    private func start() async {
        await clearPreviousResult()
        do {
            // iOS ends the app if a recording intent has audio but no Live Activity.
            try presenter.begin()
        } catch {
            handoff.publish(.failed(Self.liveActivityMessage))
            hold(for: failureDisplay)
            return
        }
        gate.isActive = true
        isActive = true
        handoff.publish(KeyboardHandoff(phase: .listening))
        recorder.requestStart(target: nil)
        await recorder.settle()
        guard recorder.state == .recording else {
            await deliverOutcome()
            return
        }
        followTask = Task { [weak self] in await self?.followRecording() }
    }

    private func clearPreviousResult() async {
        followTask?.cancel()
        followTask = nil
        retentionTask?.cancel()
        retentionTask = nil
        await presenter.end()
        handoff.clear()
        backgroundTime.end()
    }

    /// Follows every way a recording ends: the button, the time limit, a phone
    /// call, or an audio failure.
    private func followRecording() async {
        while recorder.state == .recording {
            try? await Task.sleep(for: pollInterval)
            if Task.isCancelled { return }
        }
        beginBackgroundTime()
        handoff.publish(KeyboardHandoff(phase: .writing))
        await presenter.show(.writing)
        await recorder.settle()
        await deliverOutcome()
    }

    private func deliverOutcome() async {
        switch recorder.state {
        case .needsAttention(let issue) where issue.isTextForReview:
            if let text = recorder.reviewText {
                recorder.discardRecordingKeepingText()
                await finish(with: .ready(text: text), hold: resultRetention)
            } else {
                await fail(issue.userMessage)
            }
        case .needsAttention(let issue):
            await fail(issue.userMessage)
        case .failed(let error):
            await fail(error.userMessage)
        default:
            await presenter.end()
            handoff.clear()
            endSession()
            backgroundTime.end()
        }
    }

    private func finish(with result: KeyboardHandoff, hold duration: Duration) async {
        handoff.publish(result)
        await presenter.end()
        endSession()
        hold(for: duration)
    }

    private func fail(_ message: String) async {
        handoff.publish(.failed(message))
        await presenter.show(.failed)
        endSession()
        hold(for: failureDisplay)
    }

    private func endSession() {
        gate.isActive = false
        isActive = false
    }

    /// Keeps the app awake while the keyboard can still collect the result, then
    /// erases it, so dictated text never waits in the shared file.
    private func hold(for duration: Duration) {
        retentionTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            await self.presenter.end()
            self.handoff.clear()
            self.backgroundTime.end()
        }
    }

    private func beginBackgroundTime() {
        // If iOS runs out of time first, the text is erased rather than left behind.
        backgroundTime.begin { [weak self] in self?.handoff.clear() }
    }

    private static var liveActivityMessage: String {
        String(
            localized: "Turn on Live Activities for LemmeType in Settings to dictate from other apps.",
            bundle: .module,
            comment: "Shown on the keyboard when iOS refuses the Live Activity that a background recording needs")
    }
}

extension DictationIssue {
    /// A finished result waiting to be read, rather than a problem.
    fileprivate var isTextForReview: Bool {
        switch self {
        case .reviewText, .reviewTranslation, .reviewRewrite: true
        default: false
        }
    }
}
