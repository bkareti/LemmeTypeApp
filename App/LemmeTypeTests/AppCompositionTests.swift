import Audio
import Lifecycle
import Permissions
import Shortcuts
import Support
import TestSupport
import Testing

@testable import LemmeType

@MainActor
struct AppCompositionTests {
    private let info: [String: Any] = ["CFBundleShortVersionString": "9.9.9", "CFBundleVersion": "99"]

    @Test func defaultLaunchUsesRealServices() {
        let composition = AppComposition.make(arguments: ["LemmeType"], infoDictionary: info)

        #expect(composition.mode == .live)
        #expect(composition.permissionChecker is SystemPermissionChecker)
        #expect(composition.permissionRequester is SystemPermissionRequester)
        #expect(composition.preferences is UserDefaultsPreferences)
        #expect(composition.audioDeviceLister is CaptureDeviceLister)
        #expect(composition.loginItems is SystemLoginItemManager)
        #expect(composition.hotKeyRegistrar is CarbonHotKeyRegistrar)
        #expect(composition.targetCapturer is AccessibilityTargetCapturer)
    }

    @Test func uiTestingArgumentReplacesOperatingSystemServices() {
        let composition = AppComposition.make(
            arguments: ["LemmeType", AppComposition.uiTestingArgument],
            infoDictionary: info
        )

        #expect(composition.mode == .uiTesting)
        #expect(composition.permissionChecker is FakePermissions)
        #expect(composition.permissionRequester is FakePermissions)
        #expect(composition.preferences is FakePreferences)
        #expect(composition.audioDeviceLister is FakeAudioDeviceLister)
        #expect(composition.loginItems is FakeLoginItemManager)
        #expect(composition.targetCapturer is FakeTargetCapturer)
        #expect(composition.preferences.hasCompletedOnboarding)
    }

    @Test func freshInstallArgumentStartsWithOnboardingPending() {
        let composition = AppComposition.make(
            arguments: [AppComposition.uiTestingArgument, AppComposition.freshInstallArgument],
            infoDictionary: info
        )

        #expect(!composition.preferences.hasCompletedOnboarding)
        #expect(composition.permissionChecker.status(for: .microphone) == .notRequested)
    }

    @Test func showSettingsArgumentIsHonouredInDebug() {
        let plain = AppComposition.make(arguments: [], infoDictionary: info)
        let showing = AppComposition.make(arguments: [AppComposition.showSettingsArgument], infoDictionary: info)

        #expect(!plain.showsSettingsOnLaunch)
        #expect(showing.showsSettingsOnLaunch)
    }

    @Test func buildInfoComesFromTheBundle() {
        let composition = AppComposition.make(arguments: [], infoDictionary: info)

        #expect(composition.buildInfo.displayString == "9.9.9 (99)")
    }

    @Test func controllerSharesOnePermissionsModel() {
        let controller = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1")).makeAppController()

        #expect(controller.onboardingModel.permissions === controller.permissions)
        #expect(controller.permissions.status(for: .microphone) == .granted)
    }
}
