import AVFoundation
import AppKit
import ApplicationServices
import Domain
import Support

/// Requests Microphone and Accessibility access from macOS.
public struct SystemPermissionRequester: PermissionRequesting {
    private let checker = SystemPermissionChecker()

    public init() {}

    public func requestMicrophoneAccess() async -> PermissionStatus {
        // AVFoundation only shows the prompt for an undetermined status, so a
        // denied user is never prompted again.
        guard checker.status(for: .microphone) == .notRequested else {
            return checker.status(for: .microphone)
        }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        let status = checker.status(for: .microphone)
        Log.permissions.info("Microphone request finished: \(status.rawValue, privacy: .public)")
        return status
    }

    public func requestAccessibilityAccess() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt;
        // the literal avoids importing a mutable global under strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.permissions.info("Accessibility prompt requested; trusted=\(trusted, privacy: .public)")
    }

    public func openSystemSettings(for permission: PermissionKind) {
        guard let url = Self.settingsURL(for: permission) else { return }
        Log.permissions.info("Opening System Settings for \(permission.rawValue, privacy: .public)")
        NSWorkspace.shared.open(url)
    }

    static func settingsURL(for permission: PermissionKind) -> URL? {
        let anchor =
            switch permission {
            case .microphone: "Privacy_Microphone"
            case .accessibility: "Privacy_Accessibility"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
