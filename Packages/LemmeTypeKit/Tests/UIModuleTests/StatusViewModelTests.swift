import Domain
import Support
import TestSupport
import Testing

@testable import UI

@MainActor
struct StatusViewModelTests {
    @Test func showsEveryPermissionFromInjectedChecker() {
        let model = makeModel(statuses: [.microphone: .granted, .accessibility: .notDetermined])

        #expect(
            model.permissionRows == [
                .init(permission: .microphone, status: .granted),
                .init(permission: .accessibility, status: .notDetermined),
            ])
    }

    @Test func countsInjectedInputDevices() {
        let devices = [
            AudioInputDevice(id: "1", name: "One", isSystemDefault: true),
            AudioInputDevice(id: "2", name: "Two", isSystemDefault: false),
        ]
        let model = makeModel(devices: devices)

        #expect(model.inputDeviceCount == 2)
    }

    @Test func unknownAccessibilityStateIsShownAsNotGranted() {
        #expect(PermissionStatus.notDetermined.displayName == "Not granted")
    }

    private func makeModel(
        statuses: [PermissionKind: PermissionStatus] = [:],
        devices: [AudioInputDevice] = []
    ) -> StatusViewModel {
        StatusViewModel(
            permissionChecker: FakePermissionChecker(statuses: statuses),
            audioDeviceLister: FakeAudioDeviceLister(devices: devices),
            buildInfo: BuildInfo(version: "0.0.0", build: "0")
        )
    }
}
