import Audio
import Delivery
import Domain
import Editing
import Foundation
import Lifecycle
import ModelAssets
import Permissions
import Recognition
import Subscriptions
import Support
import SwiftUI
import UI
import os

/// The single composition root of the iPhone and iPad app. Every concrete
/// operating-system service is constructed here; everything downstream receives
/// protocols (ADR 0027).
@MainActor
// swiftlint:disable:next type_body_length
struct IOSComposition {
    enum Mode: String {
        case live
        /// Deterministic fakes for UI tests. Only honoured in Debug builds.
        case uiTesting
    }

    static let uiTestingArgument = "-LemmeTypeUITesting"

    /// Which languages this build offers (ADR 0029): English only in Release
    /// (the friends beta), every language in Debug for evaluation work.
    static var languageScope: LanguageScope {
        #if ENGLISH_ONLY_RELEASE
            .englishOnly
        #else
            .allLanguages
        #endif
    }

    /// The one monthly subscription (E13-S4, ADR 0034). Confirm this id before the first App Store Connect save:
    /// it cannot be reused or renamed afterwards.
    static let subscriptionProductID = "com.lemmetype.LemmeType.iOS.pro.monthly"

    let mode: Mode
    /// The subscription, its paywall, and the Settings section.
    let subscription: SubscriptionModel
    /// Turning cloud speech on and off; `nil` when this build doesn't offer it.
    let cloudSpeech: CloudSpeechSettingsModel?
    /// Shared with the App Intent, which leaves a request here (E8-S7).
    let launchRequests: LaunchRequestInbox
    let recorder: RecordingCoordinator
    let quick: QuickDictationModel
    let dictation: DictationSettingsModel
    let models: ModelsSettingsModel
    let personalization: PersonalizationModel
    let modes: ModesSettingsModel
    let privacy: PrivacyOverviewModel
    let permissions: PermissionsModel
    let residency: ModelResidencyController
    let conditions: any SystemConditionsMonitoring
    let audioCapture: any AudioCapturing
    let actionDictation: ActionDictationController
    private let prepare: @MainActor () async -> Void

    /// The services that differ between the real app and UI tests.
    struct Services {
        var permissionChecker: any PermissionChecking
        var permissionRequester: any PermissionRequesting
        var preferences: any AppPreferences
        var audioCapture: any AudioCapturing
        var speechAuthorizer: any SpeechRecognitionAuthorizing
        var engines: [any SpeechRecognitionEngine]
        var modelAssets: any ModelAssetManaging
        var textCopier: any TextCopying
        var rewriter: any TextRewriting
        var personalizationStore: any PersonalizationStoring
        /// Kept only if the user turns retention on, which the iPhone app does not offer (ADR 0027).
        var historyStore: any DictationHistoryStoring
        var conditions: any SystemConditionsMonitoring
        var diagnostics: DiagnosticsBuffer
        var hardware: HardwareProfile
        var copiedTextLifetime: @MainActor () -> CopiedTextLifetime
        var limits: RecordingLimits = .handheld
        var cloudSpeech: CloudSpeechServices?
        var actionDictation = ActionDictationServices()
        var subscription: any SubscriptionProviding
        var paywallSeen: any PaywallSeenStoring
        /// Whether dictation needs an active trial or subscription, and the summary the keyboard reads.
        var entitlement: any EntitlementChecking
        var entitlementSummary: any EntitlementSummaryStoring
    }

    static func make(arguments: [String]) -> IOSComposition {
        #if DEBUG
            if arguments.contains(uiTestingArgument) {
                let scenario = UITestScenario(arguments: arguments)
                let composition = assemble(mode: .uiTesting, uiTesting(scenario))
                if scenario.startsFromShortcut { composition.launchRequests.post() }
                return composition
            }
        #endif
        return assemble(mode: .live, live())
    }

    // MARK: Real services

