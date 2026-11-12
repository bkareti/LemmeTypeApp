import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

private struct ExampleProvider: CloudSpeechProvider {
    let id = CloudSpeechProviderID(rawValue: "lemmetype-gateway")
    let displayName = "LemmeType"
    let host = "gateway.example.test"
    let maximumClipSeconds = 30.0
    let supportedLanguages = ["te"]
    let tasks: Set<RecognitionTask> = [.transcribe]

    func request(
        for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential
    ) throws(RecognitionError) -> CloudHTTPRequest {
        throw .cloudServiceFailed
    }

    func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String { "" }
}

/// E12-S1 and E13-S3: turning cloud speech on and off. There is no key to enter.
@MainActor
struct CloudSpeechSettingsModelTests {
    private let provider = ExampleProvider()
    let consent = FakeCloudSpeechConsent()
    let gateway = FakeGatewayAccess(consentVersion: 3)

    private func makeModel() -> CloudSpeechSettingsModel {
        CloudSpeechSettingsModel(provider: provider, consent: consent, directory: gateway, allowances: gateway)
    }

    @Test func aFreshInstallIsOffAndNamesTheService() async {
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .off)
        #expect(model.providerName == "LemmeType")
        #expect(model.host == "gateway.example.test")
    }

    @Test func turningOnAsksFirstAndDecliningChangesNothing() async {
        let model = makeModel()
        model.requestTurnOn()
        #expect(model.isShowingConsent)
        #expect(consent.consentedProvider == nil, "asking is not agreeing")
        model.declineConsent()
        await model.refresh()
        #expect(!model.isShowingConsent)
        #expect(model.status == .off)
    }

    @Test func agreeingTurnsItOnAndRemembersTheVersionOfTheTerms() async {
        let model = makeModel()
        var offered: [Bool] = []
        model.onChange = { offered.append($0) }
        var ready = 0
        model.onReady = { ready += 1 }
        await model.acceptConsent()
        #expect(model.status == .turnedOn)
        #expect(consent.consentedProvider == provider.id)
        #expect(consent.consentedVersion == 3)
        #expect(offered.last == true)
        #expect(ready == 1)
    }

    @Test func anAgreementForAnotherProviderIsNotAccepted() async {
        consent.consentedProvider = CloudSpeechProviderID(rawValue: "sarvam")
        consent.consentedVersion = 3
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .off)
    }

    @Test func anOldAgreementWithNoVersionIsNotAccepted() async {
        consent.consentedProvider = provider.id
        consent.consentedVersion = nil
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .off)
    }

    @Test func aNewVersionOfTheTermsAsksAgain() async {
        consent.consentedProvider = provider.id
        consent.consentedVersion = 2
        let model = makeModel()
        var offered: [Bool] = []
        model.onChange = { offered.append($0) }
        await model.refresh()
        #expect(model.status == .turnedOn, "launch trusts what is stored")
        await model.verifyTerms()
        #expect(model.status == .needsConsentAgain)
        #expect(offered.last == false, "the engine is not offered until the user agrees again")
        await model.refresh()
        #expect(model.status == .needsConsentAgain, "a local refresh does not hide the change")
        await model.acceptConsent()
        #expect(model.status == .turnedOn)
        #expect(consent.consentedVersion == 3)
    }

    @Test func launchingUsesNoNetwork() async {
        consent.consentedProvider = provider.id
        consent.consentedVersion = 2
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .turnedOn)
        #expect(gateway.capabilityCalls == 0, "refresh at launch never asks the gateway")
        await model.verifyTerms()
        #expect(gateway.capabilityCalls == 1)
    }

    @Test func offlineTheAgreementStands() async {
        consent.consentedProvider = provider.id
        consent.consentedVersion = 2
        gateway.setCapabilitiesFailure(.offline)
        let model = makeModel()
        await model.refresh()
        await model.verifyTerms()
        #expect(model.status == .turnedOn)
    }

    @Test func turningOnNeedsASubscriptionAndAConnection() async {
        gateway.setCapabilitiesFailure(.subscriptionRequired)
        let model = makeModel()
        await model.acceptConsent()
        #expect(model.status == .off)
        #expect(model.problem == .subscriptionRequired)
        #expect(consent.consentedProvider == nil, "nothing is recorded when it could not be turned on")

        gateway.setCapabilitiesFailure(.offline)
        await model.acceptConsent()
        #expect(model.problem == .offline)
        gateway.setCapabilitiesFailure(.failed)
        await model.acceptConsent()
        #expect(model.problem == .failed)

        gateway.setCapabilitiesFailure(nil)
        await model.acceptConsent()
        #expect(model.problem == nil)
        #expect(model.status == .turnedOn)
    }

    @Test func theAllowanceIsShownOnlyWhileItIsOn() async {
        let allowance = GatewayAllowance(allowanceSeconds: 7200, usedSeconds: 600, periodEnd: .distantFuture)
        gateway.setAllowance(allowance)
        let model = makeModel()
        await model.refreshAllowance()
        #expect(model.allowance == nil)
        await model.acceptConsent()
        #expect(model.allowance == allowance, "it is there as soon as Cloud speech is on")
        #expect(model.allowance?.remainingMinutes == 110)
    }

    @Test func turningOffRemovesTheAgreement() async {
        let model = makeModel()
        await model.acceptConsent()
        var turnedOff = 0
        model.onTurnedOff = { turnedOff += 1 }
        await model.turnOff()
        #expect(model.status == .off)
        #expect(consent.consentedProvider == nil)
        #expect(consent.consentedVersion == nil)
        #expect(turnedOff == 1)
    }

    @Test func eraseReportsWhetherThereWasAnythingToRemove() async {
        let model = makeModel()
        #expect(await model.eraseAll() == false)
        await model.acceptConsent()
        #expect(await model.eraseAll() == true)
        #expect(consent.consentedProvider == nil)
    }

    @Test func noTokenOrKeyReachesPreferencesOrDescriptions() async {
        let model = makeModel()
        await model.acceptConsent()
        let seen = String(describing: model) + String(reflecting: model)
        #expect(!seen.contains("test-token"))
        #expect(consent.consentedProvider?.rawValue == "lemmetype-gateway", "only the service's name is remembered")
    }

    @Test func theModesEditorOffersTheCloudEngineOnlyWhenOn() {
        let modes = ModesSettingsModel(
            personalization: PersonalizationModel(store: FakePersonalizationStore()), preferences: FakePreferences(),
            engines: [.appleSpeech, .whisper])
        #expect(!modes.engines.contains(.cloud))
        modes.setOffersCloudEngine(true)
        #expect(modes.engines == [.appleSpeech, .whisper, .cloud])
        modes.setOffersCloudEngine(true)
        #expect(modes.engines.filter(\.isCloud).count == 1)
        modes.setOffersCloudEngine(false)
        #expect(modes.engines == [.appleSpeech, .whisper])
    }

    @Test func theEngineHasAName() {
        #expect(RecognitionEngineID.cloud.displayName == "Cloud")
    }

    @Test func agreeingTellsTheAppItIsReadyAndTurningOffTellsItToTidyUp() async {
        let model = makeModel()
        var ready = 0
        var turnedOff = 0
        model.onReady = { ready += 1 }
        model.onTurnedOff = { turnedOff += 1 }
        gateway.setCapabilitiesFailure(.subscriptionRequired)
        await model.acceptConsent()
        #expect(ready == 0, "no subscription, so nothing is ready")
        gateway.setCapabilitiesFailure(nil)
        await model.acceptConsent()
        #expect(ready == 1)
        await model.turnOff()
        #expect(turnedOff == 1)
        await model.turnOff()
        #expect(turnedOff == 1, "nothing was removed the second time")
    }
}
