/// Which provider, and which version of its terms, the user agreed to send audio to, if any.
/// Changing the provider, or raising the version the gateway reports, always asks again (ADR 0031, ADR 0033).
public protocol CloudSpeechConsentStoring: AnyObject, Sendable {
    var consentedProvider: CloudSpeechProviderID? { get set }
    /// The gateway's `consentVersion` the user saw when they agreed.
    var consentedVersion: Int? { get set }
}

/// Lets the engine run only for the provider and consent version the user agreed to, and only when a
/// subscription can be shown to the gateway. Without consent the engine reports that it cannot run and
/// sends nothing. The "credential" is a placeholder: the real access token is added to each request by the
/// gateway transport, so it is never held here.
public struct GatewayCredentials: CloudCredentialProviding {
    private let consent: any CloudSpeechConsentStoring
    private let access: any GatewayAccessing
    private let directory: any GatewayCapabilitiesProviding

    public init(
        consent: any CloudSpeechConsentStoring, access: any GatewayAccessing,
        directory: any GatewayCapabilitiesProviding
    ) {
        self.consent = consent
        self.access = access
        self.directory = directory
    }

    public func credential(for provider: CloudSpeechProviderID) async -> CloudCredential? {
        guard consent.consentedProvider == provider, let agreed = consent.consentedVersion else { return nil }
        // If the gateway cannot be reached, the agreement stands: the request itself will fail as offline.
        if let current = try? await directory.capabilities().consentVersion, current != agreed { return nil }
        guard await access.canObtainToken() else { return nil }
        return CloudCredential(secret: "gateway")
    }
}
