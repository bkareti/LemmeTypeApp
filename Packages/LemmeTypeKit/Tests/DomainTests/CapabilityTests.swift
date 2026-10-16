import Domain
import Testing

struct CapabilityTests {
    @Test func recordingNeedsMicrophoneAndInsertionNeedsAccessibility() {
        #expect(Capability.recording.requiredPermission == .microphone)
        #expect(Capability.textInsertion.requiredPermission == .accessibility)
    }
}
