import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

private struct ExampleProvider: CloudSpeechProvider {
    let id = CloudSpeechProviderID(rawValue: "sarvam")
    let displayName = "Sarvam"
    let host = "api.sarvam.ai"
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

/// E12-S1: turning cloud speech on and off.
@MainActor
struct CloudSpeechSettingsModelTests {
    private let provider = ExampleProvider()
    let store = FakeCloudCredentialStore()
    let consent = FakeCloudSpeechConsent()

    private func makeModel() -> CloudSpeechSettingsModel {
        CloudSpeechSettingsModel(provider: provider, store: store, consent: consent)
    }

    @Test func aFreshInstallIsOffAndNamesTheProvider() async {
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .off)
        #expect(model.providerName == "Sarvam")
        #expect(model.host == "api.sarvam.ai")
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

    @Test func consentThenAKeyTurnsItOn() async {
        let model = makeModel()
        var offered: [Bool] = []
        model.onChange = { offered.append($0) }
        await model.acceptConsent()
        #expect(model.status == .needsKey)
        await model.saveKey("  sk-test-key\n")
        #expect(model.status == .turnedOn)
        #expect(await store.credential(for: provider.id) == CloudCredential(secret: "sk-test-key"))
        #expect(offered.last == true)
        #expect(offered.dropLast().allSatisfy { !$0 }, "the engine is offered only once a key exists")
    }

    @Test func consentForAnotherProviderIsNotAccepted() async throws {
        consent.consentedProvider = CloudSpeechProviderID(rawValue: "someone-else")
        try store.save(CloudCredential(secret: "k"), for: provider.id)
        let model = makeModel()
        await model.refresh()
        #expect(model.status == .off)
    }

    @Test func aMissingKeyIsNotAKey() async {
        let model = makeModel()
        await model.acceptConsent()
        await model.saveKey("   ")
        #expect(model.status == .needsKey)
        #expect(model.keyProblem == .empty)
    }

    @Test func aKeyThatCannotBeSavedIsReported() async {
        store.setFailsToSave(true)
        let model = makeModel()
        await model.acceptConsent()
        await model.saveKey("sk-test-key")
        #expect(model.status == .needsKey)
        #expect(model.keyProblem == .notSaved)
    }

    @Test func turningOffRemovesTheKeyAndConsent() async {
        let model = makeModel()
        await model.acceptConsent()
        await model.saveKey("sk-test-key")
        await model.turnOff()
        #expect(model.status == .off)
        #expect(consent.consentedProvider == nil)
        #expect(await store.credential(for: provider.id) == nil)
    }

    @Test func eraseReportsWhetherThereWasAnythingToRemove() async {
        let model = makeModel()
        #expect(await model.eraseAll() == false)
        await model.acceptConsent()
        await model.saveKey("sk-test-key")
        #expect(await model.eraseAll() == true)
        #expect(await store.credential(for: provider.id) == nil)
    }

    @Test func theKeyReachesNoPreferencesOrDiagnostics() async throws {
        let canary = "canary-cloud-key-5e2a"
        let preferences = FakePreferences()
        let model = makeModel()
        await model.acceptConsent()
        await model.saveKey(canary)
        #expect(!String(describing: preferences).contains(canary))
        #expect(!String(describing: model).contains(canary))
        #expect(!String(reflecting: await store.credential(for: provider.id)).contains(canary))
        #expect(consent.consentedProvider?.rawValue == "sarvam", "only the provider's name is remembered")
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
}
