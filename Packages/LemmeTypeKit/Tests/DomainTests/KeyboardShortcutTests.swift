import Domain
import Foundation
import Testing

struct KeyboardShortcutTests {
    @Test func displaysModifiersInStandardOrder() {
        let shortcut = KeyboardShortcut(keyCode: 0x02, modifiers: [.command, .shift, .option, .control], keyLabel: "D")

        #expect(shortcut.displayString == "⌃⌥⇧⌘D")
        #expect(KeyboardShortcut.defaultDictation.displayString == "⌥Space")
    }

    @Test func roundTripsThroughCodable() throws {
        let shortcut = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")

        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))

        #expect(decoded == shortcut)
    }

    @Test func defaultShortcutIsValid() {
        #expect(ShortcutValidation.problem(with: .defaultDictation) == nil)
    }

    @Test(arguments: [
        (KeyboardShortcut(keyCode: 0x02, modifiers: [], keyLabel: "D"), ShortcutValidation.Problem.missingModifier),
        (KeyboardShortcut(keyCode: 0x02, modifiers: .shift, keyLabel: "D"), .missingModifier),
        (KeyboardShortcut(keyCode: 0x37, modifiers: .option, keyLabel: "⌘"), .modifierOnly),
        (KeyboardShortcut(keyCode: KeyCode.escape, modifiers: .option, keyLabel: "Esc"), .reservedForCancel),
        (KeyboardShortcut(keyCode: KeyCode.ansiQ, modifiers: .command, keyLabel: "Q"), .systemShortcut),
        (KeyboardShortcut(keyCode: KeyCode.space, modifiers: .command, keyLabel: "Space"), .systemShortcut),
        (KeyboardShortcut(keyCode: KeyCode.tab, modifiers: .command, keyLabel: "Tab"), .systemShortcut),
    ])
    func rejectsUnsafeShortcuts(shortcut: KeyboardShortcut, expected: ShortcutValidation.Problem) {
        #expect(ShortcutValidation.problem(with: shortcut) == expected)
    }

    @Test func acceptsOrdinaryCombinations() {
        let shortcut = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")

        #expect(ShortcutValidation.problem(with: shortcut) == nil)
    }
}
