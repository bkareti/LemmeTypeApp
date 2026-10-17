/// Why LemmeType reads text near the cursor (E3-S1,
/// docs/decisions/0017-cursor-context.md).
public enum ContextPurpose: String, Sendable {
    /// Bounded text around the caret, to fit dictation into the sentence.
    case formatting
    /// The selected text, which voice editing rewrites.
    case editing
}

/// A small piece of text around the caret, read once when a LemmeType
/// shortcut is pressed (docs/decisions/0017-cursor-context.md).
///
/// In memory only and owned by one session: it is never logged, persisted,
/// or put in diagnostics. `description` is redacted so string interpolation
/// cannot leak it by accident.
public struct CursorContext: Equatable, Sendable {
    /// Upper bounds in UTF-16 code units (the unit Accessibility uses).
    public static let maxPrecedingLength = 240
    public static let maxFollowingLength = 40
    public static let maxSelectionLength = 4_000

    /// Text immediately before the selection (or caret), at most
    /// ``maxPrecedingLength``. Empty at the start of the field.
    public let precedingText: String
    /// Text immediately after the selection, at most ``maxFollowingLength``.
    public let followingText: String
    /// The selection (or caret) when the shortcut was pressed.
    public let selection: TextSelection
    /// The selected text; only captured for ``ContextPurpose/editing``.
    public let selectedText: String?

    /// Returns `nil` when a value exceeds its bound: callers must read bounded
    /// ranges, and an over-long selection is refused rather than truncated.
    public init?(
        precedingText: String, followingText: String, selection: TextSelection, selectedText: String? = nil
    ) {
        guard precedingText.utf16.count <= Self.maxPrecedingLength,
            followingText.utf16.count <= Self.maxFollowingLength,
            (selectedText?.utf16.count ?? 0) <= Self.maxSelectionLength
        else { return nil }
        self.precedingText = precedingText
        self.followingText = followingText
        self.selection = selection
        self.selectedText = selectedText
    }
}

extension CursorContext: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "CursorContext(redacted)" }
    public var debugDescription: String { description }
}

/// Why context was not captured. Raw values are stable diagnostics identifiers.
public enum ContextBlockReason: String, CaseIterable, Sendable {
    /// Formatting context is switched off in Settings.
    case disabled
    /// Voice editing is switched off in Settings.
    case editingDisabled = "editing-disabled"
    /// The user excluded this app.
    case excludedApp = "excluded-app"
    /// A built-in sensitive app (password manager, Keychain).
    case sensitiveApp = "sensitive-app"
    /// The focused field is a password field.
    case secureField = "secure-field"
    /// macOS reports secure keyboard entry.
    case secureInput = "secure-input"
    /// LemmeType is not trusted for Accessibility.
    case noAccessibility = "no-accessibility"
    /// No focused element, or it does not expose its selection or text.
    case unreadable
    /// Editing needs a selection and there was none.
    case noSelection = "no-selection"
    /// The selection is longer than ``CursorContext/maxSelectionLength``.
    case selectionTooLong = "selection-too-long"
}

/// The result of trying to capture context for one activation.
public enum ContextCapture: Equatable, Sendable {
    /// Nothing was asked for (for example a start from the menu).
    case notRequested
    case captured(CursorContext, purpose: ContextPurpose)
    case blocked(ContextBlockReason, purpose: ContextPurpose)

    public var context: CursorContext? {
        if case .captured(let context, _) = self { return context }
        return nil
    }

    /// Stable lowercase name for diagnostics; never contains text.
    public var identifier: String {
        switch self {
        case .notRequested: "not-requested"
        case .captured: "captured"
        case .blocked(let reason, _): reason.rawValue
        }
    }
}
