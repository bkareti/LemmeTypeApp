import Domain
import Observation
import Support

/// Drives the foundation status window: build info, permission states, and
/// the number of available inputs. Reads only; never requests permissions.
@MainActor
@Observable
public final class StatusViewModel {
    public struct PermissionRow: Identifiable, Equatable, Sendable {
        public let permission: PermissionKind
        public let status: PermissionStatus
        public var id: PermissionKind { permission }
    }

    public private(set) var permissionRows: [PermissionRow] = []
    public private(set) var inputDeviceCount = 0
    public let buildInfo: BuildInfo

    private let permissionChecker: any PermissionChecking
    private let audioDeviceLister: any AudioDeviceListing

    public init(
        permissionChecker: any PermissionChecking,
        audioDeviceLister: any AudioDeviceListing,
        buildInfo: BuildInfo
    ) {
        self.permissionChecker = permissionChecker
        self.audioDeviceLister = audioDeviceLister
        self.buildInfo = buildInfo
        refresh()
    }

    public func refresh() {
        permissionRows = PermissionKind.allCases.map {
            PermissionRow(permission: $0, status: permissionChecker.status(for: $0))
        }
        inputDeviceCount = audioDeviceLister.availableInputDevices().count
        Log.lifecycle.debug("Status refreshed for \(self.permissionRows.count, privacy: .public) permissions")
    }
}
