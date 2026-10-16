import Domain
import Foundation

/// Behaviour every ``SpeechRecognitionEngine`` must show (see the protocol's
/// documentation). Returns human-readable violations instead of asserting so
/// it can be shared by test targets without linking a test framework into
/// the app; tests check that the result is empty.
public enum RecognitionEngineContract {
    /// Maximum time an engine may take to stop after cancellation.
    public static let cancellationDeadline: Duration = .seconds(2)

    /// Runs every check. `request` should point at a real recording the
    /// engine can read; it is never deleted.
    public static func verify(_ engine: any SpeechRecognitionEngine, request: RecognitionRequest) async -> [String] {
        var issues = checkDescriptor(engine.descriptor)
        let availability = await engine.availability()
        if availability.isReady {
            issues += await checkRecognition(engine, request: request)
        } else {
            issues += await checkRefusesWhenUnavailable(engine, availability: availability, request: request)
        }
        issues += await checkCancelledBeforeStart(engine, request: request)
        issues += await checkUnloadIsSafe(engine)
        if !FileManager.default.fileExists(atPath: request.audio.fileURL.path) {
            issues.append("engine deleted the request's audio file; the session owns it")
        }
        return issues
    }

    public static func checkDescriptor(_ descriptor: EngineDescriptor) -> [String] {
        var issues: [String] = []
        if !DiagnosticValue.isSafeIdentifier(descriptor.id.rawValue) {
            issues.append("engine id \(descriptor.id) is not a stable lowercase identifier")
        }
        if descriptor.location != .onDevice {
            issues.append("engine does not run on device")
        }
        if descriptor.supportedLanguages.isEmpty {
            issues.append("engine lists no supported language")
        }
        return issues
    }

    static func checkRefusesWhenUnavailable(
        _ engine: any SpeechRecognitionEngine,
        availability: EngineAvailability,
        request: RecognitionRequest
    ) async -> [String] {
        do {
            _ = try await engine.recognize(request) { _ in }
            return ["engine returned a transcript while \(availability.identifier)"]
        } catch {
            guard error == availability.recognitionError else {
                return ["engine threw \(error.identifier) while \(availability.identifier)"]
            }
            return []
        }
    }

    static func checkRecognition(_ engine: any SpeechRecognitionEngine, request: RecognitionRequest) async -> [String] {
        let transcript: Transcript
        do {
            transcript = try await engine.recognize(request) { _ in }
        } catch {
            // A recording without speech is a valid outcome.
            return error == .noSpeechDetected ? [] : ["ready engine failed with \(error.identifier)"]
        }
        var issues: [String] = []
        if transcript.engine != engine.descriptor.id {
            issues.append("transcript names engine \(transcript.engine), expected \(engine.descriptor.id)")
        }
        if !engine.descriptor.supports(language: transcript.language) {
            issues.append("transcript language is not one the engine supports")
        }
        if abs(transcript.audioDuration - request.audio.duration) > 0.5 {
            issues.append("transcript audio duration does not match the recording")
        }
        if transcript.processingDuration < 0 {
            issues.append("negative processing duration")
        }
        for segment in transcript.segments {
            if let confidence = segment.confidence, !(0...1).contains(confidence) {
                issues.append("segment confidence outside 0...1")
            }
            if let start = segment.start, start < 0 {
                issues.append("segment starts before the recording")
            }
            if let duration = segment.duration, duration < 0 {
                issues.append("segment has negative duration")
            }
        }
        return issues
    }

    static func checkCancelledBeforeStart(
        _ engine: any SpeechRecognitionEngine,
        request: RecognitionRequest
    ) async -> [String] {
        let start = ContinuousClock.now
        let task = Task { try await engine.recognize(request) { _ in } }
        task.cancel()
        let result = await task.result
        var issues: [String] = []
        switch result {
        case .success:
            issues.append("engine returned a transcript after cancellation")
        case .failure(let error):
            let availability = await engine.availability()
            let recognitionError = error as? RecognitionError
            if recognitionError != .cancelled && recognitionError != availability.recognitionError {
                issues.append("cancelled engine threw \(error) instead of recognition.cancelled")
            }
        }
        if ContinuousClock.now - start > cancellationDeadline {
            issues.append("engine took longer than \(cancellationDeadline) to stop after cancellation")
        }
        return issues
    }

    static func checkUnloadIsSafe(_ engine: any SpeechRecognitionEngine) async -> [String] {
        await engine.unload()
        await engine.unload()
        return []
    }
}
