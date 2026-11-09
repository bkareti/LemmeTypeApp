import Domain
import Recognition
import Support

/// Cloud speech on iPhone and iPad (E12-S1, ADR 0031).
extension IOSComposition {
    /// Whether this build offers cloud speech at all (ADR 0031). Debug only until
    /// every launch gate is closed: E12-S4 changes this one line.
    static var offersCloudSpeech: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// What cloud speech needs, or nothing in a build that doesn't offer it.
    struct CloudSpeechServices {
        let provider: any CloudSpeechProvider
        let store: any CloudCredentialStoring
        let consent: any CloudSpeechConsentStoring
    }

    static func liveCloudSpeech() -> CloudSpeechServices? {
        guard offersCloudSpeech else { return nil }
        return CloudSpeechServices(
            provider: SarvamProvider(), store: KeychainCloudCredentialStore(), consent: UserDefaultsCloudSpeechConsent()
        )
    }

    static func cloudEngines(
        _ services: CloudSpeechServices?, diagnostics: any DiagnosticsRecording
    ) -> [any SpeechRecognitionEngine] {
        guard let services else { return [] }
        return [
            CloudSpeechEngine(
                provider: services.provider,
                transport: URLSessionCloudSpeechTransport(allowedHost: services.provider.host),
                credentials: ConsentedCloudCredentials(store: services.store, consent: services.consent),
                diagnostics: diagnostics)
        ]
    }
}
