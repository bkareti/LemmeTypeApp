import AVFoundation
import Domain

#if os(macOS)
    import ApplicationServices
#endif

/// Reads Microphone state (and, on the Mac, Accessibility state) from the
/// system. Never prompts.
public struct SystemPermissionChecker: PermissionChecking {
    public init() {}

    public func status(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .microphone:
            Self.microphoneStatus()
        case .accessibility:
            Self.currentAccessibilityStatus()
        }
    }

    static func status(from authorization: AVAuthorizationStatus) -> PermissionStatus {
        switch authorization {
        case .notDetermined: .notRequested
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .notGranted
        }
    }

    /// macOS only reports whether the process is trusted, so an untrusted
    /// process cannot be told apart from one that was never asked or was denied.
    static func accessibilityStatus(isTrusted: Bool) -> PermissionStatus {
        isTrusted ? .granted : .notGranted
    }

    #if os(macOS)
        private static func microphoneStatus() -> PermissionStatus {
            status(from: AVCaptureDevice.authorizationStatus(for: .audio))
        }

        private static func currentAccessibilityStatus() -> PermissionStatus {
            accessibilityStatus(isTrusted: AXIsProcessTrusted())
        }
    #else
        /// iOS reports only whether the user was asked, allowed, or denied; a
        /// configuration profile cannot be told apart from a denial.
        static func status(from permission: AVAudioApplication.recordPermission) -> PermissionStatus {
            switch permission {
            case .undetermined: .notRequested
            case .granted: .granted
            case .denied: .denied
            @unknown default: .notGranted
            }
        }

        private static func microphoneStatus() -> PermissionStatus {
            status(from: AVAudioApplication.shared.recordPermission)
        }

        /// There is no Accessibility trust on iOS; LemmeType never asks for it there.
        private static func currentAccessibilityStatus() -> PermissionStatus {
            .notGranted
        }
    #endif
}
