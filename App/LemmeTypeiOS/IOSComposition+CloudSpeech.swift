import Domain
import Foundation
import Recognition
import Support

/// Cloud speech on iPhone and iPad (E12-S1, E13-S3, ADRs 0031 and 0033).
extension IOSComposition {
    /// Whether this build offers cloud speech at all (ADR 0031). Debug always does (staging). A Release build does
    /// only in the `cloud` release scope and when `LEMMETYPE_GATEWAY_HOST` names the production gateway
    /// (`Config/LemmeTypeiOS.xcconfig`); both are set only once the launch gates in `docs/release/app-store.md` are
    /// closed (E13-S8). Version 1.0 is the `local` scope.
    static var offersCloudSpeech: Bool {
        #if DEBUG
            true
        #else
            releaseGatewayHost(from: Bundle.main.infoDictionary) != nil
        #endif
    }

    /// The production gateway host from the app's Info.plist, or `nil` when Cloud stays off: no host is set, or the
    /// build's release scope is not `cloud`. A host alone is not enough, because the `local` scope's microphone text,
    /// privacy manifest, and store answers all say nothing leaves the device.
    static func releaseGatewayHost(from info: [String: Any]?) -> String? {
        guard (info?["LemmeTypeReleaseScope"] as? String) == "cloud",
            let host = (info?["LemmeTypeGatewayHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty
        else { return nil }
        return host
    }

    /// The LemmeType gateway (ADR 0033), the only host audio is sent to in Cloud mode. Debug builds use staging.
    /// A Release build uses the production host, or a placeholder that cannot resolve while Cloud is off.
    static var gatewayHost: String {
        #if DEBUG
            "speech-gateway-staging-625772045363.asia-south1.run.app"
        #else
            releaseGatewayHost(from: Bundle.main.infoDictionary) ?? "gateway.invalid"
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

    /// `proofs` is the StoreKit subscription (E13-S4): its signed transaction is what the gateway checks. A
    /// Debug build can instead use a staging test token.
    static func liveCloudSpeech(proofs: any SubscriptionProofProviding) -> CloudSpeechServices? {
        guard offersCloudSpeech else { return nil }
        // An earlier build asked for the user's own API key. Nothing reads one any more, so remove it.
        LegacyCloudKeyEraser().erase()
        let host = gatewayHost
        // The gateway decides which Cloud languages are live (E12-S7); the app remembers its last answer.
        let languages = GatewayLanguages(store: UserDefaultsCloudLanguageStore())
        let gateway = GatewayService(
            host: host, transport: URLSessionCloudSpeechTransport(allowedHost: host), proofs: proofs,
            languages: languages, fixedToken: stagingToken)
        return CloudSpeechServices(
            provider: GatewaySpeechProvider(host: host, languages: languages),
            consent: UserDefaultsCloudSpeechConsent(), gateway: gateway)
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
