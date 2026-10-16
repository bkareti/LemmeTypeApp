import AppKit
import Domain

/// Captures the next key combination typed into LemmeType's own window. Uses a
/// local event monitor, so it sees only keys sent to LemmeType and needs no
/// Input Monitoring permission.
@MainActor
final class ShortcutRecorder {
    private var monitor: Any?

    /// - Parameters:
    ///   - onShortcut: Called with the captured combination.
    ///   - onCancel: Called when the user presses Escape on its own.
    func start(onShortcut: @escaping @MainActor (KeyboardShortcut) -> Void, onCancel: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = Self.modifiers(from: event.modifierFlags)
            MainActor.assumeIsolated {
                if event.keyCode == KeyCode.escape && modifiers.isEmpty {
                    onCancel()
                } else {
                    onShortcut(
                        KeyboardShortcut(
                            keyCode: event.keyCode,
                            modifiers: modifiers,
                            keyLabel: Self.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
                        ))
                }
            }
            return nil  // swallow the key while recording
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    nonisolated static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyboardShortcut.Modifiers {
        var result: KeyboardShortcut.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    /// Display label for a key, preferring what the user's layout produced.
    nonisolated static func label(keyCode: UInt16, characters: String?) -> String {
        if let named = namedKeys[keyCode] { return named }
        let trimmed = characters?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
    }

    private nonisolated static let namedKeys: [UInt16: String] = [
        0x31: "Space", 0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x75: "⌦", 0x35: "Esc",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}
