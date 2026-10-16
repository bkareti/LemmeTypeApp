import Audio
import Domain
import Lifecycle
import Permissions
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
        AppComposition(
            mode: .live,
            permissionChecker: SystemPermissionChecker(),
            permissionRequester: SystemPermissionRequester(),
            preferences: UserDefaultsPreferences(),
            audioDeviceLister: CaptureDeviceLister(),
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
                loginItems: FakeLoginItemManager(status: .disabled),
                hotKeyRegistrar: CarbonHotKeyRegistrar(),
                targetCapturer: FakeTargetCapturer(),
                buildInfo: buildInfo
            )
        }
    #endif

    func makeAppController() -> AppController {
        let permissions = PermissionsModel(checker: permissionChecker, requester: permissionRequester)
        let general = GeneralSettingsModel(loginItems: loginItems, buildInfo: buildInfo)
        let activation = ActivationController(
            registrar: hotKeyRegistrar,
            targetCapturer: targetCapturer,
            shortcut: preferences.dictationShortcut ?? .defaultDictation,
            mode: preferences.activationMode
        )
        let shortcut = ShortcutSettingsModel(controller: activation, preferences: preferences)
        let navigation = SettingsNavigation()
        let settings = ManagedWindowController(
            identifier: "settings",
            title: String(localized: "LemmeType Settings")
        ) {
            AnyView(
                SettingsView(general: general, shortcut: shortcut, permissions: permissions, navigation: navigation))
        }
        return AppController(
            permissions: permissions,
            preferences: preferences,
            activation: activation,
            shortcut: shortcut,
            navigation: navigation,
            settings: settings
        )
    }
}
