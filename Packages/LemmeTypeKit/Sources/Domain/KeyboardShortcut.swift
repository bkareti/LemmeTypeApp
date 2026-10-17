/// A global key combination: one non-modifier key plus modifiers.
///
/// `keyCode` is the hardware virtual key code (layout independent).
/// `keyLabel` is what the key produced on the user's layout when it was
/// recorded, used only for display.
public struct KeyboardShortcut: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers
    public let keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// ⌥Space: one hand, no common app binding, and no Input Monitoring needed.
    public static let defaultDictation = KeyboardShortcut(
        keyCode: KeyCode.space,
        modifiers: .option,
        keyLabel: "Space"
    )

    /// ⌥⇧Space: voice editing of the selection (E3-S5), next to the dictation key.
    public static let defaultVoiceEdit = KeyboardShortcut(
        keyCode: KeyCode.space,
        modifiers: [.option, .shift],
        keyLabel: "Space"
    )

    /// Escape, registered only while a dictation session is active.
    public static let cancel = KeyboardShortcut(keyCode: KeyCode.escape, modifiers: [], keyLabel: "Esc")

    /// Standard macOS ordering: ⌃⌥⇧⌘ then the key.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyLabel
    }
}

/// Hardware virtual key codes used by LemmeType's rules. Values match the
/// Carbon `kVK_*` constants; `ShortcutsTests` verifies they stay in sync.
public enum KeyCode {
    public static let ansiQ: UInt16 = 0x0C
    public static let ansiW: UInt16 = 0x0D
    public static let ansiH: UInt16 = 0x04
    public static let ansiM: UInt16 = 0x2E
    public static let ansi3: UInt16 = 0x14
    public static let ansi4: UInt16 = 0x15
    public static let ansi5: UInt16 = 0x17
    public static let grave: UInt16 = 0x32
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let escape: UInt16 = 0x35

    /// Modifier keys themselves cannot be the shortcut's key.
    public static let modifierKeys: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]
}
