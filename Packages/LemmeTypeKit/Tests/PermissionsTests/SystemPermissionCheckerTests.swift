import AVFoundation
import Domain
import Testing

@testable import Permissions

/// Exercises the status mapping only; never queries the host's real TCC state.
struct SystemPermissionCheckerTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionStatus.notRequested),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsMicrophoneAuthorization(authorization: AVAuthorizationStatus, expected: PermissionStatus) {
        #expect(SystemPermissionChecker.status(from: authorization) == expected)
    }

    @Test func untrustedAccessibilityIsNotReportedAsDenied() {
        #expect(SystemPermissionChecker.accessibilityStatus(isTrusted: true) == .granted)
        #expect(SystemPermissionChecker.accessibilityStatus(isTrusted: false) == .notGranted)
    }
}

struct SystemPermissionRequesterTests {
    @Test func settingsLinksPointAtTheMatchingPrivacyPane() {
        #expect(
            SystemPermissionRequester.settingsURL(for: .microphone)?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #expect(
            SystemPermissionRequester.settingsURL(for: .accessibility)?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
