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

    @Test func shortcutStartAndStopDriveTheRecorder() async {
        var composition = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"))
        let registrar = FakeHotKeyRegistrar()
        composition.hotKeyRegistrar = registrar
        let controller = composition.makeAppController()
        controller.activation.change(to: .toggle)
        controller.launchFinished()

        registrar.send(.pressed, .defaultDictation, at: 0)
        await controller.recorder.settle()
        #expect(controller.recorder.state == .recording)
        #expect(controller.overlay.isVisible)

        registrar.send(.released, .defaultDictation, at: 0.1)
        registrar.send(.pressed, .defaultDictation, at: 1)
        await controller.recorder.settle()
        #expect(controller.recorder.state == .completed)
        #expect(!controller.activation.isSessionActive)
        controller.overlay.currentPanel?.orderOut(nil)
    }

    @Test func cancellingFromTheOverlayRearmsTheShortcut() async {
        var composition = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"))
        let registrar = FakeHotKeyRegistrar()
        composition.hotKeyRegistrar = registrar
        let controller = composition.makeAppController()
        controller.activation.change(to: .toggle)
        controller.launchFinished()

        registrar.send(.pressed, .defaultDictation, at: 0)
        await controller.recorder.settle()
        controller.recorder.requestCancel()
        await controller.recorder.settle()

        #expect(controller.recorder.state == .cancelled)
        #expect(!controller.activation.isSessionActive)
        #expect(!registrar.registeredShortcuts.contains(.cancel))
        controller.overlay.currentPanel?.orderOut(nil)
    }

    @Test func overlayPanelNeverTakesFocus() async throws {
        let controller = makeController()
        controller.overlay.start()

        controller.recorder.requestStart(target: nil)
        await controller.recorder.settle()

        let panel = try #require(controller.overlay.currentPanel)
        #expect(panel.isVisible)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        await controller.prepareToTerminate()
        panel.orderOut(nil)
    }

    @Test func terminationCancelsAnActiveRecording() async {
        let controller = makeController()
        controller.recorder.requestStart(target: nil)
        await controller.recorder.settle()
        #expect(controller.recorder.state == .recording)

        await controller.prepareToTerminate()

        #expect(controller.recorder.state == .cancelled)
    }

    @Test func launchAndActivityAreRecordedInDiagnostics() async {
        var composition = AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1"))
        let registrar = FakeHotKeyRegistrar()
        composition.hotKeyRegistrar = registrar
        let controller = composition.makeAppController()
        controller.activation.change(to: .toggle)

        controller.launchFinished()
        registrar.send(.pressed, .defaultDictation, at: 0)
        await controller.recorder.settle()
        await controller.prepareToTerminate()

        let names = composition.diagnostics.snapshot().map(\.name)
        #expect(names.contains("app.launched"))
        #expect(names.contains("shortcut.registered"))
        #expect(names.contains("activation.start"))
        #expect(names.contains("capture.started"))
        #expect(names.contains("recorder.state"))
        controller.overlay.currentPanel?.orderOut(nil)
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
