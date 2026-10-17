import Audio
import Delivery
import Domain
import Editing
import Foundation
import Lifecycle
import ModelAssets
import Permissions
import Recognition
import Shortcuts
import Support
import SwiftUI
import UI

#if DEBUG
    import TestSupport
#endif

/// The single composition root. Every concrete operating-system service is
/// constructed here and nowhere else; everything downstream receives protocols.
@MainActor
struct AppComposition {
    enum Mode: String {
        /// Real macOS services.
        case live
        /// Deterministic fakes for UI tests. Only honoured in Debug builds.
        case uiTesting
    }

    /// Launch argument that switches a Debug build to fake services.
    static let uiTestingArgument = "-LemmeTypeUITesting"
    /// Debug-only launch argument that opens Settings at launch. XCUITest cannot
    /// reliably click items in a status-bar menu, so UI tests use this instead.
    static let showSettingsArgument = "-LemmeTypeShowSettings"
    /// Debug-only launch argument for UI tests: start as a fresh install
    /// (onboarding not completed, no permissions granted).
    static let freshInstallArgument = "-LemmeTypeFreshInstall"

    var mode: Mode
    var permissionChecker: any PermissionChecking
    var permissionRequester: any PermissionRequesting
    var preferences: any AppPreferences
    var audioDeviceLister: any AudioDeviceListing
    var audioCapture: any AudioCapturing
    var speechAuthorizer: any SpeechRecognitionAuthorizing
    /// Every installed recognition engine, in recommendation order.
    var recognitionEngines: [any SpeechRecognitionEngine]
    var modelAssets: any ModelAssetManaging
    var textDelivery: any TextDelivering
    var textCopier: any TextCopying
    /// On-device rewriting for voice editing (ADR 0018).
    var textRewriter: any TextRewriting
    /// Vocabulary, replacements, and snippets on disk (ADR 0020).
    var personalizationStore: any PersonalizationStoring
    var diagnostics: DiagnosticsBuffer
    var loginItems: any LoginItemManaging
    var hotKeyRegistrar: any HotKeyRegistering
    var targetCapturer: any TargetCapturing
    var buildInfo: BuildInfo
    var showsSettingsOnLaunch = false

    static func make(arguments: [String], infoDictionary: [String: Any]?) -> AppComposition {
        let buildInfo = BuildInfo(infoDictionary: infoDictionary)
        #if DEBUG
            var composition =
                arguments.contains(uiTestingArgument)
                ? uiTesting(buildInfo: buildInfo, freshInstall: arguments.contains(freshInstallArgument))
                : live(buildInfo: buildInfo)
            composition.showsSettingsOnLaunch = arguments.contains(showSettingsArgument)
            return composition
        #else
            return live(buildInfo: buildInfo)
        #endif
    }

    static func live(buildInfo: BuildInfo) -> AppComposition {
        let permissionChecker = SystemPermissionChecker()
        let diagnostics = DiagnosticsBuffer()
        let preferences = UserDefaultsPreferences()
        let speechAuthorizer = SystemSpeechAuthorizer()
        let modelAssets = ModelAssetStore.makeDefault(diagnostics: diagnostics)
        return AppComposition(
            mode: .live,
            permissionChecker: permissionChecker,
            permissionRequester: SystemPermissionRequester(),
            preferences: preferences,
            audioDeviceLister: CaptureDeviceLister(),
            audioCapture: AudioCaptureService(
                source: AVAudioEngineSource(),
                storage: .makeDefault(),
                permissions: permissionChecker,
                diagnostics: diagnostics
            ),
            speechAuthorizer: speechAuthorizer,
            recognitionEngines: [
                AppleSpeechEngine(authorizer: speechAuthorizer, language: { preferences.dictationLanguage }),
                WhisperEngine(assets: modelAssets, settings: { whisperSettings(preferences: preferences) }),
            ],
            modelAssets: modelAssets,
            textDelivery: DictationTextDelivery(
                driver: SystemAccessibilityDriver(),
                pasteboard: SystemPasteboard(),
                keystroke: SystemPasteKeystroke(),
                policy: { preferences.clipboardFallback },
                diagnostics: diagnostics
            ),
            textCopier: PasteboardTextCopier(),
            textRewriter: FoundationModelsRewriter(),
            personalizationStore: FilePersonalizationStore.makeDefault(diagnostics: diagnostics),
            diagnostics: diagnostics,
            loginItems: SystemLoginItemManager(),
            hotKeyRegistrar: CarbonHotKeyRegistrar(),
            targetCapturer: makeTargetCapturer(preferences: preferences),
            buildInfo: buildInfo
        )
    }

    /// The Whisper model choice and the performance plan, read for every session (E5-S1, E5-S5).
    private nonisolated static func whisperSettings(preferences: any AppPreferences) -> WhisperRunSettings {
        let plan = PerformancePlan.make(
            profile: preferences.performanceProfile, conditions: .nominal, idleUnload: preferences.modelIdleUnload)
        return WhisperRunSettings(
            choice: preferences.whisperModel, order: plan.whisperModelOrder, threads: plan.inferenceThreads,
            usesGPU: plan.usesGPU)
    }

    /// Reads cursor context at activation only, under the current policy (ADR 0017).
    private static func makeTargetCapturer(preferences: any AppPreferences) -> AccessibilityTargetCapturer {
        let reader = CursorContextReader(driver: SystemAccessibilityDriver(), policy: { preferences.contextPolicy })
        return AccessibilityTargetCapturer(readContext: { reader.read(for: $0, purpose: $1) })
    }