    private static func live() -> Services {
        let diagnostics = DiagnosticsBuffer()
        let preferences = UserDefaultsPreferences()
        let checker = SystemPermissionChecker()
        let authorizer = SystemSpeechAuthorizer()
        let conditions = SystemConditionsMonitor()
        let modelAssets = ModelAssetStore.makeDefault(diagnostics: diagnostics)
        let hardware = HardwareProfile.current
        // The same object sells the subscription and shows the gateway its proof (E13-S4, E13-S3).
        let subscription = StoreKitSubscriptionService(productID: subscriptionProductID)
        let cloudSpeech = liveCloudSpeech(proofs: subscription)
        let gate = BackgroundDictationGate()
        return Services(
            permissionChecker: checker,
            permissionRequester: SystemPermissionRequester(),
            preferences: preferences,
            audioCapture: AudioCaptureService(
                source: AVAudioSessionSource(backgroundDictation: gate), storage: .makeDefault(), permissions: checker,
                diagnostics: diagnostics),
            speechAuthorizer: authorizer,
            engines: [
                AppleSpeechEngine(authorizer: authorizer, language: { preferences.dictationLanguage }),
                WhisperEngine(
                    assets: modelAssets, hardware: hardware,
                    availableMemory: availableMemory,
                    settings: {
                        var settings = whisperSettings(preferences: preferences, conditions: conditions.current)
                        // iOS refuses GPU work from the background.
                        if gate.isActive { settings.usesGPU = false }
                        return settings
                    }),
            ] + cloudEngines(cloudSpeech, diagnostics: diagnostics),
            modelAssets: modelAssets,
            textCopier: ExpiringTextCopier(
                writer: UIPasteboardWriter(), lifetime: { CopiedTextLifetime.stored(in: .standard) }),
            rewriter: FoundationModelsRewriter(),
            personalizationStore: FilePersonalizationStore.makeDefault(diagnostics: diagnostics),
            historyStore: FileDictationHistoryStore.makeDefault(),
            conditions: conditions,
            diagnostics: diagnostics,
            hardware: hardware,
            copiedTextLifetime: { CopiedTextLifetime.stored(in: .standard) },
            cloudSpeech: cloudSpeech,
            actionDictation: ActionDictationServices(
                handoff: AppGroupKeyboardHandoffStore.makeDefault(), presenter: IOSActionDictationPresenter(),
                backgroundTime: IOSBackgroundTime(), gate: gate),
            subscription: subscription, paywallSeen: UserDefaultsPaywallSeen(),
            entitlement: EntitlementGate(subscription: subscription, ledger: UserDefaultsEntitlementLedger()),
            entitlementSummary: AppGroupEntitlementSummaryStore.makeDefault())
    }

    // MARK: Assembly

