import AppKit
import Domain
import Shortcuts
import Support
import SwiftUI
import UI

/// Handles app-level commands from the status menu, launch, and other launches.
@MainActor
final class AppController {
    let permissions: PermissionsModel
    let activation: ActivationController
    let recorder: RecordingCoordinator
    let dictation: DictationSettingsModel
    let overlay: RecordingOverlayController
    let shortcut: ShortcutSettingsModel
    let context: ContextSettingsModel
    let personalization: PersonalizationModel
    let modes: ModesSettingsModel
    let navigation: SettingsNavigation
    let diagnostics: any DiagnosticsRecording
    let settings: ManagedWindowController
    private let preferences: any AppPreferences
    private let modelAssets: any ModelAssetManaging

    private(set) lazy var onboardingModel: OnboardingModel = OnboardingModel(
        permissions: permissions,
        preferences: preferences
    ) { [weak self] in
        self?.onboarding.close()
    }

    private(set) lazy var onboarding: ManagedWindowController = ManagedWindowController(
        identifier: "onboarding",
        title: String(localized: "Set Up LemmeType")
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(OnboardingView(model: self.onboardingModel))
    }

    init(
        modelAssets: any ModelAssetManaging,
        permissions: PermissionsModel,
        preferences: any AppPreferences,
        activation: ActivationController,
        recorder: RecordingCoordinator,
        dictation: DictationSettingsModel,
        shortcut: ShortcutSettingsModel,
        context: ContextSettingsModel,
        personalization: PersonalizationModel,
        modes: ModesSettingsModel,
        navigation: SettingsNavigation,
        diagnostics: any DiagnosticsRecording,
        settings: ManagedWindowController
    ) {
        self.diagnostics = diagnostics
        self.modelAssets = modelAssets
        self.permissions = permissions
        self.preferences = preferences
        self.activation = activation
        self.recorder = recorder
        self.dictation = dictation
        self.overlay = RecordingOverlayController(coordinator: recorder)
        self.shortcut = shortcut
        self.context = context
        self.personalization = personalization
        self.modes = modes
        self.navigation = navigation
        self.settings = settings
        activation.onCommand = { [weak self] command in self?.handle(command) }
        recorder.onSessionEnded = { [weak activation, weak dictation] in
            activation?.sessionEnded()
            dictation?.refreshInBackground()
        }
        recorder.onOpenSettings = { [weak self] pane in self?.showSettings(pane: pane) }
        recorder.onSaveAudio = { url in AppController.saveCopy(of: url) }
    }

    var menuActions: MenuBarActions {
        MenuBarActions(
            finishSetup: { [weak self] in self?.showOnboarding() },
            chooseShortcut: { [weak self] in self?.showSettings(pane: .shortcut) },
            openSettings: { [weak self] in self?.showSettings() },
            openDictationSettings: { [weak self] in self?.showSettings(pane: .dictation) },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
    }

    /// Deletes recordings left by a crash, registers the dictation shortcut,
    /// and opens onboarding on first launch (or after an unfinished setup).
    func launchFinished() {
        Task { [audioCapture = recorder.capture] in await audioCapture.purgeLeftovers() }
        Task { [modelAssets] in await modelAssets.removeUnusableFiles() }
        Task { [personalization] in await personalization.load() }
        overlay.start()
        dictation.refreshInBackground()
        diagnostics.record(
            .lifecycle, "app.launched", ["onboardingComplete": .flag(preferences.hasCompletedOnboarding)])
        activation.activate()
        shortcut.refreshState()
        if !preferences.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationBecameActive() {
        permissions.refresh()
        dictation.refreshInBackground()
    }

    func showOnboarding() {
        if !onboarding.isVisible {
            onboardingModel.restart()
        }
        onboarding.show()
    }

    func showSettings(pane: SettingsNavigation.Pane? = nil) {
        if let pane {
            navigation.selectedPane = pane
        }
        settings.show()
    }

    private func handle(_ command: ActivationCommand) {
        shortcut.record(command)
        recorder.handle(command)
    }

    /// Lets the user keep a copy of a recording that could not be processed.
    /// The copy is theirs; LemmeType still deletes its own file.
    private static func saveCopy(of recording: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LemmeType Recording.caf"
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: recording, to: destination)
        } catch {
            Log.audio.error("Saving a recording copy failed")
        }
    }

    /// Stops any recording before the app exits so the microphone is released
    /// and partial audio is deleted.
    func prepareToTerminate() async {
        recorder.requestCancel()
        await recorder.settle()
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Quitting cancels an active recording first (see `prepareToTerminate`).
    func quit() {
        Log.lifecycle.info("Quit requested")
        diagnostics.record(.lifecycle, "app.quit-requested")
        NSApp.terminate(nil)
    }
}
