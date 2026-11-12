import Domain
import Synchronization

/// Remembers consent in memory.
public final class FakeCloudSpeechConsent: CloudSpeechConsentStoring {
    private struct State {
        var provider: CloudSpeechProviderID?
        var version: Int?
    }

    private let state: Mutex<State>

    public init(_ provider: CloudSpeechProviderID? = nil, version: Int? = nil) {
        state = Mutex(State(provider: provider, version: version ?? (provider == nil ? nil : 1)))
    }

    public var consentedProvider: CloudSpeechProviderID? {
        get { state.withLock { $0.provider } }
        set { state.withLock { $0.provider = newValue } }
    }

    public var consentedVersion: Int? {
        get { state.withLock { $0.version } }
        set { state.withLock { $0.version = newValue } }
    }
}
