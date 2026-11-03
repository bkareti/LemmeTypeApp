#if DEBUG
    import Foundation

    /// One corpus run of one engine on one task and writing mode, as written to
    /// `build/evaluation/`. `scripts/evaluation-report.py` turns reports into the
    /// summary, JUnit XML, HTML dashboard, and baseline comparison.
    ///
    /// Metrics and identifiers only: no audio, no transcripts, no references.
    /// Case ids point into the committed corpus manifests.
    public struct EvaluationReport: Codable, Equatable, Sendable {
        /// 2: modes (`mode`, `style`), number-normalized words, translation and style scores.
        public static let schemaVersion = 2

        /// Which manifest the runs came from, so a comparison knows it is like for like.
        public struct Corpus: Codable, Equatable, Sendable {
            public let name: String
            /// SHA-256 of the manifest file.
            public let sha256: String
            public let runs: Int
        }

        public let schema: Int
        /// Names the report and its file: the model id, or the engine id.
        public let label: String
        public let engine: String
        /// `RecognitionTask` raw value.
        public let task: String
        /// `DictationModeID` raw value.
        public let mode: String
        /// `WritingMode` raw value of the mode.
        public let writingMode: String
        /// `StyleOptions.identifier` the mode runs (`none` for no rewrite).
        public let style: String
        public let date: Date
        public let operatingSystem: String
        public let hardwareModel: String
        public let physicalMemoryGB: Int
        public let warmUpSeconds: Double
        public let peakMemoryIncreaseMB: Double
        public let corpora: [Corpus]
        /// Items that cannot be scored for this task, by reason (for example
        /// `no-english-reference` when translating).
        public let skipped: [String: Int]
        public let runs: [EvaluationRun]

        public var fileName: String { "\(label)-\(task)-\(mode).json" }

        public func write(to directory: URL) throws -> URL {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let url = directory.appendingPathComponent(fileName)
            try encoder.encode(self).write(to: url)
            return url
        }

        public static func load(from url: URL) throws -> EvaluationReport {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(EvaluationReport.self, from: Data(contentsOf: url))
        }
    }

    /// One item's result with what the corpus says about it.
    public struct EvaluationRun: Codable, Equatable, Sendable {
        public let id: String
        public let baseID: String
        public let variantID: String?
        public let source: String?
        public let tags: [String]
        /// `CorpusManifest.Review` raw value.
        public let review: String
        public let result: EvaluationResult
    }
#endif
