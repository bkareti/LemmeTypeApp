import Audio
import Delivery
import Domain
import Editing
import Foundation
import Lifecycle
import ModelAssets
import Permissions
import Recognition
import Support
import SwiftUI
import UI
import os

/// The single composition root of the iPhone and iPad app. Every concrete
/// operating-system service is constructed here; everything downstream receives
/// protocols (ADR 0027).
@MainActor
struct IOSComposition {
    enum Mode: String {
        case live
        /// Deterministic fakes for UI tests. Only honoured in Debug builds.
        case uiTesting
    }

    static let uiTestingArgument = "-LemmeTypeUITesting"

    let mode: Mode
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
        return Services(
            permissionChecker: checker,
            permissionRequester: SystemPermissionRequester(),
            preferences: preferences,
            audioCapture: AudioCaptureService(
                source: AVAudioSessionSource(), storage: .makeDefault(), permissions: checker,
                diagnostics: diagnostics),
            speechAuthorizer: authorizer,
            engines: [
                AppleSpeechEngine(authorizer: authorizer, language: { preferences.dictationLanguage }),
                WhisperEngine(
                    assets: modelAssets, hardware: hardware,
                    availableMemory: availableMemory,
                    settings: { whisperSettings(preferences: preferences, conditions: conditions.current) }),
            ],
            modelAssets: modelAssets,
            textCopier: ExpiringTextCopier(
                writer: UIPasteboardWriter(), lifetime: { CopiedTextLifetime.stored(in: .standard) }),
            rewriter: FoundationModelsRewriter(),
            personalizationStore: FilePersonalizationStore.makeDefault(diagnostics: diagnostics),
            historyStore: FileDictationHistoryStore.makeDefault(),
            conditions: conditions,
            diagnostics: diagnostics,
            hardware: hardware,
            copiedTextLifetime: { CopiedTextLifetime.stored(in: .standard) })
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
            residency: residency, diagnostics: diagnostics, limits: services.limits)
        let permissions = PermissionsModel(
            checker: services.permissionChecker, requester: services.permissionRequester, diagnostics: diagnostics)
        let dictation = DictationSettingsModel(
            engines: services.engines, modelAssets: services.modelAssets, preferences: preferences,
            speechAuthorizer: services.speechAuthorizer, diagnostics: diagnostics, hardware: services.hardware)
        let modes = ModesSettingsModel(
            personalization: personalization, preferences: preferences,
            engines: services.engines.map(\.descriptor.id), languages: dictation.languageChoices,
            runningApplications: { [] }, applicationName: { _ in nil }, diagnostics: diagnostics)
        let models = ModelsSettingsModel(
            modelAssets: services.modelAssets, preferences: preferences, engines: services.engines,
            hardware: services.hardware, conditions: conditions.current, diagnostics: diagnostics)
        models.onModelsChanged = { [weak dictation] in dictation?.refreshInBackground() }
        let history = HistorySettingsModel(
            history: DictationHistoryService(
                store: services.historyStore, preferences: preferences, diagnostics: diagnostics),
            copier: services.textCopier)
        let privacy = PrivacyOverviewModel(
            history: history, personalization: personalization, modes: modes, capture: services.audioCapture,
            modelAssets: services.modelAssets, clearDiagnostics: { diagnostics.removeAll() })
        let launchRequests = LaunchRequestInbox()
        let checker = services.permissionChecker
        let requester = services.permissionRequester
        let quick = QuickDictationModel(
            recorder: recorder, feedback: feedback,
            microphoneStatus: { checker.status(for: .microphone) },
            requestMicrophone: { await requester.requestMicrophoneAccess() },
            openSettings: { requester.openSystemSettings(for: .microphone) },
            lifetime: services.copiedTextLifetime, launchRequests: launchRequests)
        return IOSComposition(
            mode: mode, launchRequests: launchRequests, recorder: recorder, quick: quick, dictation: dictation,
            models: models, personalization: personalization, modes: modes, privacy: privacy,
            permissions: permissions, residency: residency, conditions: conditions,
            audioCapture: services.audioCapture)
    }

    // MARK: Running

    func rootView() -> some View {
        MobileRootView(
            quick: quick, dictation: dictation,
            settings: MobileSettingsView(
                dictation: dictation, models: models, personalization: personalization, modes: modes,
                privacy: privacy, permissions: permissions))
    }

    /// Cleans up after a crash, loads saved data, and follows the system's memory
    /// and heat for as long as the app runs.
    func start() async {
        await audioCapture.purgeLeftovers()
        await personalization.load()
        await dictation.refresh()
        await models.refresh()
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