    // swiftlint:disable:next function_body_length
    private static func assemble(mode: Mode, _ services: Services) -> IOSComposition {
        let preferences = services.preferences
        let diagnostics = services.diagnostics
        let conditions = services.conditions
        let personalization = PersonalizationModel(store: services.personalizationStore, diagnostics: diagnostics)
        let residency = ModelResidencyController(
            engines: services.engines,
            plan: { performancePlan(preferences: preferences, conditions: conditions.current) },
            diagnostics: diagnostics)
        let processor = TranscriptionPipeline(
            engines: services.engines, delivery: NoTargetDelivery(), rewriter: services.rewriter,
            copier: services.textCopier, diagnostics: diagnostics, hardware: services.hardware,
            reviewsEveryResult: true)
        let feedback = SystemRecordingFeedback(preferences: preferences)
        let recorder = RecordingCoordinator(
            capture: services.audioCapture, processor: processor, feedback: feedback, preferences: preferences,
            speechAuthorizer: services.speechAuthorizer, textCopier: services.textCopier,
            attentionDisplay: .seconds(600),
            personalization: { [weak personalization] in personalization?.library ?? .empty },
            residency: residency, diagnostics: diagnostics, limits: services.limits,
            entitlement: services.entitlement)
        let subscription = SubscriptionModel(
            service: services.subscription, seen: services.paywallSeen, summary: services.entitlementSummary)
        // A dictation refused for want of a subscription shows the offer, and so does its "See Subscription" choice.
        recorder.onOpenSubscription = { [weak subscription] in subscription?.showPaywall() }
        let permissions = PermissionsModel(
            checker: services.permissionChecker, requester: services.permissionRequester, diagnostics: diagnostics)
        let dictation = DictationSettingsModel(
            engines: services.engines, modelAssets: services.modelAssets, preferences: preferences,
            speechAuthorizer: services.speechAuthorizer, diagnostics: diagnostics, hardware: services.hardware,
            languageScope: Self.languageScope)
        let modes = ModesSettingsModel(
            personalization: personalization, preferences: preferences,
            engines: services.engines.map(\.descriptor.id).filter { !$0.isCloud }, languages: dictation.languageChoices,
            speechOutputs: dictation.speechOutputChoices,
            runningApplications: { [] }, applicationName: { _ in nil }, diagnostics: diagnostics)
        let models = ModelsSettingsModel(
            modelAssets: services.modelAssets, preferences: preferences, engines: services.engines,
            hardware: services.hardware, catalog: ModelCatalog.all.filter(Self.languageScope.lists),
            conditions: conditions.current, diagnostics: diagnostics)
        models.onModelsChanged = { [weak dictation] in dictation?.refreshInBackground() }
        let history = HistorySettingsModel(
            history: DictationHistoryService(
                store: services.historyStore, preferences: preferences, diagnostics: diagnostics),
            copier: services.textCopier)
        let cloudSpeech = services.cloudSpeech.map {
            CloudSpeechSettingsModel(
                provider: $0.provider, consent: $0.consent, directory: $0.gateway, allowances: $0.gateway)
        }
        cloudSpeech?.onChange = { [weak modes, weak dictation] offered in
            modes?.setOffersCloudEngine(offered)
            dictation?.refreshInBackground()
        }
        // Agreeing is the only step: the Cloud mode is added and becomes the default.
        cloudSpeech?.onReady = { [weak modes, weak dictation] in
            modes?.useCloudAnyLanguageMode()
            dictation?.refreshInBackground()
        }
        cloudSpeech?.onTurnedOff = { [weak modes, weak dictation] in
            modes?.removeCloudAnyLanguageMode()
            dictation?.refreshInBackground()
        }
        let privacy = PrivacyOverviewModel(
            history: history, personalization: personalization, modes: modes, capture: services.audioCapture,
            modelAssets: services.modelAssets, clearDiagnostics: { diagnostics.removeAll() },
            eraseCloudSpeech: { await cloudSpeech?.eraseAll() ?? false },
            eraseSubscriptionSummary: { [weak subscription] in subscription?.eraseSummary() })
        let launchRequests = LaunchRequestInbox()
        let checker = services.permissionChecker
        let requester = services.permissionRequester
        let quick = QuickDictationModel(
            recorder: recorder, feedback: feedback,
            microphoneStatus: { checker.status(for: .microphone) },
            requestMicrophone: { await requester.requestMicrophoneAccess() },
            openSettings: { requester.openSystemSettings(for: .microphone) },
            lifetime: services.copiedTextLifetime,
            // Apple Speech, the engine that works without a download, needs Speech Recognition:
            // ask with the microphone on the first dictation when nothing else is ready.
            needsSpeechRecognition: { [weak dictation] in
                services.speechAuthorizer.status() == .notRequested && dictation?.hasReadyEngine != true
            },
            requestSpeechRecognition: { [weak dictation] in
                _ = await services.speechAuthorizer.requestAuthorization()
                await dictation?.refresh()
            },
            launchRequests: launchRequests,
            isCloudSpeechOn: { cloudSpeech?.status == .turnedOn })
        // Purges old audio and loads settings once, before any recording, whether the
        // screen or the Action Button launched the app.
        let startup = StartupOnce()
        let audioCapture = services.audioCapture
        let handoff = services.actionDictation.handoff
        let prepare: @MainActor () async -> Void = {
            await startup.run {
                // A result left by a crash or force-quit must not outlive that run.
                handoff.clear()
                await audioCapture.purgeLeftovers()
                await personalization.load()
                await cloudSpeech?.refresh()
                await dictation.refresh()
                await models.refresh()
            }
        }
        let actionDictation = ActionDictationController(
            recorder: recorder, handoff: services.actionDictation.handoff,
            presenter: services.actionDictation.presenter, backgroundTime: services.actionDictation.backgroundTime,
            gate: services.actionDictation.gate, prepare: prepare)
        return IOSComposition(
            mode: mode, subscription: subscription, cloudSpeech: cloudSpeech, launchRequests: launchRequests,
            recorder: recorder, quick: quick,
            dictation: dictation,
            models: models, personalization: personalization, modes: modes, privacy: privacy,
            permissions: permissions, residency: residency, conditions: conditions,
            audioCapture: services.audioCapture, actionDictation: actionDictation, prepare: prepare)
    }

