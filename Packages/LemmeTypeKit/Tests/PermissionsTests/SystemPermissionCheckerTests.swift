import AVFoundation
import Domain
import Testing

@testable import Permissions

/// Exercises the status mapping only; never queries the host's real TCC state.
struct SystemPermissionCheckerTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsMicrophoneAuthorization(authorization: AVAuthorizationStatus, expected: PermissionStatus) {
        #expect(SystemPermissionChecker.status(from: authorization) == expected)
    }

    @Test func untrustedAccessibilityIsNotReportedAsDenied() {
        #expect(SystemPermissionChecker.accessibilityStatus(isTrusted: true) == .granted)
        #expect(SystemPermissionChecker.accessibilityStatus(isTrusted: false) == .notDetermined)
    }
}
