import AVFoundation
import Domain
import Support

#if os(macOS)
    import AppKit
    import ApplicationServices
#else
    import UIKit
#endif

/// Requests Microphone access (and, on the Mac, Accessibility access) from the system.
public struct SystemPermissionRequester: PermissionRequesting {
    private let checker = SystemPermissionChecker()

    public init() {}

    public func requestMicrophoneAccess() async -> PermissionStatus {
        // The system only shows the prompt for an undetermined status, so a
        // denied user is never prompted again.
        guard checker.status(for: .microphone) == .notRequested else {
            return checker.status(for: .microphone)
        }
        await Self.askForMicrophone()
        let status = checker.status(for: .microphone)
        Log.permissions.info("Microphone request finished: \(status.rawValue, privacy: .public)")
        return status
    }

    #if os(macOS)
        private static func askForMicrophone() async {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
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
    #else
        private static func askForMicrophone() async {
            _ = await AVAudioApplication.requestRecordPermission()
        }

        /// Accessibility trust does not exist on iOS.
        public func requestAccessibilityAccess() {}

        /// iOS has one Settings page per app; every permission lives there.
        public func openSystemSettings(for permission: PermissionKind) {
            Log.permissions.info("Opening Settings for \(permission.rawValue, privacy: .public)")
            Task { @MainActor in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                await UIApplication.shared.open(url)
            }
        }
    #endif
}
