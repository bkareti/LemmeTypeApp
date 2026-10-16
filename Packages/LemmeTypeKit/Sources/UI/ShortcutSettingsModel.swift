import Domain
import Observation
import Support

/// The Shortcut pane: shows and changes the dictation shortcut and mode, and
/// gives live feedback when the shortcut fires so the user can test it.
@MainActor
@Observable
public final class ShortcutSettingsModel {
    public private(set) var isRecording = false
    public private(set) var errorMessage: String?
    /// The most recent activation, as feedback for testing the shortcut.
    public private(set) var lastActivity: String?
    /// Mirrors of the controller's state, stored so SwiftUI observes changes.
    public private(set) var shortcut: KeyboardShortcut
    public private(set) var mode: ActivationMode
    public private(set) var isShortcutUnavailable = false

    private let controller: any DictationShortcutControlling
    private let preferences: any AppPreferences

    public init(controller: any DictationShortcutControlling, preferences: any AppPreferences) {
        self.controller = controller
        self.preferences = preferences
        self.shortcut = controller.shortcut
        self.mode = controller.mode
        refreshState()
    }

    /// Re-reads the controller, e.g. after the shortcut was registered at launch.
    public func refreshState() {
        shortcut = controller.shortcut
        mode = controller.mode
        isShortcutUnavailable = controller.registrationError != nil
        errorMessage = controller.registrationError.map(Self.message(for:))
    }

    public func setMode(_ mode: ActivationMode) {
        controller.change(to: mode)
        preferences.activationMode = mode
        self.mode = controller.mode
    }

    public func startRecording() {
        controller.suspend()
        errorMessage = nil
        isRecording = true
    }

    public func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        controller.activate()
        refreshState()
    }

    public func recorded(_ shortcut: KeyboardShortcut) {
        guard isRecording else { return }
        isRecording = false
        do {
            try controller.change(to: shortcut)
            preferences.dictationShortcut = shortcut
            refreshState()
            Log.shortcuts.info("Dictation shortcut changed")
        } catch {
            controller.activate()
            refreshState()
            errorMessage = Self.message(for: error)
        }
    }

    public func resetToDefault() {
        isRecording = true
        recorded(.defaultDictation)
    }

    /// Feedback only; no target content is shown, just the app name.
    public func record(_ command: ActivationCommand) {
        lastActivity =
            switch command {
            case .start(let target):
                target?.applicationName.map { String(localized: "Started in \($0)", bundle: .module) }
                    ?? String(localized: "Started", bundle: .module)
            case .stop: String(localized: "Stopped", bundle: .module)
            case .cancel: String(localized: "Cancelled", bundle: .module)
            }
    }

    static func message(for error: ShortcutError) -> String {
        switch error {
        case .invalid(.missingModifier):
            String(localized: "Include ⌘, ⌥, or ⌃ so the shortcut doesn’t interfere with typing.", bundle: .module)
        case .invalid(.modifierOnly):
            String(localized: "Add a key to the modifiers, for example ⌥Space.", bundle: .module)
        case .invalid(.reservedForCancel):
            String(localized: "Esc is reserved for cancelling dictation.", bundle: .module)
        case .invalid(.systemShortcut):
            String(localized: "macOS already uses that shortcut. Choose another.", bundle: .module)
        case .unavailable:
            String(localized: "Another app is using this shortcut. Choose another.", bundle: .module)
        case .registrationFailed:
            String(localized: "macOS couldn’t register this shortcut. Choose another.", bundle: .module)
        }
    }
}
