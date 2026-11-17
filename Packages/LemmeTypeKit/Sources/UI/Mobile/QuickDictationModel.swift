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
        /// Text waiting to be copied; nothing has left the app. A translation or a
        /// rewrite is reviewed the same way, and the original is one tap away.
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
    private let needsSpeechRecognition: @MainActor () -> Bool
    private let requestSpeechRecognition: @MainActor () async -> Void
    private let launchRequests: LaunchRequestInbox?
    /// Whether the user has turned cloud speech on, so explanations stay true (ADR 0031).
    public let isCloudSpeechOn: @MainActor () -> Bool
    private let feedback: any RecordingFeedback
    /// Whether Apple's on-device model can rewrite text in a language (E12-S5).
    private let rewriterAvailability: @MainActor (String) async -> RewriterAvailability
    /// Whether a tone can be chosen for English text on this device; `nil` until checked.
    public private(set) var toneAvailability: RewriterAvailability?

    public init(
        recorder: RecordingCoordinator,
        feedback: any RecordingFeedback,
        microphoneStatus: @escaping @MainActor () -> PermissionStatus,
        requestMicrophone: @escaping @MainActor () async -> PermissionStatus,
        openSettings: @escaping @MainActor () -> Void,
        lifetime: @escaping @MainActor () -> CopiedTextLifetime = { .default },
        needsSpeechRecognition: @escaping @MainActor () -> Bool = { false },
        requestSpeechRecognition: @escaping @MainActor () async -> Void = {},
        launchRequests: LaunchRequestInbox? = nil,
        isCloudSpeechOn: @escaping @MainActor () -> Bool = { false },
        rewriterAvailability: @escaping @MainActor (String) async -> RewriterAvailability = { _ in .unavailable }
    ) {
        self.isCloudSpeechOn = isCloudSpeechOn
        self.rewriterAvailability = rewriterAvailability
        self.recorder = recorder
        self.feedback = feedback
        self.microphoneStatus = microphoneStatus
        self.requestMicrophone = requestMicrophone
        self.openSettings = openSettings
        self.lifetime = lifetime
        self.needsSpeechRecognition = needsSpeechRecognition
        self.requestSpeechRecognition = requestSpeechRecognition
        self.launchRequests = launchRequests
    }

    /// What kind of text is under review.
    public enum ReviewKind: Equatable, Sendable {
        case dictation
        case translation
        case rewrite
    }

    public var screen: Screen {
        switch recorder.state {
        case .idle, .completed, .cancelled: .ready
        case .preparing: .preparing
        case .recording: .recording
        case .stopping, .processing: .processing
        case .failed(let error): .failed(error)
        case .needsAttention(let issue) where reviewKind(of: issue) != nil:
            .review(text: (recorder.reviewShowsOriginal ? recorder.reviewOriginal : recorder.reviewText) ?? "")
        case .needsAttention(let issue): .attention(issue)
        }
    }

    public var reviewKind: ReviewKind? { recorder.attention.flatMap(reviewKind(of:)) }

    private func reviewKind(of issue: DictationIssue) -> ReviewKind? {
        switch issue {
        case .reviewText: .dictation
        case .reviewTranslation: .translation
        case .reviewRewrite: .rewrite
        default: nil
        }
    }

    /// A rewrite can be compared with the words that were said.
    public var canCompareWithOriginal: Bool { recorder.reviewOriginal != nil || recorder.reviewShowsOriginal }

    public var showsOriginal: Bool { recorder.reviewShowsOriginal }

    public func toggleOriginal() { recorder.toggleReviewOriginal() }

    /// Regenerate and Translate Again, when the review offers them. Insert and Use Original
    /// are not offered here: there is no field to insert into on a phone.
    public var reviewRetryAction: DictationAction? {
        let offered = recorder.attentionActions
        if offered.contains(.regenerate) { return .regenerate }
        if reviewKind == .translation, offered.contains(.retry) { return .retry }
        return nil
    }

    // MARK: Tone (E12-S5)

    /// The tones offered for English text under review.
    public var toneChoices: [Tone] { RecordingCoordinator.reviewToneChoices }

    /// The tone row is shown only for English text: Telugu and mixed text keep their tone.
    public var canChangeTone: Bool { recorder.canChangeReviewTone }

    /// The tone of the text on screen; `nil` when it is none of ``toneChoices``.
    public var selectedTone: Tone? { recorder.reviewTone }

    /// Whether choosing a tone can work on this device now.
    public var isToneReady: Bool { toneAvailability?.isReady == true }

    /// Why the tone row is disabled, or `nil` while it can be used or is still being checked.
    public var toneUnavailableMessage: String? {
        guard let toneAvailability, !toneAvailability.isReady else { return nil }
        return String(
            localized: "Tone changes aren’t available: \(toneAvailability.rewriteReason)", bundle: .module,
            comment: "Under the disabled tone choices on the review screen; the reason is a short sentence")
    }

    /// Why the text on screen is not the rewrite that was asked for, if it isn't.
    public var reviewNotice: String? { recorder.reviewNotice?.userMessage }

    /// Asks the device once per review whether Apple's model can rewrite English.
    public func refreshToneAvailability() async {
        toneAvailability = await rewriterAvailability(SpokenLanguages.english.code)
    }

    public func chooseTone(_ tone: Tone) {
        guard isToneReady else { return }
        recorder.changeReviewTone(tone)
    }

    // MARK: Spoken language (E12-S6)

    /// A translation is shown and the text in the spoken language can be shown instead.
    public var canShowSpokenLanguage: Bool { recorder.canShowSpokenLanguage }

    /// The spoken-language text is shown and the translation is one tap away.
    public var canShowEnglish: Bool { recorder.canShowEnglishTranslation }

    /// Showing the spoken language sends the recording to the cloud again: ask first.
    public var spokenLanguageNeedsUpload: Bool { recorder.spokenLanguageNeedsUpload }

    /// "Show in Telugu", or "Show in Original Language" when the language was detected.
    public var showSpokenLanguageTitle: String {
        guard let language = recorder.reviewSpokenLanguage else {
            return String(
                localized: "Show in Original Language", bundle: .module,
                comment: "Review button: show the text in the language that was spoken, not translated")
        }
        let name = DictationSettingsModel.settingLanguageName(language)
        return String(
            localized: "Show in \(name)", bundle: .module,
            comment: "Review button: show the text in the spoken language; the value is a language name such as Telugu")
    }

    /// Why the spoken-language text could not be shown; the translation is on screen again.
    public var spokenLanguageFailureMessage: String? { recorder.spokenLanguageFailure?.userMessage }

    public func showSpokenLanguage() { recorder.showSpokenLanguage() }

    public func showEnglish() { recorder.showEnglishTranslation() }

    // MARK: Recording

    /// Starts a dictation. The first time, the user reads why the microphone (and,
    /// when no engine is ready without it, Speech Recognition) is needed before the
    /// system asks, so the first dictation works without a detour to Settings.
    public func start() {
        guard screen == .ready else { return }
        copiedFor = nil
        if microphoneStatus() == .notRequested || needsSpeechRecognition() {
            isExplainingMicrophone = true
        } else {
            recorder.requestStart(target: nil)
        }
    }

    /// Asks the system, then starts. A denial goes through the recorder too, so the
    /// screen says why nothing records and offers Open Settings (E8-S4).
    public func continueAfterExplanation() async {
        isExplainingMicrophone = false
        if microphoneStatus() == .notRequested { _ = await requestMicrophone() }
        if needsSpeechRecognition() { await requestSpeechRecognition() }
        recorder.requestStart(target: nil)
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
        feedback.play(.copied)
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
