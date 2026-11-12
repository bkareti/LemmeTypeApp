import Domain
import Foundation
import Observation

/// Turning cloud speech on and off (E12-S1, E13-S3, ADRs 0031 and 0033). Off by default: audio can leave the
/// device only after the user agrees to send it to LemmeType's server. There is no key to enter.
@MainActor
@Observable
public final class CloudSpeechSettingsModel {
    public enum Status: Equatable, Sendable {
        case off
        /// The user agreed before, but the gateway says audio would now go somewhere new.
        case needsConsentAgain
        case turnedOn
    }

    /// Why the last attempt to turn it on did not work; the words are the view's.
    public enum Problem: Equatable, Sendable {
        case subscriptionRequired
        case offline
        case failed
    }

    public private(set) var status: Status = .off
    public var isShowingConsent = false
    public private(set) var problem: Problem?
    /// This billing period's cloud speech allowance, when it is known.
    public private(set) var allowance: GatewayAllowance?
    public let providerName: String
    public let host: String
    /// Told whether the cloud engine can be offered, whenever that may have changed.
    public var onChange: @MainActor (Bool) -> Void = { _ in }
    /// The user just agreed, so cloud speech is ready: the place to set up a mode that uses it.
    public var onReady: @MainActor () -> Void = {}
    /// Cloud speech was turned off and the agreement removed.
    public var onTurnedOff: @MainActor () -> Void = {}

    private let providerID: CloudSpeechProviderID
    private let consent: any CloudSpeechConsentStoring
    private let directory: any GatewayCapabilitiesProviding
    private let allowances: any GatewayAllowanceProviding

    public init(
        provider: any CloudSpeechProvider, consent: any CloudSpeechConsentStoring,
        directory: any GatewayCapabilitiesProviding, allowances: any GatewayAllowanceProviding
    ) {
        providerID = provider.id
        providerName = provider.displayName
        host = provider.host
        self.consent = consent
        self.directory = directory
        self.allowances = allowances
    }

    /// What the app already knows, with no network: whether an agreement to this provider and a version of
    /// its terms is stored. Safe to await at launch. Whether the gateway has since raised the version is
    /// checked by ``verifyTerms()``, and again before any Cloud dictation by `GatewayCredentials`.
    public func refresh() async {
        guard consent.consentedProvider == providerID, consent.consentedVersion != nil else {
            setStatus(.off)
            return
        }
        if status != .needsConsentAgain { setStatus(.turnedOn) }
    }

    /// Asks the gateway whether the terms the user agreed to are still the current ones. Offline, the
    /// agreement stands; the request itself will say it could not connect. Uses the network, so it runs
    /// when the Cloud speech settings are shown, not at launch.
    public func verifyTerms() async {
        guard status == .turnedOn, let agreed = consent.consentedVersion else { return }
        if let current = try? await directory.capabilities().consentVersion, current != agreed {
            setStatus(.needsConsentAgain)
        }
    }

    public func refreshAllowance() async {
        allowance = status == .turnedOn ? await allowances.allowance() : nil
    }

    public func requestTurnOn() {
        problem = nil
        isShowingConsent = true
    }

    public func declineConsent() {
        isShowingConsent = false
    }

    /// Records what the user agreed to: this provider, and the gateway's current version of its terms.
    /// Needs the gateway, so it also needs a subscription and a connection.
    public func acceptConsent() async {
        isShowingConsent = false
        do throws(GatewayAccessError) {
            let capabilities = try await directory.capabilities()
            consent.consentedProvider = providerID
            consent.consentedVersion = capabilities.consentVersion
            problem = nil
        } catch {
            switch error {
            case .subscriptionRequired: problem = .subscriptionRequired
            case .offline: problem = .offline
            case .failed: problem = .failed
            }
            return
        }
        status = .off
        await refresh()
        if status == .turnedOn {
            onReady()
            await refreshAllowance()
        }
    }

    public func turnOff() async {
        _ = await eraseAll()
    }

    /// Removes the agreement. `true` when there was one to remove.
    public func eraseAll() async -> Bool {
        let hadConsent = consent.consentedProvider != nil
        consent.consentedProvider = nil
        consent.consentedVersion = nil
        problem = nil
        allowance = nil
        await refresh()
        if hadConsent { onTurnedOff() }
        return hadConsent
    }

    private func setStatus(_ new: Status) {
        status = new
        onChange(new == .turnedOn)
    }
}
