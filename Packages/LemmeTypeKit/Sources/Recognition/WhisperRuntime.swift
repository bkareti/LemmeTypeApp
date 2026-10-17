import Domain
import Foundation
import Synchronization
import whisper

/// Loads Whisper models. The whisper.cpp edge, replaceable in tests.
protocol WhisperRuntime: Sendable {
    func loadModel(at url: URL, usesGPU: Bool) throws(RecognitionError) -> any WhisperModel
}

/// Per-call inference settings.
struct WhisperInference: Equatable, Sendable {
    var language: String
    /// Primes the decoder with expected words (vocabulary, E4-S2).
    var prompt: String?
    /// From the performance plan (E5-S5).
    var threads: Int
}

/// A loaded model. Memory is released when the last reference goes away.
protocol WhisperModel: AnyObject, Sendable {
    /// Blocking inference over 16 kHz mono samples. Returns
    /// `RecognitionError.cancelled` soon after `shouldAbort` returns true.
    func transcribe(
        _ samples: [Float],
        _ inference: WhisperInference,
        shouldAbort: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) throws(RecognitionError) -> [TranscriptSegment]
}

/// Thread-safe cancellation flag shared with C callbacks.
final class AbortFlag: Sendable {
    private let value = Atomic<Bool>(false)

    var isSet: Bool { value.load(ordering: .relaxed) }

    func set() {
        value.store(true, ordering: .relaxed)
    }
}

struct WhisperCppRuntime: WhisperRuntime {
    func loadModel(at url: URL, usesGPU: Bool) throws(RecognitionError) -> any WhisperModel {
        // Silence whisper.cpp's own logging (it would go to stderr).
        whisper_log_set({ _, _, _ in }, nil)
        var parameters = whisper_context_default_params()
        parameters.use_gpu = usesGPU
        guard let context = url.path.withCString({ whisper_init_from_file_with_params($0, parameters) }) else {
            throw .modelLoadFailed
        }
        return WhisperCppModel(context: context)
    }
}

/// Owns one `whisper_context`. `@unchecked Sendable`: the context is used only
/// while holding `lock` (whisper.cpp contexts are not thread-safe) and is freed
/// once, in `deinit`.
final class WhisperCppModel: WhisperModel, @unchecked Sendable {
    private let lock = NSLock()
    private let context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(
        _ samples: [Float],
        _ inference: WhisperInference,
        shouldAbort: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) throws(RecognitionError) -> [TranscriptSegment] {
        let prompt = inference.prompt
        lock.lock()
        defer { lock.unlock() }
        let callbacks = Callbacks(shouldAbort: shouldAbort, progress: progress)
        let userData = Unmanaged.passUnretained(callbacks).toOpaque()

        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.no_context = true
        parameters.n_threads = Int32(max(1, inference.threads))
        parameters.abort_callback = { data in
            guard let data else { return false }
            return Unmanaged<Callbacks>.fromOpaque(data).takeUnretainedValue().shouldAbort()
        }
        parameters.abort_callback_user_data = userData
        parameters.progress_callback = { _, _, percent, data in
            guard let data else { return }
            Unmanaged<Callbacks>.fromOpaque(data).takeUnretainedValue().progress(Double(percent) / 100)
        }
        parameters.progress_callback_user_data = userData

        // C strings live only for the call; whisper.cpp copies what it keeps.
        let status = withExtendedLifetime(callbacks) {
            inference.language.withCString { languageCode in
                (prompt ?? "").withCString { promptText in
                    parameters.language = languageCode
                    parameters.initial_prompt = prompt == nil ? nil : promptText
                    return samples.withUnsafeBufferPointer { buffer in
                        whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
                    }
                }
            }
        }
        if shouldAbort() { throw .cancelled }
        guard status == 0 else { throw .engineFailure(code: Int(status)) }

        return (0..<whisper_full_n_segments(context)).compactMap { index in
            guard let cText = whisper_full_get_segment_text(context, index) else { return nil }
            let text = String(cString: cText).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            // Timestamps are in units of 10 ms.
            let start = Double(whisper_full_get_segment_t0(context, index)) / 100
            let end = Double(whisper_full_get_segment_t1(context, index)) / 100
            return TranscriptSegment(text: text, start: max(0, start), duration: max(0, end - start))
        }
    }

    private final class Callbacks: Sendable {
        let shouldAbort: @Sendable () -> Bool
        let progress: @Sendable (Double) -> Void

        init(shouldAbort: @escaping @Sendable () -> Bool, progress: @escaping @Sendable (Double) -> Void) {
            self.shouldAbort = shouldAbort
            self.progress = progress
        }
    }
}
