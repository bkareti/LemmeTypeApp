import AVFoundation
import Domain

/// Lists audio inputs through AVFoundation. Enumeration does not open devices
/// or trigger the Microphone permission prompt.
public struct CaptureDeviceLister: AudioDeviceListing {
    public init() {}

    public func availableInputDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = session.devices.map { (id: $0.uniqueID, name: $0.localizedName) }
        return Self.makeDevices(devices, defaultID: AVCaptureDevice.default(for: .audio)?.uniqueID)
    }

    /// Marks the system default and orders it first, then by name.
    static func makeDevices(
        _ devices: [(id: String, name: String)],
        defaultID: String?
    ) -> [AudioInputDevice] {
        devices
            .map { AudioInputDevice(id: $0.id, name: $0.name, isSystemDefault: $0.id == defaultID) }
            .sorted { lhs, rhs in
                if lhs.isSystemDefault != rhs.isSystemDefault { return lhs.isSystemDefault }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
