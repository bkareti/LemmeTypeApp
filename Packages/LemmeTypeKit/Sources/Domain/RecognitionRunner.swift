import Synchronization

/// Runs an engine with the cancellation guarantees every caller relies on,
/// whatever the engine does:
/// - a request for an engine that is not ready fails without calling it;
/// - once the calling task is cancelled, no update is forwarded and the result
///   is ``RecognitionError/cancelled``, even if the engine returns a transcript.
public struct RecognitionRunner: Sendable {
    public init() {}

    public func run(
        _ engine: any SpeechRecognitionEngine,
        _ request: RecognitionRequest,
        updates: @escaping @Sendable (RecognitionUpdate) -> Void = { _ in }
    ) async throws(RecognitionError) -> Transcript {
        guard engine.descriptor.supports(language: request.language) else {
            throw .unsupported(.language)
        }
        let availability = await engine.availability()
        if let error = availability.recognitionError {
            throw error
        }
        try Self.checkCancellation()
        let gate = UpdateGate(forward: updates)
        let transcript: Transcript
        do {
            transcript = try await withTaskCancellationHandler {
                try await engine.recognize(request) { gate.send($0) }
            } onCancel: {
                gate.close()
            }
        } catch {
            gate.close()
            if Task.isCancelled { throw .cancelled }
            // `withTaskCancellationHandler` erases the engine's typed error.
            throw error as? RecognitionError ?? .engineFailure(code: -1)
        }
        gate.close()
        try Self.checkCancellation()
        return transcript
    }

    private static func checkCancellation() throws(RecognitionError) {
        if Task.isCancelled { throw .cancelled }
    }
}

/// Forwards updates until closed; afterwards drops them.
private final class UpdateGate: Sendable {
    private let isOpen = Mutex(true)
    private let forward: @Sendable (RecognitionUpdate) -> Void

    init(forward: @escaping @Sendable (RecognitionUpdate) -> Void) {
        self.forward = forward
    }

    func send(_ update: RecognitionUpdate) {
        // Forward while holding the lock so `close()` cannot complete while
        // an update is still being delivered.
        isOpen.withLock { open in
            if open { forward(update) }
        }
    }

    func close() {
        isOpen.withLock { $0 = false }
    }
}
