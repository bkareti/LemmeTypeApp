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
    let overlay: RecordingOverlayController
    let shortcut: ShortcutSettingsModel
    let navigation: SettingsNavigation
    let diagnostics: any DiagnosticsRecording
    let settings: ManagedWindowController
    private let preferences: any AppPreferences

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
        permissions: PermissionsModel,
        preferences: any AppPreferences,
        activation: ActivationController,
        recorder: RecordingCoordinator,
        shortcut: ShortcutSettingsModel,
        navigation: SettingsNavigation,
        diagnostics: any DiagnosticsRecording,
        settings: ManagedWindowController
    ) {
        self.diagnostics = diagnostics
        self.permissions = permissions
        self.preferences = preferences
        self.activation = activation
        self.recorder = recorder
        self.overlay = RecordingOverlayController(coordinator: recorder)
        self.shortcut = shortcut
        self.navigation = navigation
        self.settings = settings
        activation.onCommand = { [weak self] command in self?.handle(command) }
        recorder.onSessionEnded = { [weak activation] in activation?.sessionEnded() }
        recorder.onOpenSettings = { [weak self] pane in self?.showSettings(pane: pane) }
    }

    var menuActions: MenuBarActions {
        MenuBarActions(
            finishSetup: { [weak self] in self?.showOnboarding() },
            chooseShortcut: { [weak self] in self?.showSettings(pane: .shortcut) },
            openSettings: { [weak self] in self?.showSettings() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
    }

    /// Deletes recordings left by a crash, registers the dictation shortcut,
    /// and opens onboarding on first launch (or after an unfinished setup).
    func launchFinished() {
        Task { [audioCapture = recorder.capture] in await audioCapture.purgeLeftovers() }
        overlay.start()
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
