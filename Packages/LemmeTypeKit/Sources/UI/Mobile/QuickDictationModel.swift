import Domain
import Foundation
import Observation

/// What the Quick Dictation screen shows and does on iPhone and iPad (E8-S6),
/// derived from the shared recorder. It adds only what a phone needs: the
/// microphone explanation before the first prompt, the copy confirmation, and
/// the launch request left by a shortcut. It never reads or logs dictated text
/// beyond handing it to the screen.
@MainActor
@Observable
public final class QuickDictationModel {
    /// The one thing the screen is doing.
    public enum Screen: Equatable {
        case ready
        case preparing
        case recording
        case processing
        /// Text waiting to be copied; nothing has left the app.
        case review(text: String)
        /// A decision other than copying (no engine, language unavailable, …).
        case attention(DictationIssue)
        case failed(AudioCaptureError)
    }

    public let recorder: RecordingCoordinator
    /// The user is about to see the system microphone prompt and is told why first.
    public private(set) var isExplainingMicrophone = false
    /// Set when the last result was copied; cleared when the next dictation starts.
    public private(set) var copiedFor: CopiedTextLifetime?

    private let microphoneStatus: @MainActor () -> PermissionStatus
    private let requestMicrophone: @MainActor () async -> PermissionStatus
    private let openSettings: @MainActor () -> Void
    private let lifetime: @MainActor () -> CopiedTextLifetime
    private let launchRequests: LaunchRequestInbox?
    private let feedback: any RecordingFeedback

    public init(
        recorder: RecordingCoordinator,
        feedback: any RecordingFeedback,
        microphoneStatus: @escaping @MainActor () -> PermissionStatus,
        requestMicrophone: @escaping @MainActor () async -> PermissionStatus,
        openSettings: @escaping @MainActor () -> Void,
        lifetime: @escaping @MainActor () -> CopiedTextLifetime = { .default },
        launchRequests: LaunchRequestInbox? = nil
    ) {
        self.recorder = recorder
        self.feedback = feedback
        self.microphoneStatus = microphoneStatus
        self.requestMicrophone = requestMicrophone
        self.openSettings = openSettings
        self.lifetime = lifetime
        self.launchRequests = launchRequests
    }

    public var screen: Screen {
        switch recorder.state {
        case .idle, .completed, .cancelled: .ready
        case .preparing: .preparing
        case .recording: .recording
        case .stopping, .processing: .processing
        case .failed(let error): .failed(error)
        case .needsAttention(.reviewText): .review(text: recorder.reviewText ?? "")
        case .needsAttention(let issue): .attention(issue)
        }
    }

    // MARK: Recording

    /// Starts a dictation. The first time, the user reads why the microphone is
    /// needed before the system asks.
    public func start() {
        guard screen == .ready else { return }
        copiedFor = nil
        if microphoneStatus() == .notRequested {
            isExplainingMicrophone = true
        } else {
            recorder.requestStart(target: nil)
        }
    }

    public func continueAfterExplanation() async {
        isExplainingMicrophone = false
        if await requestMicrophone().isGranted {
            recorder.requestStart(target: nil)
        }
    }

    public func cancelExplanation() {
        isExplainingMicrophone = false
    }

    public func stop() { recorder.requestStop() }

    public func cancel() { recorder.requestCancel() }

    /// Starts a dictation if a shortcut asked for one a moment ago (E8-S7).
    /// Call when the app becomes active; a request is used once and expires.
    public func startIfRequestedByShortcut() {
        guard launchRequests?.consume() != nil else { return }
        start()
    }

    // MARK: Result

    /// Copies exactly the reviewed text, once, when the user chooses Copy.
    public func copy() async {
        let chosen = lifetime()
        recorder.perform(.copyText)
        await recorder.settle()
        guard recorder.lastDelivery == .copied else { return }
        copiedFor = chosen
        feedback.announce(Self.copiedMessage(for: chosen))
        feedback.play(.stop)
    }

    public func discard() { recorder.perform(.discard) }

    /// Throws the result away and records again.
    public func dictateAgain() {
        recorder.perform(.discard)
        recorder.requestStart(target: nil)
    }

    /// A choice offered for the current attention issue.
    public func perform(_ action: DictationAction) { recorder.perform(action) }

    public func openSystemSettings() { openSettings() }

    public static func copiedMessage(for lifetime: CopiedTextLifetime) -> String {
        let minutes = lifetime.rawValue / 60
        return String(
            localized: "Copied. It stays on this device for \(minutes) min. Paste it into any app.",
            bundle: .module,
            comment: "Shown after Copy; the number is how many minutes the copied text stays available")
    }
}
