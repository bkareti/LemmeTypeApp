import Foundation

/// A copy of everything on the clipboard, held in memory only for the
/// duration of one paste and never logged.
public struct PasteboardSnapshot: Sendable {
    /// Each item's data by type identifier.
    public let items: [[String: Data]]
    /// False when some item had a type whose data could not be read (for
    /// example a file promise), so restoring would lose data.
    public let isComplete: Bool

    public init(items: [[String: Data]], isComplete: Bool) {
        self.items = items
        self.isComplete = isComplete
    }
}

/// The general clipboard (E2-S8).
public protocol PasteboardAccessing: Sendable {
    /// Increases every time any app changes the clipboard.
    func changeCount() async -> Int
    func snapshot() async -> PasteboardSnapshot
    /// Replaces the clipboard with `text`, marked transient so clipboard
    /// managers skip it. Returns the new change count.
    func writeTransient(_ text: String) async -> Int
    /// Replaces the clipboard with `text` for the user to paste.
    func write(_ text: String) async
    func restore(_ snapshot: PasteboardSnapshot) async
}

/// Posts ⌘V to the frontmost app. Needs Accessibility trust only.
public protocol PasteKeystrokePosting: Sendable {
    func postPaste() -> Bool
}

/// What happens when direct insertion is not possible (E2-S8).
public enum ClipboardFallback: String, CaseIterable, Codable, Sendable {
    /// Paste through the clipboard, then restore what was there before.
    case pasteAndRestore = "paste-and-restore"
    /// Put the text on the clipboard and let the user paste it.
    case copyOnly = "copy-only"
    /// Do nothing automatically; offer Copy Text.
    case off
}

/// The user's clipboard-fallback setting.
public struct ClipboardFallbackPolicy: Equatable, Codable, Sendable {
    public var fallback: ClipboardFallback
    /// Seconds to wait before restoring the clipboard when the target's
    /// character count cannot be observed (so consumption can't be seen).
    public var restoreDelay: Double

    public init(fallback: ClipboardFallback = .pasteAndRestore, restoreDelay: Double = 0.5) {
        self.fallback = fallback
        self.restoreDelay = restoreDelay
    }

    public static let `default` = ClipboardFallbackPolicy()
    /// Choices offered in Settings.
    public static let restoreDelayChoices: [Double] = [0.25, 0.5, 1, 2]
}
