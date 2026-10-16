import AppKit
import Domain
import Support
import SwiftUI
import UI

/// Handles app-level commands from the status menu, launch, and other launches.
@MainActor
final class AppController {
    let permissions: PermissionsModel
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

    init(permissions: PermissionsModel, preferences: any AppPreferences, settings: ManagedWindowController) {
        self.permissions = permissions
        self.preferences = preferences
        self.settings = settings
    }

    var menuActions: MenuBarActions {
        MenuBarActions(
            finishSetup: { [weak self] in self?.showOnboarding() },
            openSettings: { [weak self] in self?.showSettings() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
    }

    /// First launch (or a launch after an unfinished setup) opens onboarding.
    func launchFinished() {
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

    func showSettings() {
        settings.show()
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
