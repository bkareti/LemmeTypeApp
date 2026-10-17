import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

struct TranscriptionPipelineTests {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Pipeline-\(UUID().uuidString)", isDirectory: true)

    static func makeSession(engine: RecognitionEngineID? = nil, mode: WritingMode = .exact) throws -> DictationSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).placeholder")
        try Data("not audio".utf8).write(to: url)
        return DictationSession(
            audio: RecordedAudio(fileURL: url, duration: 2, format: .speech),
            target: ActivationTarget(
                processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit",
                focusedElement: nil),
            mode: mode, language: "en-US", engine: engine)
    }

    static func exists(_ session: DictationSession) -> Bool {
        FileManager.default.fileExists(atPath: session.audio.fileURL.path)
    }

    func makePipeline(
        engines: [FakeRecognitionEngine],
        preferred: RecognitionEngineID? = nil,
        delivery: FakeTextDelivery = FakeTextDelivery(),
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) -> TranscriptionPipeline {
        TranscriptionPipeline(
            engines: engines, preferredEngine: { preferred }, delivery: delivery, diagnostics: diagnostics)
    }

    @Test func oneSessionProducesOneDeliveryAndDeletesTheAudio() async throws {
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "  Ship   it  "))
        let delivery = FakeTextDelivery()
        let session = try Self.makeSession()
        let phases = Mutex<[ProcessingUpdate]>([])

        let outcome = await makePipeline(engines: [engine], delivery: delivery).process(session) { update in
            phases.withLock { $0.append(update) }
        }

        #expect(outcome == .delivered(.accessibility))
        #expect(engine.recognizeCount == 1)
        #expect(delivery.delivered == ["Ship it"])
        #expect(delivery.targets == ["TextEdit"])
        #expect(!Self.exists(session))
        #expect(
            phases.withLock { $0 } == [
                .phase(.preparingEngine), .phase(.recognizing), .phase(.writing), .phase(.delivering),
            ])
    }

    @Test func automaticPicksTheFirstReadyEngine() async throws {
        let apple = FakeRecognitionEngine(id: .appleSpeech, availability: .permissionUnavailable)
        let whisper = FakeRecognitionEngine(id: .whisper)
        let outcome = await makePipeline(engines: [apple, whisper]).process(try Self.makeSession()) { _ in }

        #expect(outcome == .delivered(.accessibility))
        #expect(apple.recognizeCount == 0)
        #expect(whisper.recognizeCount == 1)
    }

    @Test func unavailableChosenEngineAsksInsteadOfSwitching() async throws {
        let apple = FakeRecognitionEngine(id: .appleSpeech)
        let whisper = FakeRecognitionEngine(id: .whisper, availability: .assetsMissing)
        let session = try Self.makeSession()
        let outcome = await makePipeline(engines: [apple, whisper], preferred: .whisper).process(session) { _ in }

        #expect(
            outcome
                == .needsAttention(
                    .engineUnavailable(.whisper, .assetsMissing), engine: .whisper, alternatives: [.appleSpeech],
                    transcript: nil))
        #expect(apple.recognizeCount == 0)
        #expect(Self.exists(session))  // kept for the user's decision
    }

    @Test func noReadyEngineNeedsAttention() async throws {
        let outcome = await makePipeline(engines: [FakeRecognitionEngine(availability: .assetsMissing)])
            .process(try Self.makeSession()) { _ in }
        #expect(outcome == .needsAttention(.noEngineAvailable, engine: nil, alternatives: [], transcript: nil))
    }

    @Test func recognitionFailureKeepsAudioAndOffersRetryAndOtherEngines() async throws {
        let apple = FakeRecognitionEngine(id: .appleSpeech, script: .init(error: .engineFailure(code: 7)))
        let whisper = FakeRecognitionEngine(id: .whisper)
        let session = try Self.makeSession()
        let outcome = await makePipeline(engines: [apple, whisper]).process(session) { _ in }

        guard case .needsAttention(let issue, let engine, let alternatives, let transcript) = outcome else {
            Issue.record("expected needsAttention, got \(outcome)")
            return
        }
        #expect(issue == .recognitionFailed(.engineFailure(code: 7)))
        #expect(engine == .appleSpeech)
        #expect(alternatives == [.whisper])
        #expect(transcript == nil)
        #expect(Self.exists(session))
        #expect(issue.actions(alternatives: alternatives) == [.retry, .useEngine(.whisper), .saveAudio, .discard])
    }

    @Test func retryUsesTheSessionsEngineEvenIfThePreferenceChanged() async throws {
        let apple = FakeRecognitionEngine(id: .appleSpeech)
        let whisper = FakeRecognitionEngine(id: .whisper)
        let session = try Self.makeSession(engine: .appleSpeech)
        _ = await makePipeline(engines: [apple, whisper], preferred: .whisper).process(session) { _ in }

        #expect(apple.recognizeCount == 1)
        #expect(whisper.recognizeCount == 0)
    }

    @Test func cancellationNeverDeliversAndKeepsAudioForTheOwner() async throws {
        let engine = FakeRecognitionEngine(script: .init(delay: .seconds(30)))
        let delivery = FakeTextDelivery()
        let session = try Self.makeSession()
        let pipeline = makePipeline(engines: [engine], delivery: delivery)

        let task = Task { await pipeline.process(session) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        #expect(await task.value == .cancelled)
        #expect(delivery.delivered.isEmpty)
    }

    @Test func deliveryProblemKeepsTheTranscriptForCopyAndRetry() async throws {
        let delivery = FakeTextDelivery(outcome: .problem(.targetChanged))
        let session = try Self.makeSession()
        let pipeline = makePipeline(engines: [FakeRecognitionEngine(script: .init(text: "hello"))], delivery: delivery)

        let outcome = await pipeline.process(session) { _ in }
        #expect(
            outcome
                == .needsAttention(
                    .deliveryFailed(.targetChanged), engine: FakeRecognitionEngine().descriptor.id, alternatives: [],
                    transcript: "hello"))
        #expect(Self.exists(session))

        delivery.setOutcome(.delivered(.paste))
        #expect(await pipeline.deliver("hello", for: session) == .delivered(.paste))
        #expect(!Self.exists(session))
    }

    @Test func writingModeIsAppliedFromTheSession() async throws {
        let delivery = FakeTextDelivery()
        let pipeline = TranscriptionPipeline(
            engines: [FakeRecognitionEngine(script: .init(text: "um hello"))], preferredEngine: { nil },
            write: { text, mode in mode == .clean ? "Hello." : text }, delivery: delivery)
        _ = await pipeline.process(try Self.makeSession(mode: .clean)) { _ in }
        #expect(delivery.delivered == ["Hello."])
    }

    @Test func productionCleanerKeepsExactAndCleansClean() async throws {
        for (mode, expected) in [(WritingMode.exact, "um the the plan"), (.clean, "The plan.")] {
            let delivery = FakeTextDelivery()
            let pipeline = TranscriptionPipeline(
                engines: [FakeRecognitionEngine(script: .init(text: " um  the the plan "))], preferredEngine: { nil },
                write: TextCleaner.write, delivery: delivery)
            _ = await pipeline.process(try Self.makeSession(mode: mode)) { _ in }
            #expect(delivery.delivered == [expected])
        }
    }

    @Test func metricsCarryDurationsAndCategoriesButNoText() async throws {
        let buffer = RecordingDiagnostics()
        let engine = FakeRecognitionEngine(script: .init(text: "canary-dictated-words"))
        _ = await makePipeline(engines: [engine], diagnostics: buffer).process(try Self.makeSession()) { _ in }
        let failing = FakeRecognitionEngine(script: .init(error: .modelLoadFailed))
        _ = await makePipeline(engines: [failing], diagnostics: buffer).process(try Self.makeSession()) { _ in }

        let events = buffer.events
        #expect(events.map(\.name) == ["session.delivered", "session.needs-attention"])
        #expect(events[1].attributes["issue"] == .identifier("recognition.model-load-failed"))
        #expect(events[0].attributes["audioSeconds"] == .seconds(2))
        #expect(events[0].attributes["mode"] == .identifier("exact"))
        #expect(!String(describing: events).contains("canary"))
    }

    @Test func actionsForEachIssue() {
        #expect(DictationIssue.recognitionFailed(.noSpeechDetected).actions(alternatives: []) == [.discard])
        #expect(
            DictationIssue.recognitionFailed(.permissionDenied).actions(alternatives: [])
                == [.allowSpeechRecognition, .retry, .saveAudio, .discard])
        #expect(
            DictationIssue.noEngineAvailable.actions(alternatives: []) == [.chooseEngine, .saveAudio, .discard])
        #expect(
            DictationIssue.deliveryFailed(.targetChanged).actions(alternatives: [])
                == [.copyText, .retryDelivery, .discard])
        #expect(
            DictationIssue.deliveryFailed(.permissionMissing).actions(alternatives: [])
                == [.copyText, .openPermissions, .discard])
        #expect(DictationIssue.deliveryFailed(.secureField).actions(alternatives: []) == [.copyText, .discard])
    }

    @Test func engineSelectorTreatsUnknownPreferenceAsAutomatic() {
        let choice = EngineSelector.choose(
            preferred: RecognitionEngineID(rawValue: "retired"), candidates: [(.whisper, .ready)])
        #expect(choice == .engine(.whisper))
        #expect(EngineSelector.choose(preferred: nil, candidates: [(.whisper, .assetsMissing)]) == .noneAvailable)
    }
}

/// Collects diagnostics events in memory.
final class RecordingDiagnostics: DiagnosticsRecording {
    private let storage = Mutex<[DiagnosticEvent]>([])
    var events: [DiagnosticEvent] { storage.withLock { $0 } }

    func record(
        _ category: DiagnosticCategory, _ name: StaticString, _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {
        let event = DiagnosticEvent(timestamp: Date(), category: category, name: name, attributes: attributes)
        storage.withLock { $0.append(event) }
    }
}
