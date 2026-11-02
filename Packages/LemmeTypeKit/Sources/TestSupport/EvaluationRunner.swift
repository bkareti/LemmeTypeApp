#if DEBUG
    import Domain
    import Foundation
    import Synchronization

    /// One corpus item: an audio file and its human references.
    public struct EvaluationCase: Sendable {
        public let id: String
        public let audioURL: URL
        /// BCP 47 language that is spoken (`en-US`, `hi`, `te`, …).
        public let language: String
        /// Human reference in the spoken language. Empty means the audio has no speech.
        public let reference: String
        /// Human English reference, needed to score a translation.
        public let englishReference: String?
        public let category: String

        public init(
            id: String, audioURL: URL, language: String, reference: String, englishReference: String? = nil,
            category: String
        ) {
            self.id = id
            self.audioURL = audioURL
            self.language = language
            self.reference = reference
            self.englishReference = englishReference
            self.category = category
        }
    }

    /// What one case produced. Metrics and stable identifiers only — no audio
    /// and no text — so results can be written to reports.
    public struct EvaluationResult: Codable, Equatable, Sendable {
        public let id: String
        public let category: String
        public let language: String
        /// `RecognitionTask` raw value.
        public let task: String
        /// `WritingMode` raw value.
        public let writingMode: String
        /// `delivered`, `review`, `cancelled`, or the `DictationIssue` identifier.
        public let outcome: String
        /// Text came out that the user could insert or copy (a review counts).
        public let producedText: Bool
        public let audioSeconds: Double
        /// Recognition only.
        public let inferenceSeconds: Double
        /// Processing start to text ready.
        public let stopToDeliverySeconds: Double
        /// Against the reference for the task; no text counts as an empty hypothesis.
        public let score: TranscriptScore
    }

    public enum EvaluationError: Error, Equatable {
        /// The production pipeline only ever sees 16 kHz speech; convert the corpus first.
        case unsupportedSampleRate(caseID: String)
        /// A translation can only be scored against a human English reference.
        case missingEnglishReference(caseID: String)
    }

    /// Runs corpus audio through the production ``TranscriptionPipeline`` —
    /// engine selection, recognition, writing mode, delivery — with only the
    /// delivery target replaced, on macOS and iOS alike. Each case's audio is
    /// copied into `workDirectory` in the speech capture format (the pipeline
    /// deletes it as it would a recording), so corpus files are never touched.
    /// Text is scored in memory and dropped; only ``EvaluationResult``s leave.
    ///
    /// An actor so cases run one at a time and timings do not interfere.
    public actor EvaluationRunner {
        private let engine: RecognitionEngineID
        private let delivery = CapturingDelivery()
        private let pipeline: TranscriptionPipeline
        private let workDirectory: URL

        /// `reviewsEveryResult` is the iPhone and iPad flow (ADR 0027): every result ends in a review.
        public init(
            engine: any SpeechRecognitionEngine, workDirectory: URL, hardware: HardwareProfile = .current,
            reviewsEveryResult: Bool = false
        ) {
            self.engine = engine.descriptor.id
            self.workDirectory = workDirectory
            pipeline = TranscriptionPipeline(
                engines: [engine], write: TextCleaner.write, delivery: delivery, hardware: hardware,
                reviewsEveryResult: reviewsEveryResult)
        }

        public func run(
            _ testCase: EvaluationCase, task: RecognitionTask = .transcribe, writingMode: WritingMode = .clean
        ) async throws -> EvaluationResult {
            let reference: String
            switch task {
            case .transcribe:
                reference = testCase.reference
            case .translateToEnglish:
                guard let english = testCase.englishReference else {
                    throw EvaluationError.missingEnglishReference(caseID: testCase.id)
                }
                reference = english
            }
            let clip = try AudioClip.load(from: testCase.audioURL)
            guard clip.sampleRate == AudioCaptureFormat.speech.sampleRate else {
                throw EvaluationError.unsupportedSampleRate(caseID: testCase.id)
            }
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let url = workDirectory.appendingPathComponent("\(UUID().uuidString).caf")
            try clip.write(to: url)
            let session = DictationSession(
                audio: RecordedAudio(fileURL: url, duration: clip.duration, format: .speech), target: nil,
                mode: writingMode, language: testCase.language,
                speechOutput: task == .translateToEnglish ? .english : .original,
                enginePreference: EnginePreference(selected: engine))
            defer { session.discardAudio() }

            _ = delivery.take()
            let phases = Mutex<[ProcessingPhase: ContinuousClock.Instant]>([:])
            let start = ContinuousClock.now
            let outcome = await pipeline.process(session) { update in
                if case .phase(let phase) = update { phases.withLock { $0[phase] = ContinuousClock.now } }
            }
            let end = ContinuousClock.now
            let marks = phases.withLock { $0 }
            let inference =
                marks[.recognizing].map { recognizing in ((marks[.writing] ?? end) - recognizing).benchmarkSeconds }
                ?? 0
            let (name, text) = Self.describe(outcome, delivered: delivery.take())
            return EvaluationResult(
                id: testCase.id, category: testCase.category, language: testCase.language, task: task.rawValue,
                writingMode: writingMode.rawValue, outcome: name, producedText: text != nil,
                audioSeconds: clip.duration, inferenceSeconds: inference,
                stopToDeliverySeconds: (end - start).benchmarkSeconds,
                score: TranscriptScore.score(reference: reference, hypothesis: text ?? ""))
        }

        /// The outcome's name and the text the user would get from it. A result
        /// waiting for review is scored as if the user inserted it.
        static func describe(_ outcome: DictationOutcome, delivered: String?) -> (String, String?) {
            switch outcome {
            case .delivered:
                ("delivered", delivered)
            case .needsAttention(let issue, _, _, let transcript):
                switch issue {
                case .reviewTranslation, .reviewText: (issue.identifier, transcript)
                default: (issue.identifier, nil)
                }
            case .review(let review, _):
                ("review", review.text)
            case .cancelled:
                ("cancelled", nil)
            }
        }
    }

    /// A delivery target that keeps the last text in memory until it is taken.
    final class CapturingDelivery: TextDelivering {
        private let text = Mutex<String?>(nil)

        func take() -> String? {
            text.withLock { value in
                defer { value = nil }; return value
            }
        }

        func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
            self.text.withLock { $0 = text }
            return .delivered(.accessibility)
        }
    }

    extension Duration {
        var benchmarkSeconds: Double {
            Double(components.seconds) + Double(components.attoseconds) / 1e18
        }
    }
#endif
