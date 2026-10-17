import Audio
import Delivery
import Domain
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
                WhisperEngine(assets: modelAssets),
            ],
            modelAssets: modelAssets,
            textDelivery: DictationTextDelivery(driver: SystemAccessibilityDriver(), diagnostics: diagnostics),
            textCopier: PasteboardTextCopier(),
            diagnostics: diagnostics,
            loginItems: SystemLoginItemManager(),
            hotKeyRegistrar: CarbonHotKeyRegistrar(),
            targetCapturer: AccessibilityTargetCapturer(),
            buildInfo: buildInfo
        )
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
            preferredEngine: { [preferences] in preferences.selectedEngine },
            write: TextCleaner.write,
            delivery: textDelivery,
            diagnostics: diagnostics
        )
    }

    func makeAppController() -> AppController {
        let permissions = PermissionsModel(
            checker: permissionChecker, requester: permissionRequester, diagnostics: diagnostics)
        let general = GeneralSettingsModel(loginItems: loginItems, preferences: preferences, buildInfo: buildInfo)
        let activation = ActivationController(
            registrar: hotKeyRegistrar,
            targetCapturer: targetCapturer,
            shortcut: preferences.dictationShortcut ?? .defaultDictation,
            mode: preferences.activationMode,
            diagnostics: diagnostics
        )
        let shortcut = ShortcutSettingsModel(controller: activation, preferences: preferences)
        let audio = AudioSettingsModel(
            capture: audioCapture, deviceLister: audioDeviceLister, preferences: preferences)
        let navigation = SettingsNavigation()
        let recorder = RecordingCoordinator(
            capture: audioCapture,
            processor: makeDictationProcessor(),
            feedback: SystemRecordingFeedback(preferences: preferences),
            preferences: preferences,
            speechAuthorizer: speechAuthorizer,
            textCopier: textCopier,
            diagnostics: diagnostics
        )
        let diagnosticsModel = DiagnosticsModel(
            buffer: diagnostics, permissions: permissions, shortcut: shortcut, buildInfo: buildInfo)
        let settings = ManagedWindowController(
            identifier: "settings",
            title: String(localized: "LemmeType Settings")
        ) {
            AnyView(
                SettingsView(
                    general: general,
                    shortcut: shortcut,
                    audio: audio,
                    permissions: permissions,
                    diagnostics: diagnosticsModel,
                    navigation: navigation
                ))
        }
        return AppController(
            modelAssets: modelAssets,
            permissions: permissions,
            preferences: preferences,
            activation: activation,
            recorder: recorder,
            shortcut: shortcut,
            navigation: navigation,
            diagnostics: diagnostics,
            settings: settings
        )
    }
}
