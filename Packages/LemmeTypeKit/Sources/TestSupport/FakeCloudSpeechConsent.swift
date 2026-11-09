import Domain
import Synchronization

/// Remembers consent in memory.
public final class FakeCloudSpeechConsent: CloudSpeechConsentStoring {
    private let value: Mutex<CloudSpeechProviderID?>

    public init(_ provider: CloudSpeechProviderID? = nil) {
        value = Mutex(provider)
    }

    public var consentedProvider: CloudSpeechProviderID? {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
