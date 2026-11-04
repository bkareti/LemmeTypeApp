// macOS only, like CorpusEvaluationTests: it needs the fetched corpus and an installed model.
#if os(macOS)
    import Domain
    import Foundation
    import Synchronization
    import TestSupport
    import Testing

    @testable import Recognition

    /// Opt-in: runs corpus cases through the real pipeline with one or more
    /// ``WhisperDecoding`` settings and writes what whisper.cpp did per run (token
    /// counts, no-speech probability, log probability, the script of the output,
    /// time) next to the run's scores. Metrics only, never text
    /// (docs/testing/evaluation-harness.md, "Decoding diagnostics").
    ///
    /// - `LEMMETYPE_WHISPER_DIAGNOSTICS=1` turns it on; `LEMMETYPE_CORPUS_ROOT` as for the evaluation.
    /// - `LEMMETYPE_EVALUATION_MODEL` (default `whisper-small`), `LEMMETYPE_EVALUATION_LANGUAGES`.
    /// - `LEMMETYPE_DIAGNOSTICS_DECODING`: comma-separated names from ``decodings`` (default `shipped`).
    /// - `LEMMETYPE_DIAGNOSTICS_MANIFESTS`: such as `edge-cases.json` (default both).
    /// - `LEMMETYPE_DIAGNOSTICS_EVERY`: run every n-th item only (default 1).
    /// - `LEMMETYPE_DIAGNOSTICS_MATCH`: only ids containing this text, such as `long-dictation`, or `original`.
    /// - A setting name ending in `+nogate` (such as `whisper.cpp+nogate`) skips the no-speech check.
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_WHISPER_DIAGNOSTICS"] == "1"), .serialized)
    struct WhisperDecodingDiagnosticsTests {
        static let environment = ProcessInfo.processInfo.environment

        /// Settings to compare. `whisper.cpp` is the library's own defaults.
        static let decodings: [String: WhisperDecoding] = [
            "whisper.cpp": WhisperDecoding.libraryDefaults,
            "shipped": WhisperDecoding(),
            "shipped-inc2": WhisperDecoding().with { $0.temperatureIncrement = 0.2 },
            "shipped-no-nst": WhisperDecoding().with { $0.suppressesNonSpeechTokens = false },
            "shipped-inc2-no-nst": WhisperDecoding().with {
                $0.temperatureIncrement = 0.2
                $0.suppressesNonSpeechTokens = false
            },
            "no-fallback": WhisperDecoding.libraryDefaults.with { $0.temperatureIncrement = 0 },
            "suppress-nst": WhisperDecoding.libraryDefaults.with { $0.suppressesNonSpeechTokens = true },
            "no-fallback-nst": WhisperDecoding.libraryDefaults.with {
                $0.temperatureIncrement = 0
                $0.suppressesNonSpeechTokens = true
            },
            "nst-best5": WhisperDecoding.libraryDefaults.with {
                $0.suppressesNonSpeechTokens = true
                $0.bestOf = 5
            },
            "nst-inc4": WhisperDecoding.libraryDefaults.with {
                $0.suppressesNonSpeechTokens = true
                $0.temperatureIncrement = 0.4
            },
            "nst-beam5": WhisperDecoding.libraryDefaults.with {
                $0.suppressesNonSpeechTokens = true
                $0.bestOf = 5
                $0.beamSize = 5
            },
        ]

        @Test func decodingOnTheCorpus() async throws {
            let root = URL(fileURLWithPath: try #require(Self.environment["LEMMETYPE_CORPUS_ROOT"]), isDirectory: true)
            let modelID = Self.environment["LEMMETYPE_EVALUATION_MODEL"] ?? ModelAssetID.whisperSmall.rawValue
            let asset = try #require(ModelCatalog.whisperModels.first { $0.id.rawValue == modelID })
            let names = (Self.environment["LEMMETYPE_DIAGNOSTICS_DECODING"] ?? "shipped").split(separator: ",").map(
                String.init)
            let items = try Self.chosenItems(root: root)
            try #require(!items.isEmpty, "No corpus items chosen")

            let output = RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent("build/evaluation/diagnostics")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for name in names {
                let base = name.replacingOccurrences(of: "+nogate", with: "")
                let decoding = try #require(Self.decodings[base], "Unknown decoding \(name)")
                let runtime = DiagnosticWhisperRuntime(decoding: decoding, gate: !name.hasSuffix("+nogate"))
                let engine = WhisperEngine(
                    assets: FixedModelLocation(url: RecognitionBenchmarkTests.modelURL(for: asset)), hardware: .current,
                    runtime: runtime, settings: { WhisperRunSettings(choice: .specific(asset.id)) })
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LemmeTypeTests-Diagnostics-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: work) }
                try await engine.prepare()
                let runner = EvaluationRunner(
                    engine: engine, workDirectory: work.appendingPathComponent("sessions", isDirectory: true))
                var lines: [String] = []
                for item in items {
                    runtime.reset()
                    let result = try await item.run(with: runner, workDirectory: work)
                    let text = runtime.lastText
                    let row = DiagnosticRow(
                        id: item.id, decoding: name, language: SpokenLanguages.code(of: item.language),
                        category: item.category, result: result, decode: runtime.lastDecode,
                        decodedWords: WordErrorRate.alignment(reference: item.reference, hypothesis: text),
                        spellingFoldedWords: WordErrorRate.alignment(
                            reference: SpellingVariants.fold(item.reference), hypothesis: SpellingVariants.fold(text)),
                        spellingFoldedCharacters: CharacterErrorRate.alignment(
                            reference: SpellingVariants.fold(item.reference), hypothesis: SpellingVariants.fold(text)))
                    lines.append(String(bytes: try JSONEncoder.sorted.encode(row), encoding: .utf8) ?? "")
                }
                await engine.unload()
                let file = output.appendingPathComponent("\(asset.id.rawValue)-\(name).jsonl")
                try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    extension WhisperDecodingDiagnosticsTests {
        /// The corpus items the `LEMMETYPE_EVALUATION_LANGUAGES` and `LEMMETYPE_DIAGNOSTICS_*` variables choose.
        /// `LEMMETYPE_DIAGNOSTICS_MATCH=original` keeps recordings without a variant.
        static func chosenItems(root: URL) throws -> [CorpusItem] {
            let languages = EvaluationOptions.languages(environment["LEMMETYPE_EVALUATION_LANGUAGES"])
            let every = max(1, Int(environment["LEMMETYPE_DIAGNOSTICS_EVERY"] ?? "") ?? 1)
            let match = environment["LEMMETYPE_DIAGNOSTICS_MATCH"].flatMap { $0.isEmpty ? nil : $0 }
            let manifests = (environment["LEMMETYPE_DIAGNOSTICS_MANIFESTS"] ?? "fleurs.json,edge-cases.json")
                .split(separator: ",").map(String.init)
            let corpus = RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent("docs/testing/corpus")
            var items: [CorpusItem] = []
            for manifest in manifests {
                let all = try CorpusManifest.load(from: corpus.appendingPathComponent(manifest)).items(root: root)
                items += all.filter { item in
                    (languages?.contains(SpokenLanguages.code(of: item.language)) ?? true)
                        && (match.map { $0 == "original" ? item.variantID == nil : item.id.contains($0) } ?? true)
                }
            }
            return items.enumerated().filter { $0.offset % every == 0 }.map(\.element)
        }

        /// The English benchmark (synthesized speech, docs/testing/benchmark-corpus.json) with the same
        /// numbers per recognition, to check a decision against English speech.
        /// `LEMMETYPE_DIAGNOSTICS_ENGLISH=1` with `LEMMETYPE_WHISPER_DIAGNOSTICS=1`.
        @Test(.enabled(if: environment["LEMMETYPE_DIAGNOSTICS_ENGLISH"] == "1"))
        func decodingOnTheEnglishBenchmark() async throws {
            let modelID = Self.environment["LEMMETYPE_EVALUATION_MODEL"] ?? ModelAssetID.whisperSmallEnglish.rawValue
            let asset = try #require(ModelCatalog.whisperModels.first { $0.id.rawValue == modelID })
            let names = (Self.environment["LEMMETYPE_DIAGNOSTICS_DECODING"] ?? "shipped").split(separator: ",").map(
                String.init)
            let corpus = try BenchmarkCorpus.load(
                from: RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent(
                    "docs/testing/benchmark-corpus.json"))
            let output = RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent("build/evaluation/diagnostics")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for name in names {
                let runtime = DiagnosticWhisperRuntime(decoding: try #require(Self.decodings[name]))
                let engine = WhisperEngine(
                    assets: FixedModelLocation(url: RecognitionBenchmarkTests.modelURL(for: asset)), hardware: .current,
                    runtime: runtime, settings: { WhisperRunSettings(choice: .specific(asset.id)) })
                let report = try await DictationBenchmark.run(
                    engine: engine, corpus: corpus,
                    workDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-Diagnostics-\(UUID().uuidString)", isDirectory: true))
                var lines = try runtime.allDecodes.map {
                    String(bytes: try JSONEncoder.sorted.encode($0), encoding: .utf8) ?? ""
                }
                lines.append(
                    "{\"summary\":true,\"wordErrorRate\":\(report.wordErrorRate),\"noisyWordErrorRate\":\(report.noisyWordErrorRate),\"failedSessions\":\(report.failedSessions),\"sessions\":\(report.sessions)}"
                )
                try (lines.joined(separator: "\n") + "\n").write(
                    to: output.appendingPathComponent("english-\(asset.id.rawValue)-\(name).jsonl"), atomically: true,
                    encoding: .utf8)
            }
        }
    }

    extension WhisperDecoding {
        /// whisper.cpp v1.9.2's `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)` (greedy `best_of` 5).
        static let libraryDefaults = WhisperDecoding(
            temperatureIncrement: 0.2, entropyThreshold: 2.4, logProbabilityThreshold: -1, noSpeechThreshold: 0.6,
            suppressesNonSpeechTokens: false, bestOf: 5)

        func with(_ change: (inout WhisperDecoding) -> Void) -> WhisperDecoding {
            var copy = self
            change(&copy)
            return copy
        }
    }

    /// What one recognition decoded, as numbers.
    struct DecodeStatistics: Codable, Sendable {
        var seconds: Double
        var segments: Int
        var tokens: Int
        var maximumSegmentTokens: Int
        var minimumNoSpeechProbability: Float
        var maximumNoSpeechProbability: Float
        var lowestAverageLogProbability: Float
        var averageLogProbability: Float
        /// Share of letters in the expected script, in Latin, and in any other script.
        var expectedScript: Double
        var latinScript: Double
        var otherScript: Double
        /// Detection's probability for the requested language over the first 30 seconds.
        var requestedLanguageProbability: Float
        var detectedLanguage: String
        /// The most copies in a row of one phrase (``RepetitionLoop``), and its length in words.
        var repeatCopies: Int
        var repeatPhraseWords: Int
        /// Where the last segment ends, and the longest stretch between two segments, in seconds.
        var lastSegmentEnd: Double
        var longestGap: Double

        /// The start-of-transcript no-speech probability (``WhisperModel/noSpeechProbabilities``), per window.
        var windowNoSpeech: [Float]
        var noSpeechSeconds: Double

        init(
            segments: [WhisperSegment], language: String, seconds: Double, detection: [LanguageProbability],
            windowNoSpeech: [Float], noSpeechSeconds: Double
        ) {
            self.windowNoSpeech = windowNoSpeech
            self.noSpeechSeconds = noSpeechSeconds
            self.seconds = seconds
            self.segments = segments.count
            tokens = segments.reduce(0) { $0 + $1.tokenCount }
            maximumSegmentTokens = segments.map(\.tokenCount).max() ?? 0
            minimumNoSpeechProbability = segments.map(\.noSpeechProbability).min() ?? 0
            maximumNoSpeechProbability = segments.map(\.noSpeechProbability).max() ?? 0
            lowestAverageLogProbability = segments.map(\.averageLogProbability).min() ?? 0
            averageLogProbability =
                tokens == 0
                ? 0
                : segments.reduce(0) { $0 + $1.averageLogProbability * Float($1.tokenCount) } / Float(tokens)
            let letters = segments.flatMap { $0.text.unicodeScalars }.filter(\.properties.isAlphabetic)
            let expected = letters.filter { Self.isExpected($0, language: language) }.count
            let latin = letters.filter { $0.isASCII }.count
            let total = Double(max(1, letters.count))
            expectedScript = Double(expected) / total
            latinScript = language == "en" ? 0 : Double(latin) / total
            otherScript = letters.isEmpty ? 0 : 1 - expectedScript - latinScript
            requestedLanguageProbability = detection.first { $0.code == language }?.probability ?? 0
            detectedLanguage = detection.max { $0.probability < $1.probability }?.code ?? ""
            let run = RepetitionLoop.longestRun(in: segments.map(\.text).joined(separator: " "))
            repeatCopies = run.copies
            repeatPhraseWords = run.phraseLength
            lastSegmentEnd = segments.map { $0.start + $0.duration }.max() ?? 0
            longestGap = zip(segments, segments.dropFirst()).map { $1.start - ($0.start + $0.duration) }.max() ?? 0
        }

        static func isExpected(_ scalar: Unicode.Scalar, language: String) -> Bool {
            switch language {
            case "hi": (0x0900...0x097F).contains(scalar.value)
            case "te": (0x0C00...0x0C7F).contains(scalar.value)
            case "kn": (0x0C80...0x0CFF).contains(scalar.value)
            case "ta": (0x0B80...0x0BFF).contains(scalar.value)
            default: scalar.isASCII
            }
        }
    }

    struct DiagnosticRow: Encodable {
        let id: String
        let decoding: String
        let language: String
        let category: String
        let result: EvaluationResult
        let decode: DecodeStatistics?
        /// Words of the decoded text (before the pipeline), as scored today.
        let decodedWords: EditAlignment
        /// The same after ``SpellingVariants``, to size that scoring artifact.
        let spellingFoldedWords: EditAlignment
        let spellingFoldedCharacters: EditAlignment
    }

    /// Hindi spellings that are both in use: with or without a nukta (ज़/ज),
    /// and chandrabindu written as anusvara (हूँ/हूं).
    enum SpellingVariants {
        static func fold(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars where scalar != "\u{093C}" {
                scalars.append(scalar == "\u{0901}" ? "\u{0902}" : scalar)
            }
            return String(scalars)
        }
    }

    /// Wraps the real runtime, decodes with the chosen settings, and keeps the
    /// numbers of the last recognition.
    final class DiagnosticWhisperRuntime: WhisperRuntime {
        let decoding: WhisperDecoding
        /// `false` reports no windows, so the engine's no-speech check never touches the model.
        let gate: Bool
        private let last = Mutex<DecodeStatistics?>(nil)
        private let all = Mutex<[DecodeStatistics]>([])
        /// The decoded text of the last recognition, kept in memory only to score it.
        private let text = Mutex("")

        init(decoding: WhisperDecoding, gate: Bool = true) {
            self.decoding = decoding
            self.gate = gate
        }

        var lastDecode: DecodeStatistics? { last.withLock { $0 } }
        var lastText: String { text.withLock { $0 } }
        /// Every recognition since the runtime was made.
        var allDecodes: [DecodeStatistics] { all.withLock { $0 } }

        func reset() {
            last.withLock { $0 = nil }
            text.withLock { $0 = "" }
        }

        func loadModel(at url: URL, usesGPU: Bool) throws(RecognitionError) -> any WhisperModel {
            Model(inner: try WhisperCppRuntime().loadModel(at: url, usesGPU: usesGPU), runtime: self)
        }

        fileprivate func record(_ statistics: DecodeStatistics, text: String) {
            last.withLock { $0 = statistics }
            all.withLock { $0.append(statistics) }
            self.text.withLock { $0 = text }
        }

        final class Model: WhisperModel {
            let inner: any WhisperModel
            let runtime: DiagnosticWhisperRuntime

            init(inner: any WhisperModel, runtime: DiagnosticWhisperRuntime) {
                self.inner = inner
                self.runtime = runtime
            }

            func detectLanguage(_ samples: [Float], threads: Int) throws(RecognitionError) -> [LanguageProbability] {
                try inner.detectLanguage(samples, threads: threads)
            }

            func noSpeechProbabilities(_ samples: [Float], threads: Int) throws(RecognitionError) -> [Float] {
                runtime.gate ? try inner.noSpeechProbabilities(samples, threads: threads) : []
            }

            func transcribe(
                _ samples: [Float], _ inference: WhisperInference, shouldAbort: @escaping @Sendable () -> Bool,
                progress: @escaping @Sendable (Double) -> Void
            ) throws(RecognitionError) -> [WhisperSegment] {
                var inference = inference
                inference.decoding = runtime.decoding
                let start = ContinuousClock.now
                let segments = try inner.transcribe(samples, inference, shouldAbort: shouldAbort, progress: progress)
                let elapsed = ContinuousClock.now - start
                // `LEMMETYPE_DIAGNOSTICS_EXTRA=0` leaves the model alone after decoding.
                let extra = WhisperDecodingDiagnosticsTests.environment["LEMMETYPE_DIAGNOSTICS_EXTRA"] != "0"
                let detection = extra ? (try? inner.detectLanguage(samples, threads: inference.threads)) ?? [] : []
                let noSpeechStart = ContinuousClock.now
                let noSpeech =
                    extra ? (try? inner.noSpeechProbabilities(samples, threads: inference.threads)) ?? [] : []
                let noSpeechTime = ContinuousClock.now - noSpeechStart
                runtime.record(
                    DecodeStatistics(
                        segments: segments, language: inference.language,
                        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
                        detection: detection, windowNoSpeech: noSpeech,
                        noSpeechSeconds: Double(noSpeechTime.components.attoseconds) / 1e18
                            + Double(noSpeechTime.components.seconds)),
                    text: segments.map(\.text).joined(separator: " "))
                return segments
            }
        }
    }

    extension JSONEncoder {
        fileprivate static var sorted: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        }
    }
#endif
