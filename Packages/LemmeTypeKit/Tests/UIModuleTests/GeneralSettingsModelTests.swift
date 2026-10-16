import Domain
import Support
import TestSupport
import Testing

@testable import UI

@MainActor
struct GeneralSettingsModelTests {
    private let buildInfo = BuildInfo(version: "1", build: "1")

    @Test func reflectsSystemRegistrationOnCreation() {
        let model = GeneralSettingsModel(loginItems: FakeLoginItemManager(status: .enabled), buildInfo: buildInfo)

        #expect(model.loginItemStatus == .enabled)
        #expect(model.launchAtLogin)
    }

    @Test func enablingRegistersAndRereadsStatus() {
        let loginItems = FakeLoginItemManager(status: .disabled)
        let model = GeneralSettingsModel(loginItems: loginItems, buildInfo: buildInfo)

        model.setLaunchAtLogin(true)

        #expect(loginItems.status() == .enabled)
        #expect(model.loginItemStatus == .enabled)
        #expect(model.errorMessage == nil)
    }

    @Test func failedUpdateShowsErrorAndKeepsSystemState() {
        let model = GeneralSettingsModel(
            loginItems: FakeLoginItemManager(status: .disabled, failsUpdates: true),
            buildInfo: buildInfo
        )

        model.setLaunchAtLogin(true)

        #expect(model.loginItemStatus == .disabled)
        #expect(model.errorMessage != nil)
    }

    @Test func pendingApprovalCountsAsOn() {
        let model = GeneralSettingsModel(
            loginItems: FakeLoginItemManager(status: .requiresApproval),
            buildInfo: buildInfo
        )

        #expect(model.launchAtLogin)
        #expect(model.canChangeLaunchAtLogin)
    }

    @Test func unavailableRegistrationCannotBeChanged() {
        let model = GeneralSettingsModel(loginItems: FakeLoginItemManager(status: .unavailable), buildInfo: buildInfo)

        #expect(!model.canChangeLaunchAtLogin)
    }

    @Test func refreshPicksUpChangesMadeInSystemSettings() throws {
        let loginItems = FakeLoginItemManager(status: .disabled)
        let model = GeneralSettingsModel(loginItems: loginItems, buildInfo: buildInfo)

        try loginItems.setEnabled(true)
        model.refresh()

        #expect(model.loginItemStatus == .enabled)
    }

    @Test func opensLoginItemsSettings() {
        let loginItems = FakeLoginItemManager()
        let model = GeneralSettingsModel(loginItems: loginItems, buildInfo: buildInfo)

        model.openLoginItemsSettings()

        #expect(loginItems.openSettingsCount == 1)
    }
}
