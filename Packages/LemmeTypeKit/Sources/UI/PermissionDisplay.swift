import Domain

extension PermissionKind {
    var displayName: String {
        switch self {
        case .microphone: String(localized: "Microphone", bundle: .module)
        case .accessibility: String(localized: "Accessibility", bundle: .module)
        }
    }
}

extension PermissionStatus {
    /// Wording deliberately avoids claims macOS cannot back up: "Not granted"
    /// rather than "Denied" when the system cannot tell the difference.
    var displayName: String {
        switch self {
        case .notDetermined: String(localized: "Not granted", bundle: .module)
        case .granted: String(localized: "Granted", bundle: .module)
        case .denied: String(localized: "Denied", bundle: .module)
        case .restricted: String(localized: "Restricted", bundle: .module)
        }
    }
}
