import Domain
import Foundation
import Testing
import UI

@testable import LemmeTypeiOS

/// E8-S4, E8-S6: the iPhone composition wires the shared pieces the way ADR 0027 says.
@MainActor
struct IOSCompositionTests {
    private func makeComposition() -> IOSComposition {
        IOSComposition.make(arguments: [IOSComposition.uiTestingArgument])
    }

    @Test func uiTestingModeUsesFakesAndStartsReady() {
        let composition = makeComposition()

        #expect(composition.mode == .uiTesting)
        #expect(composition.quick.screen == .ready)
        #expect(composition.recorder.state == .idle)
    }

    @Test func aRecordingHasATimeLimit() {
        #expect(makeComposition().recorder.limits == .handheld)
    }

    @Test func theIntentAndTheAppShareOneLaunchInbox() {
        let composition = makeComposition()

        composition.launchRequests.post()

        #expect(composition.launchRequests.consume() != nil)
        #expect(composition.launchRequests.consume() == nil)
    }

    @Test func aDictationEndsInAReviewAndIsNeverCopiedAutomatically() async throws {
        let composition = makeComposition()

        composition.quick.start()
        await composition.recorder.settle()
        #expect(composition.quick.screen == .recording)
        try await Task.sleep(for: .milliseconds(400))
        composition.quick.stop()
        await composition.recorder.settle()

        #expect(composition.quick.screen == .review(text: "hello from lemmetype"))
        composition.quick.discard()
        await composition.recorder.settle()
        #expect(composition.quick.screen == .ready)
    }

    @Test func copyConfirmsAndLeavesNothingBehind() async throws {
        let composition = makeComposition()
        composition.quick.start()
        await composition.recorder.settle()
        try await Task.sleep(for: .milliseconds(400))
        composition.quick.stop()
        await composition.recorder.settle()

        await composition.quick.copy()

        #expect(composition.quick.copiedFor == .twoMinutes)
        #expect(composition.quick.screen == .ready)
    }
}
