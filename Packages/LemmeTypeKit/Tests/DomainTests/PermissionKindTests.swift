import Domain
import Testing

struct PermissionKindTests {
    @Test func onlyMicrophoneAndAccessibilityAreModelled() {
        #expect(PermissionKind.allCases == [.microphone, .accessibility])
    }
}
