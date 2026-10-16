import Domain
import TestSupport
import Testing

/// The fakes are the replacement seam required by E1-S1; they must behave
/// predictably so other tests can rely on them.
struct FakeServiceTests {
    @Test func fakePermissionCheckerReturnsConfiguredStatus() {
        let checker: any PermissionChecking = FakePermissionChecker(statuses: [.microphone: .granted])

        #expect(checker.status(for: .microphone) == .granted)
        #expect(checker.status(for: .accessibility) == .notDetermined)
    }

    @Test func fakeAudioDeviceListerReturnsConfiguredDevices() {
        let device = AudioInputDevice(id: "fake", name: "Fake Mic", isSystemDefault: true)
        let lister: any AudioDeviceListing = FakeAudioDeviceLister(devices: [device])

        #expect(lister.availableInputDevices() == [device])
    }
}