    // MARK: Running

    func rootView() -> some View {
        MobileRootView(
            quick: quick, dictation: dictation,
            settings: MobileSettingsView(
                dictation: dictation, models: models, personalization: personalization, modes: modes,
                privacy: privacy, permissions: permissions, cloudSpeech: cloudSpeech, subscription: subscription),
            actionDictation: actionDictation, subscription: subscription)
    }

    /// Cleans up after a crash, loads saved data, and follows the system's memory
    /// and heat for as long as the app runs.
    func start() async {
        // In the background: launching never waits for the App Store.
        subscription.begin()
        await prepare()
        quick.startIfRequestedByShortcut()
        var previous = conditions.current
        for await current in conditions.changes() {
            models.update(current)
            if current.memoryPressure != .normal && previous.memoryPressure == .normal {
                await residency.memoryPressure()
            }
            // A critical memory warning ends a recording; what was said so far is kept and processed.
            if current.memoryPressure == .critical { recorder.stopForSystemReason() }
            previous = current
        }
    }

    /// Memory this app may still use before iOS ends it, for the Whisper load check (E8-S5).
    /// The Simulator has no such limit and reports 0, which would refuse every model, so
    /// there it is unknown and the check is skipped.
    nonisolated static func availableMemory() -> UInt64? {
        #if targetEnvironment(simulator)
            nil
        #else
            UInt64(max(0, os_proc_available_memory()))
        #endif
    }

    // MARK: Whisper settings

    /// The Whisper model choice and the performance plan, read for every session (E5-S1, E5-S5).
    nonisolated static func whisperSettings(
        preferences: any AppPreferences, conditions: SystemConditions
    ) -> WhisperRunSettings {
        let plan = performancePlan(preferences: preferences, conditions: conditions)
        return WhisperRunSettings(
            choice: preferences.whisperModel, order: plan.whisperModelOrder, threads: plan.inferenceThreads,
            usesGPU: plan.usesGPU && gpuRunsWhisper,
            warmUpNeed: RecognitionNeed(
                language: preferences.dictationLanguage,
                task: .required(for: preferences.dictationLanguage, output: preferences.speechOutput)))
    }

    /// The Simulator's Metal driver cannot allocate the shared buffers whisper.cpp asks for
    /// (the app traps in `newBufferWithLength`), so Whisper runs on the CPU there.
    nonisolated static var gpuRunsWhisper: Bool {
        #if targetEnvironment(simulator)
            false
        #else
            true
        #endif
    }

    nonisolated static func performancePlan(
        preferences: any AppPreferences, conditions: SystemConditions
    ) -> PerformancePlan {
        PerformancePlan.make(
            profile: preferences.performanceProfile, conditions: conditions, idleUnload: preferences.modelIdleUnload)
    }
}

private func whisperSettings(preferences: any AppPreferences, conditions: SystemConditions) -> WhisperRunSettings {
    IOSComposition.whisperSettings(preferences: preferences, conditions: conditions)
}
