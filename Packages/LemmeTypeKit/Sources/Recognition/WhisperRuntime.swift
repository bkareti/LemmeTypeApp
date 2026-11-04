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
    /// A concrete two-letter code; detection happens before inference (E9-S2).
    var language: String
    /// Transcribe, or write English (E9-S2).
    var task: RecognitionTask = .transcribe
    /// Primes the decoder with expected words (vocabulary, E4-S2).
    var prompt: String?
    /// From the performance plan (E5-S5).
    var threads: Int
    /// How whisper.cpp decodes and when it gives up on a window.
    var decoding = WhisperDecoding()
}

/// whisper.cpp's decoding settings that decide when a window is retried,
/// skipped as silence, or cut short. The defaults are what the app ships
/// (ADR 0028); `WhisperDecodingDiagnosticsTests` compares alternatives.
struct WhisperDecoding: Equatable, Sendable {
    /// Added to the temperature for each retry of a window that failed the
    /// checks below; 0 turns retries off. 0.4 retries at 0.4 and 0.8 only:
    /// whisper.cpp's 0.2 tries five times up to 1.0, which kept Telugu at the
    /// 7–8 s cap and wrote random text, and was no better for Hindi (ADR 0028).
    var temperatureIncrement: Float = 0.4
    /// A window whose last 32 tokens have less entropy than this (nats) has failed.
    var entropyThreshold: Float = 2.4
    /// A window whose tokens average a lower log probability than this has failed.
    var logProbabilityThreshold: Float = -1
    /// Above this no-speech probability (with a failing log probability) a window is skipped.
    var noSpeechThreshold: Float = 0.6
    /// Keeps the decoder from writing non-speech annotations such as "(music)".
    /// On: it stopped two of three English noise hallucinations and changed
    /// no English or Hindi score (ADR 0028).
    var suppressesNonSpeechTokens = true
    /// Candidates sampled for each retry above temperature 0; the best one is kept.
    /// whisper.cpp's greedy default; one candidate made Hindi 2 points worse (ADR 0028).
    var bestOf = 5
    /// Beam search at temperature 0 with this many beams; `nil` decodes greedily.
    var beamSize: Int?
}

/// One decoded segment and how sure whisper.cpp was of it.
struct WhisperSegment: Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var duration: TimeInterval
    /// The no-speech probability of the 30-second window the segment came from.
    var noSpeechProbability: Float = 0
    /// Text tokens, without timestamps and special tokens.
    var tokenCount = 0
    /// The mean log probability of those tokens; 0 without any.
    var averageLogProbability: Float = 0

    var transcriptSegment: TranscriptSegment {
        TranscriptSegment(text: text, start: start, duration: duration)
    }
}

/// How likely a spoken language is, as whisper.cpp scores it (E9-S2).
struct LanguageProbability: Equatable, Sendable {
    var code: String
    var probability: Float
}

/// A loaded model. Memory is released when the last reference goes away.
protocol WhisperModel: AnyObject, Sendable {
    /// The probability of each language for the first 30 seconds of `samples`.
    /// Empty for English-only models, which cannot detect.
    func detectLanguage(_ samples: [Float], threads: Int) throws(RecognitionError) -> [LanguageProbability]

    /// For each 30-second window of `samples`, the probability of the
    /// no-speech token right after start-of-transcript, as OpenAI Whisper
    /// reads it. whisper.cpp reads its own after the language and task
    /// tokens, where a multilingual model almost never predicts it.
    func noSpeechProbabilities(_ samples: [Float], threads: Int) throws(RecognitionError) -> [Float]

    /// Blocking inference over 16 kHz mono samples. Returns
    /// `RecognitionError.cancelled` soon after `shouldAbort` returns true.
    func transcribe(
        _ samples: [Float],
        _ inference: WhisperInference,
        shouldAbort: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) throws(RecognitionError) -> [WhisperSegment]
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

    func detectLanguage(_ samples: [Float], threads: Int) throws(RecognitionError) -> [LanguageProbability] {
        lock.lock()
        defer { lock.unlock() }
        guard whisper_is_multilingual(context) != 0 else { return [] }
        let threadCount = Int32(max(1, threads))
        let melStatus = samples.withUnsafeBufferPointer {
            whisper_pcm_to_mel(context, $0.baseAddress, Int32($0.count), threadCount)
        }
        guard melStatus == 0 else { throw .engineFailure(code: Int(melStatus)) }
        var probabilities = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let best = whisper_lang_auto_detect(context, 0, threadCount, &probabilities)
        guard best >= 0 else { throw .engineFailure(code: Int(best)) }
        return probabilities.indices.compactMap { index in
            whisper_lang_str(Int32(index)).map {
                LanguageProbability(code: String(cString: $0), probability: probabilities[index])
            }
        }
    }

