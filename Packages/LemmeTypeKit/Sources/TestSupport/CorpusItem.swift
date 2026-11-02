#if DEBUG
    import Domain
    import Foundation

    /// One run a ``CorpusManifest`` asks for: a recording, a generated clip in
    /// one language, or a variant of a recording. Its audio is made only when
    /// it runs and deleted straight after, so a large corpus with many variants
    /// never fills the disk.
    public struct CorpusItem: Sendable {
        private enum Content: Sendable {
            case recording(URL)
            case generated(CorpusManifest.GeneratedCase)
            case variant(URL, CorpusVariant)
        }

        /// `<case>`, `<case>~<variant>`, or `<generated>@<language>`; unique in the manifest.
        public let id: String
        /// The recording or generated case it comes from.
        public let baseID: String
        public let variantID: String?
        /// Dataset id, or `nil` for generated audio.
        public let source: String?
        public let language: String
        public let category: String
        public let tags: [String]
        public let review: CorpusManifest.Review
        public let reference: String
        public let englishReference: String?
        private let content: Content

        init(recording: CorpusManifest.Case, url: URL, variant: CorpusVariant? = nil) {
            id = variant.map { "\(recording.id)~\($0.id)" } ?? recording.id
            baseID = recording.id
            variantID = variant?.id
            source = recording.source
            language = recording.language
            category = recording.category
            tags = recording.tags + (variant.map { ["variant:\($0.transform.rawValue)"] } ?? [])
            review = recording.review
            reference = variant?.reference(for: recording.reference) ?? recording.reference
            englishReference = recording.englishReference.map { variant?.reference(for: $0) ?? $0 }
            content = variant.map { .variant(url, $0) } ?? .recording(url)
        }

        init(generated: CorpusManifest.GeneratedCase, language: String) {
            id = "\(generated.id)@\(language)"
            baseID = generated.id
            variantID = nil
            source = nil
            self.language = language
            category = generated.category
            tags = ["generated:\(generated.kind.rawValue)"]
            review = .byConstruction
            reference = ""
            englishReference = ""
            content = .generated(generated)
        }

        /// Makes the audio (in `workDirectory` when it has to be generated or
        /// changed), runs it, and deletes what it made.
        public func run(
            with runner: EvaluationRunner, workDirectory: URL, task: RecognitionTask = .transcribe,
            writingMode: WritingMode = .clean
        ) async throws -> EvaluationResult {
            let audioURL: URL
            var made: URL?
            switch content {
            case .recording(let url):
                audioURL = url
            case .generated(let generated):
                audioURL = try write(generated.clip, in: workDirectory)
                made = audioURL
            case .variant(let url, let variant):
                audioURL = try write(variant.apply(to: AudioClip.load(from: url)), in: workDirectory)
                made = audioURL
            }
            defer { if let made { try? FileManager.default.removeItem(at: made) } }
            return try await runner.run(
                EvaluationCase(
                    id: id, audioURL: audioURL, language: language, reference: reference,
                    englishReference: englishReference, category: category),
                task: task, writingMode: writingMode)
        }

        private func write(_ clip: AudioClip, in directory: URL) throws -> URL {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).caf")
            try clip.write(to: url)
            return url
        }
    }
#endif
