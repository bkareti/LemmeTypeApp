import Foundation
import Security

/// Removes an API key that an earlier build kept in the Keychain (ADR 0031 before ADR 0033). Cloud speech
/// now goes through the LemmeType gateway, so nothing reads or writes such a key any more; this only
/// deletes it so it does not stay on the device.
public struct LegacyCloudKeyEraser: Sendable {
    private let service: String

    public init(service: String = "com.lemmetype.cloud-speech") {
        self.service = service
    }

    /// Deletes every key stored under the old service name. Returns whether one was found.
    @discardableResult
    public func erase() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
