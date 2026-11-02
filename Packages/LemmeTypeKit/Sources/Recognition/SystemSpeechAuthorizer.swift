import Domain
import Speech
import Support

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Speech-recognition authorization from the system.
public struct SystemSpeechAuthorizer: SpeechRecognitionAuthorizing {
    public init() {}

    public func status() -> PermissionStatus {
        Self.status(from: SFSpeechRecognizer.authorizationStatus())
    }

    public func requestAuthorization() async -> PermissionStatus {
        guard status() == .notRequested else { return status() }
        let result = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let status = Self.status(from: result)
        Log.permissions.info("Speech recognition request finished: \(status.rawValue, privacy: .public)")
        return status
    }

    #if os(macOS)
        public func openSystemSettings() {
            guard
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            else { return }
            NSWorkspace.shared.open(url)
        }
    #else
        public func openSystemSettings() {
            Task { @MainActor in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                await UIApplication.shared.open(url)
            }
        }
    #endif

    static func status(from authorization: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch authorization {
        case .notDetermined: .notRequested
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
