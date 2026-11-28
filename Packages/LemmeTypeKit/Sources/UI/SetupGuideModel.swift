import Domain
import Observation
import Support

/// The first-run setup guide on iPhone and iPad (E8-S10): the microphone, how LemmeType listens (a model on
/// this device, Apple Speech, or Cloud speech), and dictating in other apps. Every action goes through the
/// model Settings already uses, so the guide adds no new way to change anything. It stores one flag,
/// `hasCompletedOnboarding`.
@MainActor
@Observable
public final class SetupGuideModel {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome
        case microphone
        case listening
        case anyApp
        case done
    }

    /// The ways to listen the guide can offer.
    public enum Listening: String, CaseIterable, Sendable {
        case onDevice
        case appleSpeech
        case cloud
        case later
    }

    public private(set) var step: Step = .welcome
    public private(set) var isPresented = false
    public private(set) var microphone: PermissionStatus
    public private(set) var speechRecognition: PermissionStatus?
    public private(set) var choice: Listening?

    public let models: ModelsSettingsModel
    /// `nil` when this build does not offer Cloud speech.
    public let cloudSpeech: CloudSpeechSettingsModel?
    /// `nil` in a build without the subscription.
    public let subscription: SubscriptionModel?
    public let deviceClass: DeviceClass

    private let preferences: any AppPreferences
    private let microphoneStatus: @MainActor () -> PermissionStatus
    private let requestMicrophone: @MainActor () async -> PermissionStatus
    private let openMicrophoneSettings: @MainActor () -> Void
    private let speechAuthorizer: (any SpeechRecognitionAuthorizing)?
    private let onEnginesChanged: @MainActor () async -> Void

    public init(
        preferences: any AppPreferences,
        deviceClass: DeviceClass,
        models: ModelsSettingsModel,
        cloudSpeech: CloudSpeechSettingsModel? = nil,
        subscription: SubscriptionModel? = nil,
        microphoneStatus: @escaping @MainActor () -> PermissionStatus,
        requestMicrophone: @escaping @MainActor () async -> PermissionStatus,
        openMicrophoneSettings: @escaping @MainActor () -> Void,
        speechAuthorizer: (any SpeechRecognitionAuthorizing)? = nil,
        onEnginesChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.preferences = preferences
        self.deviceClass = deviceClass
        self.models = models
        self.cloudSpeech = cloudSpeech
        self.subscription = subscription
        self.microphoneStatus = microphoneStatus
        self.requestMicrophone = requestMicrophone
        self.openMicrophoneSettings = openMicrophoneSettings
        self.speechAuthorizer = speechAuthorizer
        self.onEnginesChanged = onEnginesChanged
        microphone = microphoneStatus()
        speechRecognition = speechAuthorizer?.status()
    }

    // MARK: Showing

    /// Call once at launch, before the subscription starts. A fresh install sees the guide; someone who
    /// already used the microphone (an upgrade from a build without the guide) is marked done silently.
    public func begin() {
        guard !preferences.hasCompletedOnboarding else { return }
        microphone = microphoneStatus()
        guard microphone == .notRequested else {
            preferences.hasCompletedOnboarding = true
            return
        }
        present()
    }

    /// Settings › Show Setup Guide: from Welcome again. Nothing is reset.
    public func replay() {
        present()
    }

    private func present() {
        refreshStatuses()
        step = .welcome
        isPresented = true
        subscription?.holdOneTimeOffer()
    }

    /// Finishing and closing (from any step) both end the guide for good.
    public func finish() {
        preferences.hasCompletedOnboarding = true
        isPresented = false
        Log.permissions.info("Setup guide finished at \(self.step.rawValue, privacy: .public)")
        subscription?.releaseOneTimeOffer()
    }

    // MARK: Moving

    /// The steps this device shows: an iPad has no Action Button or Back Tap.
    public var steps: [Step] {
        Step.allCases.filter { $0 != .anyApp || deviceClass == .iPhone }
    }

    public var position: Int { steps.firstIndex(of: step) ?? 0 }

    public var canGoBack: Bool { position > 0 }

    public func next() {
        guard position + 1 < steps.count else { return finish() }
        step = steps[position + 1]
        refreshStatuses()
    }

    public func back() {
        guard canGoBack else { return }
        step = steps[position - 1]
    }

    private func refreshStatuses() {
        microphone = microphoneStatus()
        speechRecognition = speechAuthorizer?.status()
    }

    // MARK: Microphone

    /// Before the system prompt the step offers only Continue (App Review Guideline 5.1.1).
    public var hasAskedForMicrophone: Bool { microphone != .notRequested }

    /// The step's Continue: asks the system once. The answer is shown on the same step.
    public func allowMicrophone() async {
        guard microphone == .notRequested else { return }
        microphone = await requestMicrophone()
    }

    public func openSettingsForMicrophone() { openMicrophoneSettings() }

    // MARK: Listening

    /// What the Listening step offers, in order. "On this device" needs a model this device runs; Cloud needs
    /// a build that offers it; Apple Speech needs a speech authorizer.
    public var listeningOptions: [Listening] {
        Listening.allCases.filter { option in
            switch option {
            case .onDevice: models.suggestedModel != nil
            case .appleSpeech: speechAuthorizer != nil
            case .cloud: cloudSpeech != nil
            case .later: true
            }
        }
    }

    /// Offers the suggested model's download with the same confirmation, space check, and licence as Settings.
    /// Nothing downloads until the user confirms (``ModelsSettingsModel/confirmDownload()``).
    public func chooseOnDevice() async {
        choice = .onDevice
        guard let suggested = models.suggestedModel, !suggested.state.isInstalled, !suggested.state.isBusy
        else { return }
        await models.offerDownload(of: suggested.id)
    }

    public func confirmDownload() {
        models.confirmDownload()
    }

    /// The suggested model's state, for the progress ring.
    public var suggestedModelState: ModelInstallState? {
        models.suggestedModel.flatMap { models.row($0.id)?.state }
    }

    /// Apple Speech works with no download but needs Speech Recognition. The option's text explains that
    /// first; the button then shows the system prompt, once.
    public func chooseAppleSpeech() async {
        choice = .appleSpeech
        guard let speechAuthorizer else { return }
        if speechAuthorizer.status() == .notRequested {
            speechRecognition = await speechAuthorizer.requestAuthorization()
            await onEnginesChanged()
        } else {
            speechRecognition = speechAuthorizer.status()
        }
    }

    public func openSettingsForSpeechRecognition() { speechAuthorizer?.openSystemSettings() }

    /// Cloud speech is part of the subscription: without one the offer is shown; with one, the agreement.
    /// Cloud turns on only when the user agrees (``CloudSpeechSettingsModel/acceptConsent()``).
    public func chooseCloud() {
        choice = .cloud
        guard let cloudSpeech, cloudSpeech.status != .turnedOn else { return }
        if let subscription, !subscription.state.grantsAccess {
            subscription.showPaywall()
            return
        }
        cloudSpeech.requestTurnOn()
    }

    public func chooseLater() {
        choice = .later
        next()
    }

    // MARK: All set

    /// One line of the All set checklist.
    public enum Readiness: Equatable, Sendable {
        case ready
        case inProgress
        case notSet
    }

    public var microphoneReadiness: Readiness { microphone == .granted ? .ready : .notSet }

    public var listeningReadiness: Readiness {
        switch choice {
        case .onDevice:
            switch suggestedModelState {
            case .installed: .ready
            case .downloading, .verifying, .paused: .inProgress
            default: .notSet
            }
        case .appleSpeech: speechRecognition == .granted ? .ready : .notSet
        case .cloud: cloudSpeech?.status == .turnedOn ? .ready : .notSet
        case .later, nil: .notSet
        }
    }
}
