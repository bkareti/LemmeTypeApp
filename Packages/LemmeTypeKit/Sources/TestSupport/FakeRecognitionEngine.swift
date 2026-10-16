import Domain
import Foundation
import Synchronization

/// Deterministic recognition engine for tests and UI tests. Returns scripted
/// text after an optional delay, honouring cancellation like a real engine.
public final class FakeRecognitionEngine: SpeechRecognitionEngine {
    public struct Script: Sendable {
        public var text: String
        public var partials: [String]
        public var delay: Duration
        public var error: RecognitionError?
        /// Return the transcript even when cancelled, to prove that
        /// `RecognitionRunner` still reports cancellation.
        public var ignoresCancellation: Bool

        public init(
            text: String = "Hello from the fake engine.",
            partials: [String] = [],
            delay: Duration = .zero,
            error: RecognitionError? = nil,
            ignoresCancellation: Bool = false
        ) {
            self.text = text
            self.partials = partials
            self.delay = delay
            self.error = error
            self.ignoresCancellation = ignoresCancellation
        }
    }

    private struct State {
        var availability: EngineAvailability
        var script: Script
        var prepareCount = 0
        var recognizeCount = 0
        var unloadCount = 0
        var isPrepared = false
        var lastLanguage: String?
    }

    public let descriptor: EngineDescriptor
    private let state: Mutex<State>

    public init(
        id: RecognitionEngineID = RecognitionEngineID(rawValue: "fake"),
        availability: EngineAvailability = .ready,
        script: Script = Script(),
        supportedLanguages: [String] = ["en"],
        assets: AssetRequirement = .none,
        capabilities: EngineCapabilities = [.partialResults]
    ) {
        descriptor = EngineDescriptor(
            id: id, supportedLanguages: supportedLanguages, assets: assets, capabilities: capabilities)
        state = Mutex(State(availability: availability, script: script))
    }

    public var prepareCount: Int { state.withLock { $0.prepareCount } }
    public var recognizeCount: Int { state.withLock { $0.recognizeCount } }
    public var unloadCount: Int { state.withLock { $0.unloadCount } }
    public var isPrepared: Bool { state.withLock { $0.isPrepared } }
    public var lastLanguage: String? { state.withLock { $0.lastLanguage } }

    public func setAvailability(_ availability: EngineAvailability) {
        state.withLock { $0.availability = availability }
    }

    public func setScript(_ script: Script) {
        state.withLock { $0.script = script }
    }

    public func availability() async -> EngineAvailability {
        state.withLock { $0.availability }
    }

    public func prepare() async throws(RecognitionError) {
        let availability = state.withLock { state in
            state.prepareCount += 1
            return state.availability
        }
        if let error = availability.recognitionError { throw error }
        state.withLock { $0.isPrepared = true }
    }

    public func recognize(
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void
    ) async throws(RecognitionError) -> Transcript {
        let (availability, script) = state.withLock { state in
            state.recognizeCount += 1
            state.lastLanguage = request.language
            return (state.availability, state.script)
        }
        if let error = availability.recognitionError { throw error }
        if Task.isCancelled && !script.ignoresCancellation { throw .cancelled }
        let start = ContinuousClock.now
        for partial in script.partials {
            updates(.partial(partial))
        }
        if script.delay > .zero {
            do {
                try await Task.sleep(for: script.delay)
            } catch {
                if !script.ignoresCancellation { throw .cancelled }
            }
        }
        if let error = script.error { throw error }
        if Task.isCancelled && !script.ignoresCancellation { throw .cancelled }
        let elapsed = ContinuousClock.now - start
        return Transcript(
            text: script.text,
            segments: script.text.isEmpty ? [] : [TranscriptSegment(text: script.text, start: 0, confidence: 1)],
            engine: descriptor.id,
            language: request.language,
            audioDuration: request.audio.duration,
            processingDuration: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        )
    }

    public func unload() async {
        state.withLock {
            $0.unloadCount += 1
            $0.isPrepared = false
        }
    }
}
