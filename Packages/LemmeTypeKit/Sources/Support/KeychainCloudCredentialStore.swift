import Domain
import Foundation
import Security

/// Keeps API keys in the Keychain, for this device only: never synced to iCloud,
/// and not part of a backup restored to another device (ADR 0031).
public struct KeychainCloudCredentialStore: CloudCredentialStoring {
    private let service: String

    public init(service: String = "com.lemmetype.cloud-speech") {
        self.service = service
    }

    private func query(for provider: CloudSpeechProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    public func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
        var search = query(for: provider)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
            let secret = String(bytes: data, encoding: .utf8), !secret.isEmpty
        else { return nil }
        return CloudCredential(secret: secret)
    }

    public func save(
        _ credential: CloudCredential, for provider: CloudSpeechProviderID
    ) throws(CloudCredentialStoreError) {
        remove(for: provider)
        var item = query(for: provider)
        item[kSecValueData as String] = Data(credential.secret.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw .failed }
    }

    public func remove(for provider: CloudSpeechProviderID) {
        SecItemDelete(query(for: provider) as CFDictionary)
    }
}
