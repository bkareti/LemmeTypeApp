import Domain
import TestSupport
import Testing

@testable import UI

@MainActor
struct PermissionsModelTests {
    @Test func creatingTheModelNeverPrompts() {
        let permissions = FakePermissions()
        _ = PermissionsModel(checker: permissions, requester: permissions)

        #expect(permissions.microphoneRequestCount == 0)
        #expect(permissions.accessibilityRequestCount == 0)
    }

    @Test func grantedMicrophoneUpdatesWithoutRelaunch() async {
        let permissions = FakePermissions(microphoneAnswer: .granted)
        let model = PermissionsModel(checker: permissions, requester: permissions)
        #expect(model.action(for: .microphone) == .request)

        await model.perform(.request, for: .microphone)

        #expect(model.status(for: .microphone) == .granted)
        #expect(model.action(for: .microphone) == nil)
    }

    @Test func deniedMicrophoneOffersSystemSettingsAndNeverRepromts() async {
        let permissions = FakePermissions(statuses: [.microphone: .denied])
        let model = PermissionsModel(checker: permissions, requester: permissions)

        #expect(model.action(for: .microphone) == .openSystemSettings)
        await model.perform(.openSystemSettings, for: .microphone)

        #expect(permissions.openedSettings == [.microphone])
        #expect(permissions.microphoneRequestCount == 0)
    }

    @Test func restrictedPermissionOffersNoAction() {
        let permissions = FakePermissions(statuses: [.microphone: .restricted])
        let model = PermissionsModel(checker: permissions, requester: permissions)

        #expect(model.action(for: .microphone) == nil)
        #expect(PermissionStatus.restricted.guidance != nil)
    }

    @Test func accessibilityIsRequestedOnceThenSentToSystemSettings() async {
        let permissions = FakePermissions()
        let model = PermissionsModel(checker: permissions, requester: permissions)
        #expect(model.action(for: .accessibility) == .request)

        await model.perform(.request, for: .accessibility)

        #expect(permissions.accessibilityRequestCount == 1)
        #expect(model.action(for: .accessibility) == .openSystemSettings)
    }

    @Test func accessibilityGrantedInSystemSettingsIsPickedUpOnRefresh() {
        let permissions = FakePermissions()
        let model = PermissionsModel(checker: permissions, requester: permissions)

        permissions.set(.granted, for: .accessibility)
        model.refresh()

        #expect(model.status(for: .accessibility) == .granted)
        #expect(model.isAvailable(.textInsertion))
    }

    @Test func revokedAccessibilityMarksInsertionUnavailable() {
        let permissions = FakePermissions(statuses: [.microphone: .granted, .accessibility: .granted])
        let model = PermissionsModel(checker: permissions, requester: permissions)
        #expect(model.isAvailable(.textInsertion))

        permissions.set(.notGranted, for: .accessibility)
        model.refresh()

        #expect(!model.isAvailable(.textInsertion))
        #expect(model.isAvailable(.recording))
        #expect(!model.allGranted)
    }

    @Test func accessibilityIsNeverReportedAsDeniedOrNotRequested() {
        let model = PermissionsModel(checker: FakePermissions(), requester: FakePermissions())

        #expect(model.status(for: .accessibility) == .notGranted)
        #expect(PermissionStatus.notGranted.displayName == "Not granted")
    }

    @Test func onlyMicrophoneAndAccessibilityAreEverShown() {
        #expect(PermissionKind.allCases == [.microphone, .accessibility])
    }
}
