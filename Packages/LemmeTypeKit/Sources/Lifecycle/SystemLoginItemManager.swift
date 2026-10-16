import Domain
import ServiceManagement
import Support

/// Launch at Login through `SMAppService.mainApp`.
public struct SystemLoginItemManager: LoginItemManaging {
    public init() {}

    public func status() -> LoginItemStatus {
        Self.status(from: SMAppService.mainApp.status)
    }

    public func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.lifecycle.info("Login item \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            Log.lifecycle.error("Login item update failed: \(String(describing: type(of: error)), privacy: .public)")
            throw LoginItemError()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func status(from status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}
