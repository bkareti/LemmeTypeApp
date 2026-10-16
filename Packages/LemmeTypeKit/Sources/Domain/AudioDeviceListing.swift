/// Enumerates audio input devices without opening them or requesting permission.
public protocol AudioDeviceListing: Sendable {
    func availableInputDevices() -> [AudioInputDevice]
}
