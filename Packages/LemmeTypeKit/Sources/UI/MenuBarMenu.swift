import Domain
import SwiftUI

/// Actions the status menu can trigger; supplied by the app's coordinator.
public struct MenuBarActions {
    public var finishSetup: @MainActor () -> Void
    public var chooseShortcut: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var openDictationSettings: @MainActor () -> Void
    public var showAbout: @MainActor () -> Void
    public var quit: @MainActor () -> Void

    public init(
        finishSetup: @escaping @MainActor () -> Void,
        chooseShortcut: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void,
        openDictationSettings: @escaping @MainActor () -> Void,
        showAbout: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.finishSetup = finishSetup
        self.chooseShortcut = chooseShortcut
        self.openSettings = openSettings
        self.openDictationSettings = openDictationSettings
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// Contents of the menu-bar item's menu.
public struct MenuBarMenu: View {
    private let actions: MenuBarActions
    private let permissions: PermissionsModel
    private let shortcut: ShortcutSettingsModel
    private let recorder: RecordingCoordinator
    private let dictation: DictationSettingsModel
    private let context: ContextSettingsModel?
    private let modes: ModesSettingsModel?

    public init(
        actions: MenuBarActions,
        permissions: PermissionsModel,
        shortcut: ShortcutSettingsModel,
        recorder: RecordingCoordinator,
        dictation: DictationSettingsModel,
        context: ContextSettingsModel? = nil,
        modes: ModesSettingsModel? = nil
    ) {
        self.modes = modes
        self.actions = actions
        self.permissions = permissions
        self.shortcut = shortcut
        self.recorder = recorder
        self.dictation = dictation
        self.context = context
    }

    public var body: some View {
        if !permissions.allGranted {
            Button(String(localized: "Finish Setup…", bundle: .module)) { actions.finishSetup() }
        }
        if shortcut.isShortcutUnavailable {
            Button(String(localized: "Shortcut Unavailable — Choose Another…", bundle: .module)) {
                actions.chooseShortcut()
            }
        } else {
            Text(String(localized: "Dictate: \(shortcut.shortcut.displayString)", bundle: .module))
        }
        if let edit = shortcut.editShortcut {
            Text(String(localized: "Edit Selection: \(edit.displayString)", bundle: .module))
        }
        if let context {
            Text(
                context.usesFormattingContext
                    ? String(localized: "Text Near Cursor: On", bundle: .module)
                    : String(localized: "Text Near Cursor: Off", bundle: .module))
        }
        Divider()
        if let modes {
            // Applies from the next session (E4-S6).
            Picker(
                String(localized: "Mode: \(modes.currentDefault.displayName)", bundle: .module),
                selection: Binding(get: { modes.currentDefault.id }, set: { modes.setDefault($0) })
            ) {
                ForEach(modes.modes) { mode in
                    Text(mode.displayName).tag(mode.id)
                }
            }
        } else {
            Picker(
                String(localized: "Writing Mode: \(dictation.writingMode.displayName)", bundle: .module),
                selection: Binding(get: { dictation.writingMode }, set: { dictation.setWritingMode($0) })
            ) {
                ForEach(WritingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
        if dictation.effectiveEngine == nil {
            Button(String(localized: "No On-Device Engine Ready — Set Up…", bundle: .module)) {
                actions.openDictationSettings()
            }
        } else {
            Text(dictation.menuEngineSummary)
        }
        Divider()
        if recorder.state.isCapturing {
            Button(String(localized: "Stop Recording", bundle: .module)) { recorder.requestStop() }
            Button(String(localized: "Cancel Recording", bundle: .module)) { recorder.requestCancel() }
        } else {
            Button(String(localized: "Start Test Recording", bundle: .module)) { recorder.requestStart(target: nil) }
                .disabled(recorder.state == .processing)
        }
        Divider()
        Button(String(localized: "Settings…", bundle: .module)) { actions.openSettings() }
            .keyboardShortcut(",")
        Button(String(localized: "About LemmeType", bundle: .module)) { actions.showAbout() }
        Divider()
        Button(String(localized: "Quit LemmeType", bundle: .module)) { actions.quit() }
            .keyboardShortcut("q")
    }
}
