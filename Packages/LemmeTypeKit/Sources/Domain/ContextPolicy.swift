/// When LemmeType may read text near the cursor (E3-S1,
/// docs/decisions/0017-cursor-context.md). App-level rules only; field-level
/// checks (password fields, secure input) happen in ``CursorContextReader``.
public struct ContextPolicy: Equatable, Sendable {
    /// Use preceding/following text to fit dictation in. Off by default.
    public var usesFormattingContext: Bool
    /// Allow the voice-editing shortcut to read the selection. On by default:
    /// nothing is read until that shortcut is pressed.
    public var allowsVoiceEditing: Bool
    /// Bundle identifiers the user excluded from every kind of context.
    public var excludedApplications: Set<String>

    public init(
        usesFormattingContext: Bool = false,
        allowsVoiceEditing: Bool = true,
        excludedApplications: Set<String> = []
    ) {
        self.usesFormattingContext = usesFormattingContext
        self.allowsVoiceEditing = allowsVoiceEditing
        self.excludedApplications = excludedApplications
    }

    public static let `default` = ContextPolicy()

    /// Apps that can never provide context: password managers and the
    /// system's credential stores. Not user-editable.
    public static let sensitiveApplications: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc",
        "com.keepersecurity.keeper",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    public static func isSensitive(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return sensitiveApplications.contains(bundleIdentifier)
    }

    /// Why context must not be read in this app for `purpose`, or `nil` if it may.
    /// An unknown app (no bundle identifier) is treated like any other app.
    public func blockReason(for purpose: ContextPurpose, bundleIdentifier: String?) -> ContextBlockReason? {
        if Self.isSensitive(bundleIdentifier) { return .sensitiveApp }
        if let bundleIdentifier, excludedApplications.contains(bundleIdentifier) { return .excludedApp }
        switch purpose {
        case .formatting: return usesFormattingContext ? nil : .disabled
        case .editing: return allowsVoiceEditing ? nil : .editingDisabled
        }
    }
}
