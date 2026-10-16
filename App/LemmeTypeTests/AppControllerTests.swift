import AppKit
import Testing
import UI

@testable import LemmeType

@MainActor
struct AppControllerTests {
    private func makeController() -> AppController {
        AppComposition.uiTesting(buildInfo: .init(version: "1", build: "1")).makeAppController()
    }

    @Test func settingsWindowIsCreatedOnceAndReused() throws {
        let controller = makeController()

        controller.showSettings()
        let first = try #require(controller.settings.currentWindow)
        first.close()
        controller.showSettings()

        #expect(controller.settings.currentWindow === first)
        #expect(first.isVisible)
        #expect(first.identifier == SettingsWindowController.windowIdentifier)
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
}
