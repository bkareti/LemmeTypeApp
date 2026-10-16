import AVFoundation
import ApplicationServices
import Domain

/// Reads Microphone and Accessibility state from macOS. Never prompts.
public struct SystemPermissionChecker: PermissionChecking {
    public init() {}

    public func status(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .microphone:
            Self.status(from: AVCaptureDevice.authorizationStatus(for: .audio))
        case .accessibility:
            Self.accessibilityStatus(isTrusted: AXIsProcessTrusted())
        }
    }

    static func status(from authorization: AVAuthorizationStatus) -> PermissionStatus {
        switch authorization {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .notDetermined
        }
    }

    /// macOS only reports whether the process is trusted, so an untrusted
    /// process cannot be told apart from one that was never asked.
    static func accessibilityStatus(isTrusted: Bool) -> PermissionStatus {
        isTrusted ? .granted : .notDetermined
    }
}
