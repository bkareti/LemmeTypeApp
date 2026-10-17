#if DEBUG
    import AVFoundation
    import Darwin
    import Domain
    import Foundation
    import Synchronization

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
        }

        public let version: Int
        public let voices: [Voice]
        public let noise: Noise
        public let utterances: [Utterance]

        public static func load(from url: URL) throws -> BenchmarkCorpus {
            try JSONDecoder().decode(BenchmarkCorpus.self, from: Data(contentsOf: url))
        }
    }

    /// End-to-end dictation benchmark (E2-S10, docs/testing/performance-thresholds.md).
    ///
    /// Synthesises every corpus sentence with `say` for every voice (plus a
    /// noisy copy for the first voice), runs each recording through the real
    /// ``TranscriptionPipeline`` — recognition, Clean Writing, delivery to a
    /// discarding target — and measures latency, warm-up, inference, memory,
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

        public static func run(
            engine: any SpeechRecognitionEngine,
            corpus: BenchmarkCorpus,
            workDirectory: URL
        ) async throws -> Report {
            let availability = await engine.availability()
            guard availability.isReady else { throw BenchmarkError.engineNotReady(availability.identifier) }
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let memoryBefore = peakMemoryBytes()
            let warmUpStart = ContinuousClock.now
            try await engine.prepare()
            let warmUp = (ContinuousClock.now - warmUpStart).benchmarkSeconds

            let delivery = MeasuringDelivery()
            let pipeline = TranscriptionPipeline(engines: [engine], write: TextCleaner.write, delivery: delivery)
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
                            try addNoise(to: url, snrDecibels: corpus.noise.snrDecibels, seed: corpus.noise.seed)
                        }
                        let measurement = try await measure(
                            utterance, voice: voice, noisy: noisy, url: url,
                            run: Run(pipeline: pipeline, engine: engine.descriptor.id, delivery: delivery))
                        measurements.append(measurement)
                        try? FileManager.default.removeItem(at: url)  // already gone after delivery
                    }
                }
            }
            await engine.unload()
            return report(
                engine: engine.descriptor.id.rawValue, corpus: corpus, warmUp: warmUp,
                peakMemory: peakMemoryBytes() - memoryBefore, measurements: measurements)
        }

        /// What every measurement in one run shares.
        private struct Run {
            let pipeline: TranscriptionPipeline
            let engine: RecognitionEngineID
            let delivery: MeasuringDelivery
        }

        private static func measure(
            _ utterance: BenchmarkCorpus.Utterance, voice: BenchmarkCorpus.Voice, noisy: Bool, url: URL, run: Run
        ) async throws -> Measurement {
            let (pipeline, engine, delivery) = (run.pipeline, run.engine, run.delivery)
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            let session = DictationSession(
                audio: RecordedAudio(fileURL: url, duration: seconds, format: .speech), target: nil, mode: .clean,
                language: voice.accent, enginePreference: EnginePreference(selected: engine))
            let phases = Mutex<[ProcessingPhase: ContinuousClock.Instant]>([:])
            delivery.expect(reference: utterance.text)
            let start = ContinuousClock.now
            let outcome = await pipeline.process(session) { update in
                if case .phase(let phase) = update { phases.withLock { $0[phase] = ContinuousClock.now } }
            }
            let end = ContinuousClock.now
            session.discardAudio()
            let marks = phases.withLock { $0 }
            let inference =
                marks[.recognizing].map { recognizing in ((marks[.writing] ?? end) - recognizing).benchmarkSeconds }
                ?? 0
            let delivered: Bool
            if case .delivered = outcome { delivered = true } else { delivered = false }
            return Measurement(
                id: utterance.id, category: utterance.category, accent: voice.accent, noisy: noisy,
                audioSeconds: seconds, inferenceSeconds: inference,
                stopToDeliverySeconds: (end - start).benchmarkSeconds,
                wordErrorRate: delivered ? delivery.takeWordErrorRate() : 1, delivered: delivered)
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
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                hardwareModel: hardwareModel(), physicalMemoryGB: Int(ProcessInfo.processInfo.physicalMemory >> 30),
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

        /// Mixes deterministic white noise into the file at `snrDecibels`.
        static func addNoise(to url: URL, snrDecibels: Double, seed: UInt64) throws {
            let input = try AVAudioFile(forReading: url)
            let format = input.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length))
            else { return }
            try input.read(into: buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var power = 0.0
            for index in 0..<count { power += Double(samples[index] * samples[index]) }
            let signal = power / Double(max(count, 1))
            let noiseAmplitude = Float((signal / pow(10, snrDecibels / 10) * 3).squareRoot())
            var generator = SeededGenerator(seed: seed)
            for index in 0..<count {
                samples[index] += Float.random(in: -1...1, using: &generator) * noiseAmplitude
            }
            let output = try AVAudioFile(
                forWriting: url, settings: input.fileFormat.settings, commonFormat: format.commonFormat,
                interleaved: format.isInterleaved)
            try output.write(from: buffer)
        }

        static func peakMemoryBytes() -> Int {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return usage.ru_maxrss  // bytes on macOS
        }

        static func hardwareModel() -> String {
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname("hw.model", &model, &size, nil, 0)
            return String(bytes: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "unknown"
        }
    }

    /// A delivery target that scores the text against the reference and
    /// immediately forgets it.
    final class MeasuringDelivery: TextDelivering {
        private struct State {
            var reference = ""
            var wordErrorRate = 1.0
        }

        private let state = Mutex(State())

        func expect(reference: String) {
            state.withLock {
                $0.reference = reference
                $0.wordErrorRate = 1
            }
        }

        func takeWordErrorRate() -> Double { state.withLock { $0.wordErrorRate } }

        func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
            state.withLock { $0.wordErrorRate = WordErrorRate.of(reference: $0.reference, hypothesis: text) }
            return .delivered(.accessibility)
        }
    }

    /// SplitMix64, so noisy audio is identical on every run.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    extension Duration {
        var benchmarkSeconds: Double {
            Double(components.seconds) + Double(components.attoseconds) / 1e18
        }
    }
#endif
