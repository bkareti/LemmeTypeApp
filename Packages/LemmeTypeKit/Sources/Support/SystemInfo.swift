import Foundation

/// Coarse, non-identifying system facts for diagnostics.
public enum SystemInfo {
    /// e.g. "Version 27.0 (Build 26A428)".
    public static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// Hardware class such as "Mac16,1" — never a serial number.
    public static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}
