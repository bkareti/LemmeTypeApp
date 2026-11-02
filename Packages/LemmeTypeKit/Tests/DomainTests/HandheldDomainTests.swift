import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

/// E8-S5, E8-S6, E8-S7: the platform-neutral rules the iPhone and iPad app rely on.
struct DeviceFitTests {
    private static let gigabyte: UInt64 = 1 << 30

    /// A handheld reports a little less than the memory it is sold with.
    private func profile(_ device: DeviceClass, nominal: Int) -> HardwareProfile {
        let reported = UInt64(Double(nominal) * 0.93 * Double(Self.gigabyte))
        return HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: reported, deviceClass: device)
    }

    private func fit(_ id: ModelAssetID, on hardware: HardwareProfile) throws -> ModelFit {
        try #require(ModelCatalog.asset(id)).hardware.fit(for: hardware)
    }

    @Test(arguments: [
        ("iPhone17,1", DeviceClass.iPhone), ("iPad16,3", .iPad), ("Mac15,3", .mac), ("arm64", .mac), ("", .mac),
    ])
    func deviceClassComesFromTheModelIdentifier(identifier: String, expected: DeviceClass) {
        #expect(DeviceClass.detect(machineIdentifier: identifier) == expected)
        #expect(expected.isHandheld == (expected != .mac))
    }

    @Test func nominalMemorySnapsToTheSizeTheDeviceIsSoldWith() {
        #expect(profile(.iPhone, nominal: 6).nominalMemoryGigabytes == 6)
        #expect(profile(.iPhone, nominal: 8).nominalMemoryGigabytes == 8)
        #expect(profile(.iPad, nominal: 16).nominalMemoryGigabytes == 16)
    }

    @Test func tinyAndBaseRunOnPhonesFromSixGigabytes() throws {
        for id in [ModelAssetID.whisperTinyEnglish, .whisperBaseEnglish, .whisperTiny, .whisperBase] {
            #expect(try fit(id, on: profile(.iPhone, nominal: 4)) == .unsupported(.insufficientMemory))
            #expect(try fit(id, on: profile(.iPhone, nominal: 6)) == .supported)
            #expect(try fit(id, on: profile(.iPhone, nominal: 8)) == .recommended)
            #expect(try fit(id, on: profile(.iPad, nominal: 6)) == .supported)
        }
    }

    @Test func smallRunsOnlyOnIPadsWithEightGigabytes() throws {
        for id in [ModelAssetID.whisperSmallEnglish, .whisperSmall] {
            #expect(try fit(id, on: profile(.iPhone, nominal: 8)) == .unsupported(.hardware))
            #expect(try fit(id, on: profile(.iPhone, nominal: 12)) == .unsupported(.hardware))
            #expect(try fit(id, on: profile(.iPad, nominal: 6)) == .unsupported(.insufficientMemory))
            #expect(try fit(id, on: profile(.iPad, nominal: 8)) == .supported)
            #expect(try fit(id, on: profile(.iPad, nominal: 16)) == .recommended)
        }
    }

    @Test func macFitIsUnchangedByTheHandheldTable() throws {
        let mac = HardwareProfile(isAppleSilicon: true, physicalMemoryBytes: 8 * Self.gigabyte)
        let intel = HardwareProfile(isAppleSilicon: false, physicalMemoryBytes: 16 * Self.gigabyte)
        #expect(mac.deviceClass == .mac)
        #expect(try fit(.whisperBaseEnglish, on: mac) == .recommended)
        #expect(try fit(.whisperSmallEnglish, on: mac) == .supported)
        #expect(try fit(.whisperBaseEnglish, on: intel) == .unsupported(.hardware))
    }
}

struct CopiedTextTests {
    @MainActor
    final class RecordingWriter: ExpiringPasteboardWriting {
        var writes: [(text: String, lifetime: TimeInterval)] = []
        func write(_ text: String, lifetime: TimeInterval) { writes.append((text, lifetime)) }
    }

    @MainActor
    @Test func copyWritesTheReviewedTextOnceWithTheChosenLifetime() async {
        let writer = RecordingWriter()
        let copier = ExpiringTextCopier(writer: writer, lifetime: { .tenMinutes })

        await copier.copy("Ship it Friday")

        #expect(writer.writes.count == 1)
        #expect(writer.writes.first?.text == "Ship it Friday")
        #expect(writer.writes.first?.lifetime == 600)
    }

