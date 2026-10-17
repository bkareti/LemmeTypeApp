import Carbon.HIToolbox
import CoreGraphics
import Domain

/// Posts ⌘V through the HID event tap, which reaches the frontmost app.
/// Needs Accessibility trust only (not Input Monitoring).
///
/// Uses the key in the ANSI "V" position; layouts that move V without a
/// "⌘ QWERTY" variant (plain Dvorak) are a documented limitation.
public struct SystemPasteKeystroke: PasteKeystrokePosting {
    public init() {}

    public func postPaste() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        // Explicit flags so modifiers still held from the shortcut don't turn
        // this into another command.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
