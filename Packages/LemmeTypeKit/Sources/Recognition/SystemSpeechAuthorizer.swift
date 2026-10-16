import AppKit
import Domain
import Speech
import Support

/// Speech-recognition authorization from macOS.
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

    public func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        else { return }
        NSWorkspace.shared.open(url)
    }

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
