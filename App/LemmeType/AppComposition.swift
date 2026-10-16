import Audio
import Domain
import Lifecycle
import Permissions
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

    let mode: Mode
    let permissionChecker: any PermissionChecking
    let audioDeviceLister: any AudioDeviceListing
    let loginItems: any LoginItemManaging
    let buildInfo: BuildInfo
    var showsSettingsOnLaunch = false

    static func make(arguments: [String], infoDictionary: [String: Any]?) -> AppComposition {
        let buildInfo = BuildInfo(infoDictionary: infoDictionary)
        #if DEBUG
            var composition =
                arguments.contains(uiTestingArgument) ? uiTesting(buildInfo: buildInfo) : live(buildInfo: buildInfo)
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
            audioDeviceLister: CaptureDeviceLister(),
            loginItems: SystemLoginItemManager(),
            buildInfo: buildInfo
        )
    }

    #if DEBUG
        static func uiTesting(buildInfo: BuildInfo) -> AppComposition {
            AppComposition(
                mode: .uiTesting,
                permissionChecker: FakePermissionChecker(statuses: [
                    .microphone: .granted,
                    .accessibility: .notDetermined,
                ]),
                audioDeviceLister: FakeAudioDeviceLister(devices: [
                    AudioInputDevice(id: "ui-test-default", name: "UI Test Microphone", isSystemDefault: true),
                    AudioInputDevice(id: "ui-test-usb", name: "UI Test USB Microphone", isSystemDefault: false),
                ]),
                loginItems: FakeLoginItemManager(status: .disabled),
                buildInfo: buildInfo
            )
        }
    #endif

    func makeStatusViewModel() -> StatusViewModel {
        StatusViewModel(
            permissionChecker: permissionChecker,
            audioDeviceLister: audioDeviceLister,
            buildInfo: buildInfo
        )
    }

    func makeAppController() -> AppController {
        let general = GeneralSettingsModel(loginItems: loginItems, buildInfo: buildInfo)
        let status = makeStatusViewModel()
        let settings = SettingsWindowController {
            AnyView(SettingsView(general: general, status: status))
        }
        return AppController(settings: settings)
    }
}
