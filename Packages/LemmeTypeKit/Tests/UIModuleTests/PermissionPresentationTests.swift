import Domain
import TestSupport
import Testing

@testable import UI

/// E1-S8: permission presentation for every permission and status, using
/// fakes only — the CI host's real privacy settings are never read or changed.
@MainActor
struct PermissionPresentationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let permission: PermissionKind
        let status: PermissionStatus
        let action: PermissionsModel.Action?
        let hasGuidance: Bool
        let enablesCapability: Bool

        var testDescription: String { "\(permission.rawValue) \(status.rawValue)" }
    }

    nonisolated static let cases: [Case] = [
        Case(
            permission: .microphone, status: .notRequested, action: .request, hasGuidance: false,
            enablesCapability: false),
        Case(permission: .microphone, status: .granted, action: nil, hasGuidance: false, enablesCapability: true),
        Case(
            permission: .microphone, status: .denied, action: .openSystemSettings, hasGuidance: true,
            enablesCapability: false),
        Case(permission: .microphone, status: .restricted, action: nil, hasGuidance: true, enablesCapability: false),
        Case(
            permission: .microphone, status: .notGranted, action: .openSystemSettings, hasGuidance: false,
            enablesCapability: false),
        Case(
            permission: .accessibility, status: .notRequested, action: .request, hasGuidance: false,
            enablesCapability: false),
        Case(permission: .accessibility, status: .granted, action: nil, hasGuidance: false, enablesCapability: true),
        Case(
            permission: .accessibility, status: .denied, action: .openSystemSettings, hasGuidance: true,
            enablesCapability: false),
        Case(permission: .accessibility, status: .restricted, action: nil, hasGuidance: true, enablesCapability: false),
        Case(
            permission: .accessibility, status: .notGranted, action: .request, hasGuidance: false,
            enablesCapability: false),
    ]

    @Test(arguments: cases)
    func presentsEveryState(_ testCase: Case) {
        let permissions = FakePermissions(statuses: [testCase.permission: testCase.status])
        let model = PermissionsModel(checker: permissions, requester: permissions)
        let capability = Capability.allCases.first { $0.requiredPermission == testCase.permission }

        #expect(model.status(for: testCase.permission) == testCase.status)
        #expect(model.action(for: testCase.permission) == testCase.action)
        #expect((testCase.status.guidance != nil) == testCase.hasGuidance)
        #expect(!testCase.status.displayName.isEmpty)
        #expect(!testCase.permission.explanation.isEmpty)
        #expect(capability.map(model.isAvailable) == testCase.enablesCapability)
        if let action = testCase.action {
            #expect(!action.title(for: testCase.permission).isEmpty)
        }
    }

    @Test func everyCombinationIsCovered() {
        let statuses: [PermissionStatus] = [.notRequested, .granted, .denied, .restricted, .notGranted]
        #expect(Self.cases.count == PermissionKind.allCases.count * statuses.count)
    }
}
