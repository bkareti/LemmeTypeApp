import Domain

/// Returns a fixed device list without touching audio hardware.
public struct FakeAudioDeviceLister: AudioDeviceListing {
    public var devices: [AudioInputDevice]

    public init(devices: [AudioInputDevice] = []) {
        self.devices = devices
    }

    public func availableInputDevices() -> [AudioInputDevice] {
        devices
    }
}
