import AppKit
import Domain
import TestSupport
import Testing
import UI

@testable import LemmeType

@MainActor
struct AppControllerTests {
    private func makeController(freshInstall: Bool = false) -> AppController {
        AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"), freshInstall: freshInstall)
            .makeAppController()
    }

    @Test func settingsWindowIsCreatedOnceAndReused() throws {
        let controller = makeController()

        controller.showSettings()
        let first = try #require(controller.settings.currentWindow)
        first.close()
        controller.showSettings()

        #expect(controller.settings.currentWindow === first)
        #expect(first.isVisible)
        #expect(first.identifier?.rawValue == "settings")
        first.close()
    }

    @Test func menuSettingsActionOpensTheSettingsWindow() throws {
        let controller = makeController()

        controller.menuActions.openSettings()

        let window = try #require(controller.settings.currentWindow)
        #expect(window.isVisible)
        window.close()
    }

    @Test func settingsWindowSurvivesClosing() throws {
        let controller = makeController()

        controller.showSettings()
        let window = try #require(controller.settings.currentWindow)
        window.close()

        #expect(!window.isReleasedWhenClosed)
        #expect(controller.settings.currentWindow === window)
    }

    @Test func firstLaunchOpensOnboarding() throws {
        let controller = makeController(freshInstall: true)

        controller.launchFinished()

        let window = try #require(controller.onboarding.currentWindow)
        #expect(window.isVisible)
        window.close()
    }

    @Test func completedOnboardingIsNotShownAgain() {
        let controller = makeController(freshInstall: false)

        controller.launchFinished()

        #expect(controller.onboarding.currentWindow == nil)
    }

    @Test func finishingOnboardingClosesItsWindow() throws {
        let controller = makeController(freshInstall: true)
        controller.launchFinished()
        let window = try #require(controller.onboarding.currentWindow)

        controller.onboardingModel.finish()

        #expect(!window.isVisible)
    }

    @Test func launchRegistersTheDictationShortcut() {
        // The test host already owns ⌥Space through its own live composition.
        var composition = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"))
        let registrar = FakeHotKeyRegistrar()
        composition.hotKeyRegistrar = registrar
        let controller = composition.makeAppController()

        controller.launchFinished()

        #expect(registrar.registeredShortcuts == [.defaultDictation])
        #expect(!controller.shortcut.isShortcutUnavailable)
    }

    @Test func unavailableShortcutAtLaunchIsSurfaced() {
        var composition = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"))
        let registrar = FakeHotKeyRegistrar()
        registrar.failures[.defaultDictation] = .unavailable
        composition.hotKeyRegistrar = registrar
        let controller = composition.makeAppController()

        controller.launchFinished()

        #expect(controller.shortcut.isShortcutUnavailable)
        #expect(controller.shortcut.errorMessage != nil)
    }

    @Test func chooseShortcutOpensTheShortcutPane() throws {
        let controller = makeController()

        controller.menuActions.chooseShortcut()

        #expect(controller.navigation.selectedPane == .shortcut)
        let window = try #require(controller.settings.currentWindow)
        #expect(window.isVisible)
        window.close()
    }

    @Test func finishSetupMenuActionReopensOnboardingFromTheStart() throws {
        let controller = makeController()
        controller.onboardingModel.next()

        controller.menuActions.finishSetup()

        #expect(controller.onboardingModel.step == .welcome)
        let window = try #require(controller.onboarding.currentWindow)
        #expect(window.isVisible)
        window.close()
    }
}
