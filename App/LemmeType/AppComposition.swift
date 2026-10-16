import Audio
import Domain
import Permissions
import Support
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

    let mode: Mode
    let permissionChecker: any PermissionChecking
    let audioDeviceLister: any AudioDeviceListing
    let buildInfo: BuildInfo

    static func make(arguments: [String], infoDictionary: [String: Any]?) -> AppComposition {
        let buildInfo = BuildInfo(infoDictionary: infoDictionary)
        #if DEBUG
            if arguments.contains(uiTestingArgument) {
                return uiTesting(buildInfo: buildInfo)
            }
        #endif
        return live(buildInfo: buildInfo)
    }

    static func live(buildInfo: BuildInfo) -> AppComposition {
        AppComposition(
            mode: .live,
            permissionChecker: SystemPermissionChecker(),
            audioDeviceLister: CaptureDeviceLister(),
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
}
