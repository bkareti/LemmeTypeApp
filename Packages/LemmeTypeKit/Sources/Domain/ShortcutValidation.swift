/// Rules a user-chosen dictation shortcut must satisfy.
public enum ShortcutValidation {
    public enum Problem: String, Equatable, Sendable {
        /// Needs ⌘, ⌥, or ⌃; Shift alone would capture ordinary typing.
        case missingModifier
        /// The key is itself a modifier (or Caps Lock / Fn).
        case modifierOnly
        /// Escape is reserved for cancelling dictation.
        case reservedForCancel
        /// Conflicts with a standard macOS shortcut.
        case systemShortcut
    }

    public static func problem(with shortcut: KeyboardShortcut) -> Problem? {
        if KeyCode.modifierKeys.contains(shortcut.keyCode) { return .modifierOnly }
        if shortcut.keyCode == KeyCode.escape { return .reservedForCancel }
        if shortcut.modifiers.isDisjoint(with: [.command, .option, .control]) { return .missingModifier }
        if systemShortcuts.contains(Signature(shortcut)) { return .systemShortcut }
        return nil
    }

    private struct Signature: Hashable {
        let keyCode: UInt16
        let modifiers: KeyboardShortcut.Modifiers

        init(_ keyCode: UInt16, _ modifiers: KeyboardShortcut.Modifiers) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        init(_ shortcut: KeyboardShortcut) {
            self.init(shortcut.keyCode, shortcut.modifiers)
        }
    }

    private static let systemShortcuts: Set<Signature> = [
        Signature(KeyCode.ansiQ, .command),
        Signature(KeyCode.ansiW, .command),
        Signature(KeyCode.ansiH, .command),
        Signature(KeyCode.ansiM, .command),
        Signature(KeyCode.tab, .command),
        Signature(KeyCode.grave, .command),
        Signature(KeyCode.space, .command),
        Signature(KeyCode.space, .control),
        Signature(KeyCode.space, [.command, .option]),
        Signature(KeyCode.ansi3, [.command, .shift]),
        Signature(KeyCode.ansi4, [.command, .shift]),
        Signature(KeyCode.ansi5, [.command, .shift]),
    ]
}
