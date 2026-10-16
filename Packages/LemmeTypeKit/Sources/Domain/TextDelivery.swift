/// How final text reached the user.
public enum DeliveryMethod: String, Sendable {
    /// Inserted into the captured field through Accessibility.
    case accessibility
    /// Pasted through the clipboard, with the previous clipboard restored.
    case paste
    /// Left on the clipboard for the user to paste.
    case copied
}

/// Why text could not be delivered automatically. Raw values are stable
/// diagnostics identifiers.
public enum DeliveryProblem: String, Sendable {
    /// The focused app or field changed since dictation started.
    case targetChanged = "target-changed"
    /// The target does not accept inserted text.
    case unsupported
    /// Accessibility trust is missing.
    case permissionMissing = "permission-missing"
    /// The target is a password field; nothing is inserted or read.
    case secureField = "secure-field"
    /// Dictation started without a target (for example from the menu).
    case noTarget = "no-target"
    /// Insertion was attempted and failed; nothing was inserted.
    case failed
}

public enum DeliveryOutcome: Equatable, Sendable {
    case delivered(DeliveryMethod)
    case problem(DeliveryProblem)
}

/// Delivers final text to the field captured at activation (E2-S7, E2-S8).
public protocol TextDelivering: Sendable {
    /// Delivers `text` at most once. Never reads secure fields.
    func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome
}

/// Puts text on the clipboard when the user asks to copy it.
public protocol TextCopying: Sendable {
    func copy(_ text: String) async
}
