import Domain
import TestSupport
import Testing

/// The fakes are the replacement seam for OS services; they must behave like
/// macOS where it matters (no re-prompting after a decision).
struct FakeServiceTests {
    @Test func defaultsMatchAFreshInstall() {
        let permissions = FakePermissions()

        #expect(permissions.status(for: .microphone) == .notRequested)
        #expect(permissions.status(for: .accessibility) == .notGranted)
    }

    @Test func microphoneIsPromptedOnlyOnce() async {
        let permissions = FakePermissions(microphoneAnswer: .denied)

        #expect(await permissions.requestMicrophoneAccess() == .denied)
        #expect(await permissions.requestMicrophoneAccess() == .denied)
        #expect(permissions.microphoneRequestCount == 1)
    }

    @Test func fakeAudioDeviceListerReturnsConfiguredDevices() {
        let device = AudioInputDevice(id: "fake", name: "Fake Mic", isSystemDefault: true)
        let lister: any AudioDeviceListing = FakeAudioDeviceLister(devices: [device])

        #expect(lister.availableInputDevices() == [device])
    }
}
