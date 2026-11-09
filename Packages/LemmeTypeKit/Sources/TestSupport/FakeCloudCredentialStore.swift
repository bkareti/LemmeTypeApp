import Domain
import Synchronization

/// Keeps keys in memory, and can be told to fail.
public final class FakeCloudCredentialStore: CloudCredentialStoring {
    private struct State {
        var keys: [CloudSpeechProviderID: CloudCredential] = [:]
        var failsToSave = false
    }

    private let state = Mutex(State())

    public init() {}

    public func setFailsToSave(_ fails: Bool) {
        state.withLock { $0.failsToSave = fails }
    }

    public func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
        state.withLock { $0.keys[provider] }
    }

    public func save(
        _ credential: CloudCredential, for provider: CloudSpeechProviderID
    ) throws(CloudCredentialStoreError) {
        let saved = state.withLock { state -> Bool in
            guard !state.failsToSave else { return false }
            state.keys[provider] = credential
            return true
        }
        if !saved { throw .failed }
    }

    public func remove(for provider: CloudSpeechProviderID) {
        _ = state.withLock { $0.keys.removeValue(forKey: provider) }
    }
}
