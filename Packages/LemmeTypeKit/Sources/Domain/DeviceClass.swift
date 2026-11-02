import Foundation

/// The kind of device LemmeType runs on. Model fit and the default memory
/// budget depend on it (ADR 0027).
public enum DeviceClass: String, CaseIterable, Sendable {
    case mac
    case iPhone
    case iPad

    /// iPhone and iPad share one memory model: the app is limited to part of
    /// the physical memory and the system ends it without warning beyond that.
    public var isHandheld: Bool { self != .mac }

    /// The device class for a hardware model identifier such as `iPhone17,1`,
    /// `iPad16,3`, or `Mac15,3`. Anything else is a Mac.
    public static func detect(machineIdentifier: String) -> DeviceClass {
        if machineIdentifier.hasPrefix("iPhone") { return .iPhone }
        if machineIdentifier.hasPrefix("iPad") { return .iPad }
        return .mac
    }

    /// The model identifier of this device. The iOS Simulator reports its
    /// simulated device through an environment variable.
    static func currentMachineIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}

/// What an iPhone or iPad needs to run a model: whole gigabytes of the
/// device's nominal memory (a "6 GB" phone reports a little less than 6 GiB).
public struct HandheldRequirement: Equatable, Sendable {
    public let minimumGigabytes: Int
    /// Below this the model runs but leaves little room for the system.
    public let recommendedGigabytes: Int

    public init(minimumGigabytes: Int, recommendedGigabytes: Int) {
        self.minimumGigabytes = minimumGigabytes
        self.recommendedGigabytes = max(minimumGigabytes, recommendedGigabytes)
    }
}
