#if DEBUG && os(macOS)
    import Domain
    import Foundation

    /// The versioned benchmark corpus (`docs/testing/benchmark-corpus.json`).
    public struct BenchmarkCorpus: Decodable, Sendable {
        public struct Voice: Decodable, Sendable {
            public let name: String
            public let accent: String
        }

        public struct Noise: Decodable, Sendable {
            public let snrDecibels: Double
            public let seed: UInt64
        }

        public struct Utterance: Decodable, Sendable {
            public let id: String
            public let category: String
            public let text: String
            /// The English reference when the corpus translates (E9-S6).
            public let english: String?
        }

        public let version: Int
        /// Names a multilingual corpus; it becomes part of the report name (E9-S6).
        public let name: String?
        /// `"translate-to-english"` scores the English translation against
        /// each utterance's `english` reference; otherwise the original text.
        public let task: String?
        public let voices: [Voice]
        public let noise: Noise
        public let utterances: [Utterance]

        var translatesToEnglish: Bool { task == RecognitionTask.translateToEnglish.rawValue }

        public static func load(from url: URL) throws -> BenchmarkCorpus {
            try JSONDecoder().decode(BenchmarkCorpus.self, from: Data(contentsOf: url))
        }
    }

    /// End-to-end dictation benchmark (E2-S10, docs/testing/performance-thresholds.md).
    ///
    /// Synthesises every corpus sentence with `say` for every voice (plus a
    /// noisy copy for the first voice), runs each recording through the real
    /// ``TranscriptionPipeline`` with ``EvaluationRunner`` — recognition, Clean
    /// Writing, delivery to a discarding target — and measures latency, warm-up, inference, memory,
    /// and word error rate. Transcripts are compared in memory and dropped;
    /// audio is deleted by the pipeline as each session completes. Only
    /// metrics leave this type.
    public enum DictationBenchmark {
        public struct Measurement: Codable, Sendable {
            public let id: String
            public let category: String
            public let accent: String
            public let noisy: Bool
            public let audioSeconds: Double
            /// Recognition only.
            public let inferenceSeconds: Double
            /// Capture stop (processing start) to delivered text.
            public let stopToDeliverySeconds: Double
            public let wordErrorRate: Double
            public let delivered: Bool
        }

        public struct Summary: Codable, Sendable {
            public let mean: Double
            public let p95: Double

            init(_ values: [Double]) {
                let sorted = values.sorted()
                mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            }
        }

        /// Metrics only — no audio, no transcripts.
        public struct Report: Codable, Sendable {
            public let engine: String
            public let corpusVersion: Int
            public let date: Date
            public let operatingSystem: String
            public let hardwareModel: String
            public let physicalMemoryGB: Int
            public let warmUpSeconds: Double
            public let peakMemoryIncreaseMB: Double
            public let audioSeconds: Summary
            public let inferenceSeconds: Summary
            public let stopToDeliverySeconds: Summary
            public let realTimeFactor: Summary
            public let wordErrorRate: Double
            public let wordErrorRateByCategory: [String: Double]
            public let wordErrorRateByAccent: [String: Double]
            public let noisyWordErrorRate: Double
            public let failedSessions: Int
            public let sessions: Int
        }

        public enum BenchmarkError: Error {
            case synthesisFailed(String)
            case engineNotReady(String)
        }

        /// `label` names the report (and its thresholds); the engine id by default.
        /// Per-model Whisper runs use the model id (E5-S7).
        public static func run(
            engine: any SpeechRecognitionEngine,
            corpus: BenchmarkCorpus,
            workDirectory: URL,
            label: String? = nil
        ) async throws -> Report {
            let language = corpus.voices.first?.accent ?? "en-US"
            let need = RecognitionNeed(
                language: language, task: corpus.translatesToEnglish ? .translateToEnglish : .transcribe)
            let availability = await engine.availability(for: need)
            guard availability.isReady else { throw BenchmarkError.engineNotReady(availability.identifier) }
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let memoryBefore = EvaluationHost.peakResidentBytes()
            let warmUpStart = ContinuousClock.now
            try await engine.prepare()
            let warmUp = (ContinuousClock.now - warmUpStart).benchmarkSeconds

            let runner = EvaluationRunner(
                engine: engine, workDirectory: workDirectory.appendingPathComponent("sessions", isDirectory: true))
            let task: RecognitionTask = corpus.translatesToEnglish ? .translateToEnglish : .transcribe
            var measurements: [Measurement] = []
            for utterance in corpus.utterances {
                for (index, voice) in corpus.voices.enumerated() {
                    var variants = [false]
                    if index == 0 { variants.append(true) }
                    for noisy in variants {
                        let url = workDirectory.appendingPathComponent(
                            "\(utterance.id)-\(voice.name)\(noisy ? "-noisy" : "").wav")
                        try synthesize(utterance.text, voice: voice.name, to: url)
                        if noisy {
                            try AudioClip.load(from: url)
                                .withNoise(snrDecibels: corpus.noise.snrDecibels, seed: corpus.noise.seed)
                                .write(to: url)
                        }
                        let result = try await runner.run(
                            EvaluationCase(
                                id: utterance.id, audioURL: url, language: voice.accent, reference: utterance.text,
                                englishReference: utterance.english, category: utterance.category),
                            task: task)
                        try? FileManager.default.removeItem(at: url)
                        measurements.append(
                            Measurement(
                                id: utterance.id, category: utterance.category, accent: voice.accent, noisy: noisy,
                                audioSeconds: result.audioSeconds, inferenceSeconds: result.inferenceSeconds,
                                stopToDeliverySeconds: result.stopToDeliverySeconds,
                                wordErrorRate: result.producedText ? result.score.wordErrorRate : 1,
                                delivered: result.producedText))
                    }
                }
            }
            await engine.unload()
            let reportName =
                label ?? [engine.descriptor.id.rawValue, corpus.name].compactMap(\.self).joined(separator: "-")
            return report(
                engine: reportName, corpus: corpus, warmUp: warmUp,
                peakMemory: EvaluationHost.peakResidentBytes() - memoryBefore, measurements: measurements)
        }

        static func report(
            engine: String, corpus: BenchmarkCorpus, warmUp: Double, peakMemory: Int, measurements: [Measurement]
        ) -> Report {
            func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
            func grouped(by key: (Measurement) -> String) -> [String: Double] {
                Dictionary(grouping: measurements.filter { !$0.noisy }, by: key).mapValues {
                    mean($0.map(\.wordErrorRate))
                }
            }
            return Report(
                engine: engine, corpusVersion: corpus.version, date: Date(),
                operatingSystem: EvaluationHost.operatingSystem,
                hardwareModel: EvaluationHost.hardwareModel(), physicalMemoryGB: EvaluationHost.physicalMemoryGB,
                warmUpSeconds: warmUp, peakMemoryIncreaseMB: Double(peakMemory) / 1_048_576,
                audioSeconds: Summary(measurements.map(\.audioSeconds)),
                inferenceSeconds: Summary(measurements.map(\.inferenceSeconds)),
                stopToDeliverySeconds: Summary(measurements.map(\.stopToDeliverySeconds)),
                realTimeFactor: Summary(measurements.map { $0.inferenceSeconds / max($0.audioSeconds, 0.01) }),
                wordErrorRate: mean(measurements.filter { !$0.noisy }.map(\.wordErrorRate)),
                wordErrorRateByCategory: grouped(by: \.category),
                wordErrorRateByAccent: grouped(by: \.accent),
                noisyWordErrorRate: mean(measurements.filter(\.noisy).map(\.wordErrorRate)),
                failedSessions: measurements.filter { !$0.delivered }.count,
                sessions: measurements.count)
        }

        /// Writes `<engine>.json` and `<engine>.md` into `directory`.
        public static func write(_ report: Report, to directory: URL) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: directory.appendingPathComponent("\(report.engine).json"))
            try Data(markdown(report).utf8).write(to: directory.appendingPathComponent("\(report.engine).md"))
        }

        public static func markdown(_ report: Report) -> String {
            func row(_ name: String, _ summary: Summary, unit: String = "s") -> String {
                String(format: "| %@ | %.2f %@ | %.2f %@ |", name, summary.mean, unit, summary.p95, unit)
            }
            var lines = [
                "# Dictation benchmark — \(report.engine)",
                "",
                "Corpus v\(report.corpusVersion) · \(report.hardwareModel) · \(report.physicalMemoryGB) GB · "
                    + "\(report.operatingSystem) · \(report.date.formatted(.iso8601))",
                "",
                "| Metric | Mean | p95 |",
                "|---|---|---|",
                row("Audio duration", report.audioSeconds),
                row("Inference", report.inferenceSeconds),
                row("Capture stop → delivered", report.stopToDeliverySeconds),
                row("Real-time factor", report.realTimeFactor, unit: "×"),
                "",
                String(
                    format: "Warm-up %.2f s · peak memory increase %.0f MB · ", report.warmUpSeconds,
                    report.peakMemoryIncreaseMB)
                    + String(
                        format: "WER %.1f %% · noisy WER %.1f %% · %d of %d sessions failed",
                        report.wordErrorRate * 100, report.noisyWordErrorRate * 100, report.failedSessions,
                        report.sessions),
                "",
                "| Group | WER |",
                "|---|---|",
            ]
            for (name, value) in report.wordErrorRateByCategory.sorted(by: { $0.key < $1.key }) {
                lines.append(String(format: "| %@ | %.1f %% |", name, value * 100))
            }
            for (name, value) in report.wordErrorRateByAccent.sorted(by: { $0.key < $1.key }) {
                lines.append(String(format: "| accent %@ | %.1f %% |", name, value * 100))
            }
            return lines.joined(separator: "\n") + "\n"
        }

        // MARK: Audio

        /// `say` writes 16 kHz mono float WAVE, the speech capture format.
        static func synthesize(_ text: String, voice: String, to url: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = [
                "-v", voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text,
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw BenchmarkError.synthesisFailed(voice) }
        }
    }
#endif
