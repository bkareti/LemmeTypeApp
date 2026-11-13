import Domain
import Foundation
import TestSupport
import Testing

@testable import Audio
@testable import UI

/// E13-S5: without a trial or subscription nothing is recorded, from any way of starting.
@MainActor
struct RecordingCoordinatorEntitlementTests {
    private let source = FakeAudioSource()
    private let processor = RecordingSpy()
    private let storage = AudioSessionStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CoordinatorEntitlement-\(UUID().uuidString)", isDirectory: true))

    private func makeCoordinator(_ entitlement: (any EntitlementChecking)?) -> RecordingCoordinator {
        RecordingCoordinator(
            capture: AudioCaptureService(
                source: source, storage: storage, permissions: FakePermissions(statuses: [.microphone: .granted])),
            processor: processor, feedback: FakeFeedback(), preferences: FakePreferences(),
            finishedDisplay: .milliseconds(50), failureDisplay: .milliseconds(50), entitlement: entitlement)
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: storage.directory) }

    private var files: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil)) ?? []
    }

    @Test(arguments: [
        EntitlementBlockReason.noSubscription, .expired, .revoked, .paymentProblem, .unconfirmed,
    ])
    func aBlockedStartIsRefusedBeforeTheMicrophoneOpens(reason: EntitlementBlockReason) async {
        defer { cleanUp() }
        let entitlement = FakeEntitlement(.blocked(reason))
        let coordinator = makeCoordinator(entitlement)
        var offered = 0
        coordinator.onOpenSubscription = { offered += 1 }

        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()

        #expect(coordinator.attention == .subscriptionRequired(reason))
        #expect(!source.isRunning, "the microphone never opened")
        #expect(files.isEmpty, "nothing was captured")
        #expect(coordinator.attentionActions == [.openSubscription, .discard])
        #expect(offered == 1, "the subscription offer is shown")
        #expect(entitlement.asked == 1)
        #expect(!reason.userMessage.isEmpty)
    }

    @Test func theSeeSubscriptionChoiceShowsTheOfferAgain() async {
        defer { cleanUp() }
        let coordinator = makeCoordinator(FakeEntitlement(.blocked(.expired)))
        var offered = 0
        coordinator.onOpenSubscription = { offered += 1 }
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        offered = 0

        coordinator.perform(.openSubscription)
        await coordinator.settle()

        #expect(offered == 1)
    }

    @Test(arguments: [
        EntitlementDecision.allowed, .allowedUnconfirmed(until: Date(timeIntervalSince1970: 2_000_000_000)),
    ])
    func anAllowedStartRecordsAsBefore(decision: EntitlementDecision) async {
        defer { cleanUp() }
        let coordinator = makeCoordinator(FakeEntitlement(decision))
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        #expect(source.isRunning)
        coordinator.requestCancel()
        await coordinator.settle()
    }

    @Test func withoutAnEntitlementCheckTheMacAppIsUnchanged() async {
        defer { cleanUp() }
        let coordinator = makeCoordinator(nil)
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(coordinator.state == .recording)
        coordinator.requestCancel()
        await coordinator.settle()
    }

    @Test func eachStartAsksAgainSoABoughtSubscriptionWorksAtOnce() async {
        defer { cleanUp() }
        let entitlement = FakeEntitlement(.blocked(.noSubscription))
        let coordinator = makeCoordinator(entitlement)
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()
        #expect(!source.isRunning)

        entitlement.set(.allowed)
        coordinator.perform(.discard)
        coordinator.handle(.start(FakeTargetCapturer.textEdit))
        await coordinator.settle()

        #expect(coordinator.state == .recording)
        #expect(entitlement.asked == 2)
        coordinator.requestCancel()
        await coordinator.settle()
    }
}
