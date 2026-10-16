import Domain
import Foundation
import Speech
import Support

/// Text and segments from one Apple Speech recognition.
struct AppleSpeechResult: Sendable, Equatable {
    let text: String
    let segments: [TranscriptSegment]
}

/// The Speech-framework edge, replaceable in tests.
protocol AppleSpeechBackend: Sendable {
    func hasRecognizer(language: String) -> Bool
    func supportsOnDeviceRecognition(language: String) -> Bool
    func recognize(
        fileURL: URL,
        language: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws(RecognitionError) -> AppleSpeechResult
}

/// `SFSpeechRecognizer` with on-device recognition required.
struct SFSpeechBackend: AppleSpeechBackend {
    func hasRecognizer(language: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language)) != nil
    }

    func supportsOnDeviceRecognition(language: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language))?.supportsOnDeviceRecognition ?? false
    }

    func recognize(
        fileURL: URL,
        language: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws(RecognitionError) -> AppleSpeechResult {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            throw .unsupported(.language)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw .unsupported(.onDeviceRecognitionUnavailable)
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        // Never send audio to Apple's servers, even if on-device recognition
        // becomes unavailable mid-request: the task fails instead.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let session = SpeechTaskSession(onPartial: onPartial)
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    session.begin(continuation)
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error {
                            let nsError = error as NSError
                            session.fail(AppleSpeechErrorMapping.map(domain: nsError.domain, code: nsError.code))
                        } else if let result {
                            session.receive(Self.convert(result.bestTranscription), isFinal: result.isFinal)
                        }
                    }
                    session.attach(task: task, recognizer: recognizer)
                }
            } onCancel: {
                session.cancel()
            }
        } catch let error as RecognitionError {
            throw error
        } catch {
            throw .engineFailure(code: -1)
        }
    }

    private static func convert(_ transcription: SFTranscription) -> AppleSpeechResult {
        AppleSpeechResult(
            text: transcription.formattedString,
            segments: transcription.segments.map {
                TranscriptSegment(
                    text: $0.substring,
                    start: $0.timestamp,
                    duration: $0.duration,
                    confidence: Double(min(max($0.confidence, 0), 1))
                )
            }
        )
    }
}

/// Bridges one callback-based recognition task to a single continuation
/// resume. `@unchecked Sendable`: every stored property is read and written
/// only while holding `lock`, and the continuation is resumed exactly once,
/// outside the lock.
private final class SpeechTaskSession: @unchecked Sendable {
    private let lock = NSLock()
    private let onPartial: @Sendable (String) -> Void
    private var continuation: CheckedContinuation<AppleSpeechResult, any Error>?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var isCancelled = false

    init(onPartial: @escaping @Sendable (String) -> Void) {
        self.onPartial = onPartial
    }

    func begin(_ continuation: CheckedContinuation<AppleSpeechResult, any Error>) {
        lock.lock()
        let cancelled = isCancelled
        if !cancelled { self.continuation = continuation }
        lock.unlock()
        if cancelled { continuation.resume(throwing: RecognitionError.cancelled) }
    }

    func attach(task: SFSpeechRecognitionTask, recognizer: SFSpeechRecognizer) {
        lock.lock()
        let cancelled = isCancelled
        if !cancelled {
            self.task = task
            self.recognizer = recognizer
        }
        lock.unlock()
        if cancelled { task.cancel() }
    }

    func receive(_ result: AppleSpeechResult, isFinal: Bool) {
        if isFinal {
            finish(.success(result))
        } else {
            lock.lock()
            let active = continuation != nil
            lock.unlock()
            if active { onPartial(result.text) }
        }
    }

    func fail(_ error: RecognitionError) {
        finish(.failure(error))
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(.failure(.cancelled))
    }

    private func finish(_ result: Result<AppleSpeechResult, RecognitionError>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        task = nil
        recognizer = nil
        lock.unlock()
        continuation?.resume(with: result.mapError { $0 as any Error })
    }
}

/// Maps Speech-framework errors to stable LemmeType errors using only the
/// error domain and numeric code (framework messages are never kept).
enum AppleSpeechErrorMapping {
    static func map(domain: String, code: Int) -> RecognitionError {
        switch (domain, code) {
        case ("kAFAssistantErrorDomain", 1110), ("kAFAssistantErrorDomain", 203):
            .noSpeechDetected
        case ("kAFAssistantErrorDomain", 216), ("kAFAssistantErrorDomain", 301),
            ("kLSRErrorDomain", 301):
            .cancelled
        case ("kAFAssistantErrorDomain", 1700), ("kAFAssistantErrorDomain", 1101):
            .unsupported(.onDeviceRecognitionUnavailable)
        case ("SFSpeechErrorDomain", 2):
            .audioUnreadable
        default:
            .engineFailure(code: code)
        }
    }
}
