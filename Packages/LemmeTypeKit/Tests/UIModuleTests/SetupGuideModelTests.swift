import Domain
import Foundation
import TestSupport
import Testing

@testable import UI

private struct GatewayProvider: CloudSpeechProvider {
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

/// The microphone as the guide sees it: a status and the answer the system prompt gives.
@MainActor
private final class Microphone {
    var status: PermissionStatus
    let answer: PermissionStatus
    private(set) var requests = 0
    private(set) var settingsOpened = 0

    init(_ status: PermissionStatus = .notRequested, answer: PermissionStatus = .granted) {
        self.status = status
        self.answer = answer
    }

    func request() -> PermissionStatus {
        requests += 1
        status = answer
        return answer
    }

    func openSettings() { settingsOpened += 1 }
}

/// E8-S10: the first-run setup guide on iPhone and iPad.
@MainActor
struct SetupGuideModelTests {
    private static let iPhone = HardwareProfile(
        isAppleSilicon: true, physicalMemoryBytes: 8 << 30, deviceClass: .iPhone)
    private static let iPad = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 << 30, deviceClass: .iPad)
    private static let later = Date(timeIntervalSince1970: 4_000_000_000)

    let preferences = FakePreferences()
    let assets = FakeModelAssetManager()
    let speech = FakeSpeechAuthorizer(status: .notRequested)
    let seen = FakePaywallSeen()
    let consent = FakeCloudSpeechConsent()
    let gateway = FakeGatewayAccess()

    private func makeGuide(
        microphone: Microphone = Microphone(), hardware: HardwareProfile = iPhone,
        cloud: Bool = false, subscription: SubscriptionModel? = nil, appleSpeech: Bool = true,
        enginesChanged: @escaping @MainActor () async -> Void = {}
    ) -> SetupGuideModel {
        let models = ModelsSettingsModel(modelAssets: assets, preferences: preferences, hardware: hardware)
        return SetupGuideModel(
            preferences: preferences, deviceClass: hardware.deviceClass, models: models,
            cloudSpeech: cloud
                ? CloudSpeechSettingsModel(
                    provider: GatewayProvider(), consent: consent, directory: gateway, allowances: gateway)
                : nil,
            subscription: subscription,
            microphoneStatus: { microphone.status },
            requestMicrophone: { microphone.request() },
            openMicrophoneSettings: { microphone.openSettings() },
            speechAuthorizer: appleSpeech ? speech : nil,
            onEnginesChanged: enginesChanged)
    }

    // MARK: Who sees it

    @Test func aFreshInstallShowsTheGuideFromWelcome() {
        let guide = makeGuide()
        guide.begin()
        #expect(guide.isPresented)
        #expect(guide.step == .welcome)
        #expect(!preferences.hasCompletedOnboarding, "only finishing or closing marks it done")
    }

    @Test func someoneWhoAlreadyUsedTheMicrophoneSkipsIt() {
        let guide = makeGuide(microphone: Microphone(.granted))
        guide.begin()
        #expect(!guide.isPresented)
        #expect(preferences.hasCompletedOnboarding, "an upgrade is marked done silently")
    }

    @Test func aFinishedGuideIsNotShownAgain() {
        preferences.hasCompletedOnboarding = true
        let guide = makeGuide()
        guide.begin()
        #expect(!guide.isPresented)
    }