    #if DEBUG
        /// Fake services. A fresh install starts with nothing granted and
        /// onboarding pending; otherwise Microphone is granted, Accessibility is
        /// not, and onboarding is complete. Requests succeed immediately.
        /// Hot keys are real (they need no permission) so UI tests can press them;
        /// the activation target is fake so no other app is inspected.
        static func uiTesting(buildInfo: BuildInfo, freshInstall: Bool = false) -> AppComposition {
            let diagnostics = DiagnosticsBuffer()
            // Records text instead of touching other apps or the clipboard.
            let delivery = FakeTextDelivery()
            let permissions = FakePermissions(
                statuses: freshInstall ? [:] : [.microphone: .granted],
                microphoneAnswer: .granted,
                grantsAccessibilityOnRequest: true
            )
            return AppComposition(
                mode: .uiTesting,
                permissionChecker: permissions,
                permissionRequester: permissions,
                preferences: FakePreferences(hasCompletedOnboarding: !freshInstall),
                audioDeviceLister: FakeAudioDeviceLister(devices: [
                    AudioInputDevice(id: "ui-test-default", name: "UI Test Microphone", isSystemDefault: true),
                    AudioInputDevice(id: "ui-test-usb", name: "UI Test USB Microphone", isSystemDefault: false),
                ]),
                audioCapture: AudioCaptureService(
                    source: FakeAudioSource(liveTone: true),
                    storage: AudioSessionStorage(
                        directory: FileManager.default.temporaryDirectory
                            .appendingPathComponent("LemmeTypeUITesting", isDirectory: true)),
                    permissions: permissions,
                    diagnostics: diagnostics
                ),
                speechAuthorizer: FakeSpeechAuthorizer(status: .granted),
                recognitionEngines: [
                    FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "hello from lemmetype")),
                    FakeRecognitionEngine(
                        id: .whisper, availability: .assetsMissing,
                        assets: .downloadable(.whisperBaseEnglish)),
                ],
                modelAssets: FakeModelAssetManager(),
                textDelivery: delivery,
                textCopier: delivery,
                textRewriter: FakeTextRewriter(),
                personalizationStore: FakePersonalizationStore(),
                diagnostics: diagnostics,
                loginItems: FakeLoginItemManager(status: .disabled),
                hotKeyRegistrar: CarbonHotKeyRegistrar(),
                targetCapturer: FakeTargetCapturer(),
                buildInfo: buildInfo
            )
        }
    #endif

    /// Recognition, writing mode, and delivery for each finished recording.
    func makeDictationProcessor() -> any DictationProcessing {
        TranscriptionPipeline(
            engines: recognitionEngines,
            write: TextCleaner.write,
            delivery: textDelivery,
            rewriter: textRewriter,
            copier: textCopier,
            diagnostics: diagnostics
        )
    }

    func makeAppController() -> AppController {
        let permissions = PermissionsModel(
            checker: permissionChecker, requester: permissionRequester, diagnostics: diagnostics)
        let general = GeneralSettingsModel(loginItems: loginItems, preferences: preferences, buildInfo: buildInfo)
        let activation = makeActivationController()
        let shortcut = ShortcutSettingsModel(controller: activation, preferences: preferences)
        let context = makeContextSettings(shortcut: shortcut)
        let audio = AudioSettingsModel(
            capture: audioCapture, deviceLister: audioDeviceLister, preferences: preferences)
        let navigation = SettingsNavigation()
        let personalization = PersonalizationModel(store: personalizationStore, diagnostics: diagnostics)
        let recorder = makeRecorder(personalization: personalization)
        let dictation = DictationSettingsModel(
            engines: recognitionEngines, modelAssets: modelAssets, preferences: preferences,
            speechAuthorizer: speechAuthorizer, diagnostics: diagnostics)
        let modes = makeModes(personalization: personalization, languages: dictation.languages)
        let models = makeModels(dictation: dictation)
        let diagnosticsModel = DiagnosticsModel(
            buffer: diagnostics, permissions: permissions, shortcut: shortcut, buildInfo: buildInfo)
        let settings = Self.makeSettingsWindow(
            SettingsView(
                general: general,
                dictation: dictation,
                shortcut: shortcut,
                context: context,
                personalization: personalization,
                modes: modes,
                models: models,
                audio: audio,
                permissions: permissions,
                diagnostics: diagnosticsModel,
                navigation: navigation
            ))
        return AppController(
            modelAssets: modelAssets,
            permissions: permissions,
            preferences: preferences,
            activation: activation,
            recorder: recorder,
            dictation: dictation,
            shortcut: shortcut,
            context: context,
            personalization: personalization,
            modes: modes,
            models: models,
            navigation: navigation,
            diagnostics: diagnostics,
            settings: settings
        )
    }

    /// The dictation shortcut and, when voice editing is on, its shortcut.
    private func makeActivationController() -> ActivationController {
        ActivationController(
            registrar: hotKeyRegistrar,
            targetCapturer: targetCapturer,
            shortcut: preferences.dictationShortcut ?? .defaultDictation,
            editShortcut: preferences.allowsVoiceEditing ? (preferences.voiceEditShortcut ?? .defaultVoiceEdit) : nil,
            mode: preferences.activationMode,
            diagnostics: diagnostics
        )
    }

    private func makeRecorder(personalization: PersonalizationModel) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: audioCapture,
            processor: makeDictationProcessor(),
            feedback: SystemRecordingFeedback(preferences: preferences),
            preferences: preferences,
            speechAuthorizer: speechAuthorizer,
            textCopier: textCopier,
            personalization: { [weak personalization] in personalization?.library ?? .empty },
            diagnostics: diagnostics
        )
    }

    private static func makeSettingsWindow(_ view: SettingsView) -> ManagedWindowController {
        ManagedWindowController(identifier: "settings", title: String(localized: "LemmeType Settings")) {
            AnyView(view)
        }
    }
}
