/// Why a key could not be saved.
public enum CloudCredentialStoreError: Error, Equatable, Sendable {
    case failed
}

/// Where API keys are kept. Implementations hold them for this device only.
public protocol CloudCredentialStoring: CloudCredentialProviding {
    func save(_ credential: CloudCredential, for provider: CloudSpeechProviderID) throws(CloudCredentialStoreError)
    func remove(for provider: CloudSpeechProviderID)
}

/// Which provider the user agreed to send audio to, if any. One value, so
/// changing provider always asks again (ADR 0031).
public protocol CloudSpeechConsentStoring: AnyObject, Sendable {
    var consentedProvider: CloudSpeechProviderID? { get set }
}

/// Hands the engine a key only for the provider the user agreed to. Without
/// consent the engine has no key, reports that it cannot run, and sends nothing.
public struct ConsentedCloudCredentials: CloudCredentialProviding {
    private let store: any CloudCredentialProviding
    private let consent: any CloudSpeechConsentStoring

    public init(store: any CloudCredentialProviding, consent: any CloudSpeechConsentStoring) {
        self.store = store
        self.consent = consent
    }

    public func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
        guard consent.consentedProvider == provider else { return nil }
        return await store.credential(for: provider)
    }
}