    @Test func closingFromAnyStepMarksItDone() {
        let guide = makeGuide()
        guide.begin()
        guide.next()
        guide.next()
        #expect(guide.step == .listening)
        guide.finish()
        #expect(!guide.isPresented)
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test func replayStartsAtWelcomeAndChangesNothing() async {
        let microphone = Microphone(.granted)
        preferences.hasCompletedOnboarding = true
        let guide = makeGuide(microphone: microphone)
        guide.replay()
        #expect(guide.isPresented)
        #expect(guide.step == .welcome)
        #expect(guide.choice == nil)
        #expect(guide.microphone == .granted)
        #expect(microphone.requests == 0)
        #expect(assets.installCount == 0)
        guide.finish()
        #expect(preferences.hasCompletedOnboarding)
    }

    // MARK: Steps

    @Test func anIPhoneWalksEveryStepAndTheLastOneFinishes() {
        let guide = makeGuide()
        guide.begin()
        #expect(guide.steps == [.welcome, .microphone, .listening, .anyApp, .done])
        #expect(!guide.canGoBack)
        for expected in [SetupGuideModel.Step.microphone, .listening, .anyApp, .done] {
            guide.next()
            #expect(guide.step == expected)
        }
        guide.back()
        #expect(guide.step == .anyApp)
        guide.next()
        guide.next()
        #expect(!guide.isPresented, "Next on All set finishes")
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test func anIPadSkipsTheAnyAppStep() {
        let guide = makeGuide(hardware: Self.iPad)
        guide.begin()
        #expect(guide.steps == [.welcome, .microphone, .listening, .done])
        guide.next()
        guide.next()
        guide.next()
        #expect(guide.step == .done)
    }

    // MARK: Microphone

    @Test func theMicrophoneStepAsksOnlyAfterContinue() async {
        let microphone = Microphone()
        let guide = makeGuide(microphone: microphone)
        guide.begin()
        guide.next()
        #expect(guide.step == .microphone)
        #expect(!guide.hasAskedForMicrophone)
        #expect(microphone.requests == 0, "reaching the step does not show the system prompt")

        await guide.allowMicrophone()
        #expect(microphone.requests == 1)
        #expect(guide.microphone == .granted)
        #expect(guide.microphoneReadiness == .ready)
        await guide.allowMicrophone()
        #expect(microphone.requests == 1, "the system is asked once")
    }

    @Test func aDeniedMicrophoneOffersSettings() async {
        let microphone = Microphone(answer: .denied)
        let guide = makeGuide(microphone: microphone)
        guide.begin()
        guide.next()
        await guide.allowMicrophone()
        #expect(guide.microphone == .denied)
        #expect(guide.hasAskedForMicrophone)
        #expect(guide.microphoneReadiness == .notSet)
        guide.openSettingsForMicrophone()
        #expect(microphone.settingsOpened == 1)
        guide.next()
        #expect(guide.step == .listening, "a denial does not stop the guide")
    }

    // MARK: Listening

    @Test func onThisDeviceOffersTheSuggestedModelAndWaitsForConfirmation() async {
        let guide = makeGuide()
        let suggested = try? #require(guide.models.suggestedModel)
        #expect(guide.listeningOptions.contains(.onDevice))

        await guide.chooseOnDevice()
        #expect(guide.choice == .onDevice)
        #expect(guide.models.downloadOffer?.asset.id == suggested?.id, "the same confirmation as Settings")
        #expect(assets.installCount == 0, "nothing downloads before the user confirms")

        guide.confirmDownload()
        await guide.models.settle()
        #expect(assets.installCount == 1)
        #expect(guide.suggestedModelState == .installed)
        #expect(guide.listeningReadiness == .ready)
    }

    @Test func anInstalledModelIsNotOfferedAgain() async {
        let guide = makeGuide()
        guard let suggested = guide.models.suggestedModel else {
            Issue.record("expected a suggested model")
            return
        }
        let installed = FakeModelAssetManager(installed: [suggested.id])
        let models = ModelsSettingsModel(modelAssets: installed, preferences: preferences, hardware: Self.iPhone)
        await models.refresh()
        let ready = SetupGuideModel(
            preferences: preferences, deviceClass: .iPhone, models: models,
            microphoneStatus: { .granted }, requestMicrophone: { .granted }, openMicrophoneSettings: {})
        await ready.chooseOnDevice()
        #expect(models.downloadOffer == nil)
        #expect(ready.listeningReadiness == .ready)
    }

    @Test func aDeviceThatRunsNoModelIsNotOfferedOne() {
        let guide = makeGuide(hardware: HardwareProfile(isAppleSilicon: false, physicalMemoryBytes: 2 << 30))
        #expect(guide.models.suggestedModel == nil)
        #expect(!guide.listeningOptions.contains(.onDevice))
        #expect(guide.listeningOptions.last == .later)
    }

    @Test func appleSpeechAsksForSpeechRecognitionOnce() async {
        var refreshes = 0
        let guide = makeGuide(enginesChanged: { refreshes += 1 })
        #expect(guide.listeningOptions.contains(.appleSpeech))
        await guide.chooseAppleSpeech()
        #expect(speech.requestCount == 1)
        #expect(guide.speechRecognition == .granted)
        #expect(guide.listeningReadiness == .ready)
        #expect(refreshes == 1, "the engines are checked again")
        await guide.chooseAppleSpeech()
        #expect(speech.requestCount == 1)
    }

    @Test func appleSpeechIsOfferedOnlyWhenTheBuildHasIt() {
        #expect(!makeGuide(appleSpeech: false).listeningOptions.contains(.appleSpeech))
    }

    @Test func cloudIsOfferedOnlyWhenTheBuildHasIt() {
        #expect(!makeGuide().listeningOptions.contains(.cloud))
        #expect(makeGuide(cloud: true).listeningOptions.contains(.cloud))
    }

    @Test func cloudWithoutASubscriptionShowsThePaywallAndStaysOff() async {
        let subscription = SubscriptionModel(service: FakeSubscriptionService(), seen: FakePaywallSeen(true))
        await subscription.start()
        let guide = makeGuide(cloud: true, subscription: subscription)
        guide.chooseCloud()
        #expect(subscription.isShowingPaywall)
        #expect(guide.cloudSpeech?.isShowingConsent == false)
        #expect(guide.cloudSpeech?.status == .off)
        #expect(guide.listeningReadiness == .notSet)
        subscription.stop()
    }

    @Test func cloudWithASubscriptionTurnsOnOnlyAfterAgree() async {
        let service = FakeSubscriptionService(state: .trialing(until: Self.later))
        let subscription = SubscriptionModel(service: service, seen: seen)
        await subscription.start()
        let guide = makeGuide(cloud: true, subscription: subscription)
        guide.chooseCloud()
        #expect(guide.cloudSpeech?.isShowingConsent == true, "the agreement is shown first")
        #expect(guide.cloudSpeech?.status == .off)
        #expect(!subscription.isShowingPaywall)

        await guide.cloudSpeech?.acceptConsent()
        #expect(guide.cloudSpeech?.status == .turnedOn)
        #expect(guide.listeningReadiness == .ready)
        subscription.stop()
    }

    @Test func decideLaterMovesOn() {
        let guide = makeGuide()
        guide.begin()
        guide.next()
        guide.next()
        guide.chooseLater()
        #expect(guide.choice == .later)
        #expect(guide.step == .anyApp)
        #expect(guide.listeningReadiness == .notSet)
    }

    // MARK: Paywall

    @Test func theOneTimePaywallWaitsForTheGuideAndThenAppearsOnce() async {
        let subscription = SubscriptionModel(service: FakeSubscriptionService(), seen: seen)
        let guide = makeGuide(subscription: subscription)
        guide.begin()
        await subscription.start()
        #expect(!subscription.isShowingPaywall, "it never covers the guide")
        #expect(!seen.hasSeenPaywall)

        guide.finish()
        #expect(subscription.isShowingPaywall, "it appears when the guide ends")
        #expect(seen.hasSeenPaywall)
        subscription.stop()
    }
}