    func noSpeechProbabilities(_ samples: [Float], threads: Int) throws(RecognitionError) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let threadCount = Int32(max(1, threads))
        let melStatus = samples.withUnsafeBufferPointer {
            whisper_pcm_to_mel(context, $0.baseAddress, Int32($0.count), threadCount)
        }
        guard melStatus == 0 else { throw .engineFailure(code: Int(melStatus)) }
        let milliseconds = samples.count * 1000 / Int(AudioCaptureFormat.speech.sampleRate)
        let vocabulary = Int(whisper_n_vocab(context))
        let noSpeech = Int(whisper_token_nosp(context))
        var probabilities: [Float] = []
        // Windows start every 30 seconds; a last one under a second is not worth an encoder pass.
        for offset in stride(from: 0, to: max(1, milliseconds - 1000), by: 30000) {
            // Encodes the window and decodes start-of-transcript alone.
            let status = whisper_lang_auto_detect(context, Int32(offset), threadCount, nil)
            guard status >= 0, let logits = whisper_get_logits(context) else {
                throw .engineFailure(code: Int(status))
            }
            let window = UnsafeBufferPointer(start: logits, count: vocabulary)
            let largest = window.max() ?? 0
            let total = window.reduce(Float(0)) { $0 + exp($1 - largest) }
            probabilities.append(exp(window[noSpeech] - largest) / total)
        }
        return probabilities
    }

    func transcribe(
        _ samples: [Float],
        _ inference: WhisperInference,
        shouldAbort: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) throws(RecognitionError) -> [WhisperSegment] {
        let prompt = inference.prompt
        lock.lock()
        defer { lock.unlock() }
        let callbacks = Callbacks(shouldAbort: shouldAbort, progress: progress)
        let userData = Unmanaged.passUnretained(callbacks).toOpaque()

        var parameters = Self.parameters(for: inference)
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

        return decodedSegments()
    }

    /// Defaults plus this call's task, threads, and decoding settings (ADR 0028).
    private static func parameters(for inference: WhisperInference) -> whisper_full_params {
        let decoding = inference.decoding
        var parameters = whisper_full_default_params(
            decoding.beamSize == nil ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH)
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = inference.task == .translateToEnglish
        parameters.no_context = true
        parameters.n_threads = Int32(max(1, inference.threads))
        parameters.temperature_inc = decoding.temperatureIncrement
        parameters.entropy_thold = decoding.entropyThreshold
        parameters.logprob_thold = decoding.logProbabilityThreshold
        parameters.no_speech_thold = decoding.noSpeechThreshold
        parameters.suppress_nst = decoding.suppressesNonSpeechTokens
        parameters.greedy.best_of = Int32(decoding.bestOf)
        if let beamSize = decoding.beamSize {
            parameters.beam_search.beam_size = Int32(beamSize)
        }
        return parameters
    }

    /// The segments of the last `whisper_full` call with their confidence. Call with `lock` held.
    private func decodedSegments() -> [WhisperSegment] {
        let endOfText = whisper_token_eot(context)
        return (0..<whisper_full_n_segments(context)).compactMap { index in
            guard let cText = whisper_full_get_segment_text(context, index) else { return nil }
            let text = String(cString: cText).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            // Timestamps are in units of 10 ms.
            let start = Double(whisper_full_get_segment_t0(context, index)) / 100
            let end = Double(whisper_full_get_segment_t1(context, index)) / 100
            // Special and timestamp tokens sort after end-of-text.
            let logProbabilities = (0..<whisper_full_n_tokens(context, index))
                .map { whisper_full_get_token_data(context, index, $0) }
                .filter { $0.id < endOfText }
                .map(\.plog)
            return WhisperSegment(
                text: text, start: max(0, start), duration: max(0, end - start),
                noSpeechProbability: whisper_full_get_segment_no_speech_prob(context, index),
                tokenCount: logProbabilities.count,
                averageLogProbability: logProbabilities.isEmpty
                    ? 0 : logProbabilities.reduce(0, +) / Float(logProbabilities.count))
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
