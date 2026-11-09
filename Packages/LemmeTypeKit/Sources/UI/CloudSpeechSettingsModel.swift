import Domain
import Foundation
import Observation

/// Turning cloud speech on and off (E12-S1, ADR 0031). Off by default: audio can
/// leave the device only after the user agrees to a named provider and adds a key.
@MainActor
@Observable
public final class CloudSpeechSettingsModel {
    public enum Status: Equatable, Sendable {
        case off
        /// The user agreed, but no key is stored yet.
        case needsKey
        case turnedOn
    }

    public private(set) var status: Status = .off
    public var isShowingConsent = false
    /// The last key could not be used; the words are the view's.
    public private(set) var keyProblem: KeyProblem?
    public let providerName: String
    public let host: String
    /// Told whether the cloud engine can be offered, whenever that may have changed.
    public var onChange: @MainActor (Bool) -> Void = { _ in }

    public enum KeyProblem: Equatable, Sendable {
        case empty
        case notSaved
    }

    private let providerID: CloudSpeechProviderID
    private let store: any CloudCredentialStoring
    private let consent: any CloudSpeechConsentStoring

    public init(
        provider: any CloudSpeechProvider, store: any CloudCredentialStoring, consent: any CloudSpeechConsentStoring
    ) {
        providerID = provider.id
        providerName = provider.displayName
        host = provider.host
        self.store = store
        self.consent = consent
    }

    public func refresh() async {
        guard consent.consentedProvider == providerID else {
            setStatus(.off)
            return
        }
        setStatus(await store.credential(for: providerID) == nil ? .needsKey : .turnedOn)
    }

    public func requestTurnOn() {
        isShowingConsent = true
    }

    public func declineConsent() {
        isShowingConsent = false
    }

    public func acceptConsent() async {
        consent.consentedProvider = providerID
        isShowingConsent = false
        await refresh()
    }

    /// Spaces and line breaks around a pasted key are dropped.
    public func saveKey(_ text: String) async {
        let secret = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            keyProblem = .empty
            return
        }
        do throws(CloudCredentialStoreError) {
            try store.save(CloudCredential(secret: secret), for: providerID)
            keyProblem = nil
        } catch {
            keyProblem = .notSaved
        }
        await refresh()
    }

    public func turnOff() async {
        _ = await eraseAll()
    }

    /// Removes the key and the consent. `true` when there was something to remove.
    public func eraseAll() async -> Bool {
        let hadKey = await store.credential(for: providerID) != nil
        let hadConsent = consent.consentedProvider != nil
        store.remove(for: providerID)
        consent.consentedProvider = nil
        keyProblem = nil
        await refresh()
        return hadKey || hadConsent
    }

    private func setStatus(_ new: Status) {
        status = new
        onChange(new == .turnedOn)
    }
}
