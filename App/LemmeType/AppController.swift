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
    let audioCapture: any AudioCapturing
    let shortcut: ShortcutSettingsModel
    let navigation: SettingsNavigation
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
        audioCapture: any AudioCapturing,
        shortcut: ShortcutSettingsModel,
        navigation: SettingsNavigation,
        settings: ManagedWindowController
    ) {
        self.permissions = permissions
        self.preferences = preferences
        self.activation = activation
        self.audioCapture = audioCapture
        self.shortcut = shortcut
        self.navigation = navigation
        self.settings = settings
        activation.onCommand = { [weak self] command in self?.handle(command) }
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
        Task { [audioCapture] in await audioCapture.purgeLeftovers() }
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

    /// Recording arrives in E1-S5/E1-S6; until then activations only drive the
    /// Shortcut pane's test feedback.
    private func handle(_ command: ActivationCommand) {
        shortcut.record(command)
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Recording does not exist yet; E1-S6 makes quit stop an active recording first.
    func quit() {
        Log.lifecycle.info("Quit requested")
        NSApp.terminate(nil)
    }
}