    @Test func lifetimesAreShortAndTheDefaultIsTwoMinutes() {
        #expect(CopiedTextLifetime.allCases.map(\.seconds) == [60, 120, 600])
        #expect(CopiedTextLifetime.default == .twoMinutes)
    }

    @Test func aPhoneHasNoTargetToDeliverTo() async {
        let outcome = await NoTargetDelivery().deliver("text", to: nil)
        #expect(outcome == .problem(.noTarget))
    }
}

struct LaunchRequestInboxTests {
    private func inbox(_ clock: TestNow, lifetime: TimeInterval = 10) -> LaunchRequestInbox {
        LaunchRequestInbox(lifetime: lifetime, now: { clock.date })
    }

    @Test func aRequestIsConsumedOnce() {
        let clock = TestNow()
        let inbox = inbox(clock)
        let posted = inbox.post()

        #expect(inbox.consume() == posted)
        #expect(inbox.consume() == nil)
    }

    @Test func anExpiredRequestStartsNothingAndIsCleared() {
        let clock = TestNow()
        let inbox = inbox(clock)
        inbox.post()

        clock.advance(by: 11)

        #expect(inbox.consume() == nil)
        #expect(inbox.consume() == nil)
    }

    @Test func aRequestJustInsideItsLifetimeIsStillValid() {
        let clock = TestNow()
        let inbox = inbox(clock)
        inbox.post()

        clock.advance(by: 10)

        #expect(inbox.consume() != nil)
    }

    @Test func aNewerRequestReplacesAnOlderOne() {
        let clock = TestNow()
        let inbox = inbox(clock)
        inbox.post()
        clock.advance(by: 3)
        let newer = inbox.post()

        #expect(inbox.consume() == newer)
        #expect(inbox.consume() == nil)
    }

    @Test func nothingIsPendingUntilARequestIsPosted() {
        #expect(inbox(TestNow()).consume() == nil)
    }
}

struct RecordingLimitsTests {
    @Test func theMacHasNoLimitAndHandheldsStopAtFiveMinutes() {
        #expect(RecordingLimits.none.maximumDuration == nil)
        #expect(RecordingLimits.handheld.maximumDuration == .seconds(300))
    }
}

struct ReviewEveryResultPipelineTests {
    @Test func everyDictationEndsInAReviewAndIsNeverDelivered() async throws {
        let engine = FakeRecognitionEngine(id: .whisper, script: .init(text: "  Ship   it  "))
        let delivery = FakeTextDelivery()
        let session = try TranscriptionPipelineTests.makeSession()
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: delivery, reviewsEveryResult: true)

        let outcome = await pipeline.process(session) { _ in }

        #expect(
            outcome == .needsAttention(.reviewText, engine: .whisper, alternatives: [], transcript: "Ship it"))
        #expect(delivery.delivered.isEmpty)
        #expect(!TranscriptionPipelineTests.exists(session))  // the text is final; nothing can use the audio
    }

    @Test func theReviewOffersCopyAndDiscardOnly() {
        #expect(DictationIssue.reviewText.actions(alternatives: []) == [.copyText, .discard])
        #expect(DictationIssue.reviewText.identifier == "review.text")
    }

    @Test func withoutTheOptionTextIsDeliveredAsBefore() async throws {
        let engine = FakeRecognitionEngine(id: .whisper, script: .init(text: "Ship it"))
        let delivery = FakeTextDelivery()
        let pipeline = TranscriptionPipeline(engines: [engine], delivery: delivery)

        let outcome = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        #expect(outcome == .delivered(.accessibility))
        #expect(delivery.delivered == ["Ship it"])
    }

    @Test func silenceIsStillReportedInsteadOfReviewed() async throws {
        let engine = FakeRecognitionEngine(id: .whisper, script: .init(text: "   "))
        let pipeline = TranscriptionPipeline(
            engines: [engine], delivery: FakeTextDelivery(), reviewsEveryResult: true)

        let outcome = await pipeline.process(try TranscriptionPipelineTests.makeSession()) { _ in }

        guard case .needsAttention(.recognitionFailed(.noSpeechDetected), _, _, _) = outcome else {
            Issue.record("expected no speech, got \(outcome)")
            return
        }
    }
}
