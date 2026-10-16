import Domain

extension PermissionKind {
    var displayName: String {
        switch self {
        case .microphone: String(localized: "Microphone", bundle: .module)
        case .accessibility: String(localized: "Accessibility", bundle: .module)
        }
    }

    /// Why LemmeType needs the permission. Describes LemmeType's own behaviour,
    /// never something only macOS could guarantee.
    var explanation: String {
        switch self {
        case .microphone:
            String(
                localized: """
                    LemmeType listens only while you use your dictation shortcut. \
                    Audio is processed on this Mac and is not kept after transcription.
                    """,
                bundle: .module
            )
        case .accessibility:
            String(
                localized: """
                    Accessibility lets LemmeType find the text field you were typing in \
                    and insert your dictated text there. Without it, LemmeType can record \
                    but cannot insert text.
                    """,
                bundle: .module
            )
        }
    }
}

extension PermissionStatus {
    var displayName: String {
        switch self {
        case .notRequested: String(localized: "Not requested", bundle: .module)
        case .granted: String(localized: "Granted", bundle: .module)
        case .denied: String(localized: "Denied", bundle: .module)
        case .restricted: String(localized: "Restricted", bundle: .module)
        case .notGranted: String(localized: "Not granted", bundle: .module)
        }
    }

    /// Extra guidance shown under the status, if any.
    var guidance: String? {
        switch self {
        case .denied:
            String(localized: "Turn it on in System Settings › Privacy & Security.", bundle: .module)
        case .restricted:
            String(localized: "A device policy blocks this permission. Contact your administrator.", bundle: .module)
        case .notGranted, .notRequested, .granted:
            nil
        }
    }
}

extension Capability {
    var displayName: String {
        switch self {
        case .recording: String(localized: "Dictation recording", bundle: .module)
        case .textInsertion: String(localized: "Text insertion", bundle: .module)
        }
    }
}

extension PermissionsModel.Action {
    func title(for permission: PermissionKind) -> String {
        switch (self, permission) {
        case (.request, .microphone): String(localized: "Allow Microphone Access…", bundle: .module)
        case (.request, .accessibility): String(localized: "Allow Accessibility Access…", bundle: .module)
        case (.openSystemSettings, _): String(localized: "Open System Settings…", bundle: .module)
        }
    }
}
