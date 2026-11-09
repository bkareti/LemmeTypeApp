import Domain

/// Returns a fixed key, or none, for every provider.
public struct FakeCloudCredentials: CloudCredentialProviding {
    private let credential: CloudCredential?

    public init(secret: String? = "test-key") {
        credential = secret.map(CloudCredential.init(secret:))
    }

    public func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
        credential
    }
}
