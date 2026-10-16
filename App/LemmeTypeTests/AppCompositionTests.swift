import Audio
import Permissions
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
        #expect(composition.audioDeviceLister is CaptureDeviceLister)
    }

    @Test func uiTestingArgumentReplacesOperatingSystemServices() {
        let composition = AppComposition.make(
            arguments: ["LemmeType", AppComposition.uiTestingArgument],
            infoDictionary: info
        )

        #expect(composition.mode == .uiTesting)
        #expect(composition.permissionChecker is FakePermissionChecker)
        #expect(composition.audioDeviceLister is FakeAudioDeviceLister)
    }

    @Test func buildInfoComesFromTheBundle() {
        let composition = AppComposition.make(arguments: [], infoDictionary: info)

        #expect(composition.buildInfo.displayString == "9.9.9 (99)")
    }

    @Test func statusViewModelReceivesInjectedServices() {
        let model = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1")).makeStatusViewModel()

        #expect(model.inputDeviceCount == 2)
        #expect(model.permissionRows.first { $0.permission == .microphone }?.status == .granted)
    }
}
