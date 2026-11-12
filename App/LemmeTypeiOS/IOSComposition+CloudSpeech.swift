import Domain
import Foundation
import Recognition
import Support

/// Cloud speech on iPhone and iPad (E12-S1, E13-S3, ADRs 0031 and 0033).
extension IOSComposition {
    /// Whether this build offers cloud speech at all (ADR 0031). Debug only until
    /// every launch gate is closed: E13-S8 changes this one line.
    static var offersCloudSpeech: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// The LemmeType gateway (ADR 0033), the only host audio is sent to in Cloud mode. Debug builds use
    /// staging. A Release build has cloud speech off, so its host is a placeholder that cannot resolve; E13-S8
    /// sets the production host when the gateway has its own domain.
    static var gatewayHost: String {
        #if DEBUG
            "speech-gateway-staging-625772045363.asia-south1.run.app"
        #else
            "gateway.invalid"
        #endif
    }

    /// Everything the gateway gives the app: a token, the terms version, and the allowance.
    typealias GatewayServing = GatewayAccessing & GatewayCapabilitiesProviding & GatewayAllowanceProviding

    /// What cloud speech needs, or nothing in a build that doesn't offer it.
    struct CloudSpeechServices {
        let provider: any CloudSpeechProvider
        let consent: any CloudSpeechConsentStoring
        let gateway: any GatewayServing
    }

    /// The subscription proof is StoreKit's signed transaction (E13-S4). Until that exists there is none, so
    /// Cloud speech cannot be used in a build without a staging test token.
    struct NoSubscriptionProof: SubscriptionProofProviding {
        func signedTransaction() async -> String? { nil }
    }

    static func liveCloudSpeech() -> CloudSpeechServices? {
        guard offersCloudSpeech else { return nil }
        // An earlier build asked for the user's own API key. Nothing reads one any more, so remove it.
        LegacyCloudKeyEraser().erase()
        let host = gatewayHost
        let gateway = GatewayService(
            host: host, transport: URLSessionCloudSpeechTransport(allowedHost: host), proofs: NoSubscriptionProof(),
            fixedToken: stagingToken)
        return CloudSpeechServices(
            provider: GatewaySpeechProvider(host: host), consent: UserDefaultsCloudSpeechConsent(), gateway: gateway)
    }

    /// A fixed gateway token for trying staging in a Debug build: launch with `-LemmeTypeGatewayToken <token>`.
    /// Never present in a Release build.
    private static var stagingToken: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "LemmeTypeGatewayToken")
        #else
            nil
        #endif
    }

    static func cloudEngines(
        _ services: CloudSpeechServices?, diagnostics: any DiagnosticsRecording
    ) -> [any SpeechRecognitionEngine] {
        guard let services else { return [] }
        return [
            CloudSpeechEngine(
                provider: services.provider,
                transport: GatewayTransport(
                    base: URLSessionCloudSpeechTransport(allowedHost: services.provider.host),
                    access: services.gateway),
                credentials: GatewayCredentials(
                    consent: services.consent, access: services.gateway, directory: services.gateway),
                diagnostics: diagnostics)
        ]
    }
}
