import Domain
import ServiceManagement
import Testing

@testable import Lifecycle

/// Mapping only; never registers the test runner as a login item.
struct SystemLoginItemManagerTests {
    @Test(arguments: [
        (SMAppService.Status.enabled, LoginItemStatus.enabled),
        (.notRegistered, .disabled),
        (.requiresApproval, .requiresApproval),
        (.notFound, .unavailable),
    ])
    func mapsServiceManagementStatus(status: SMAppService.Status, expected: LoginItemStatus) {
        #expect(SystemLoginItemManager.status(from: status) == expected)
    }
}
