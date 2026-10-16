import AVFoundation
import Darwin
import Domain
import Foundation
import TestSupport
import Testing

@testable import Recognition

/// Opt-in recognition benchmark (docs/decisions/0012-local-whisper-model.md).
/// Synthesises the versioned corpus with `say`, runs the engine, and reports
/// warm-up time, inference time, real-time factor, peak memory, and word
/// error rate. Only metrics are printed or written; transcripts are discarded.
///
/// Run with `scripts/run-recognition-benchmark.sh` on a Mac with the Whisper
/// model installed (or `LEMMETYPE_WHISPER_MODEL=/path/to/ggml-base.en.bin`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_BENCHMARK"] == "1"))
struct RecognitionBenchmarkTests {
    struct Corpus: Decodable {
        let version: Int
        let voices: [String]
        let utterances: [BenchmarkUtterance]
    }

    struct Measurement {
        let id: String
        let category: String
        let audioSeconds: Double
        let inferenceSeconds: Double
        let wordErrorRate: Double
    }

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func loadCorpus() throws -> Corpus {
        let url = repositoryRoot.appendingPathComponent("docs/testing/benchmark-corpus.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    /// `say` writes 16 kHz mono float WAVE, the speech capture format.
    static func synthesize(_ text: String, voice: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }

    static func peakMemoryBytes() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return usage.ru_maxrss  // bytes on macOS
    }

    static func whisperModelURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["LEMMETYPE_WHISPER_MODEL"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let asset = ModelCatalog.whisperBaseEnglish
        return support.appendingPathComponent("LemmeType/Models/\(asset.id.rawValue)/\(asset.version)")
            .appendingPathComponent(asset.files[0].name)
    }

    @Test func whisperBaseEnglish() async throws {
        let modelURL = Self.whisperModelURL()
        try #require(FileManager.default.fileExists(atPath: modelURL.path), "Install the Whisper model first")
        let engine = WhisperEngine(
            assets: FixedModelLocation(url: modelURL), hardware: .current, runtime: WhisperCppRuntime())
        try await run(engine, name: "whisper-base-en")
    }

    func run(_ engine: any SpeechRecognitionEngine, name: String) async throws {
        let corpus = try Self.loadCorpus()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-Benchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let memoryBefore = Self.peakMemoryBytes()
        let warmUpStart = ContinuousClock.now
        try await engine.prepare()
        let warmUp = (ContinuousClock.now - warmUpStart).seconds

        var measurements: [Measurement] = []
        for utterance in corpus.utterances {
            for voice in corpus.voices {
                let url = directory.appendingPathComponent("\(utterance.id)-\(voice).wav")
                try Self.synthesize(utterance.text, voice: voice, to: url)
                let file = try AVAudioFile(forReading: url)
                let seconds = Double(file.length) / file.processingFormat.sampleRate
                let request = RecognitionRequest(
                    audio: RecordedAudio(fileURL: url, duration: seconds, format: .speech), language: "en-US")
                let start = ContinuousClock.now
                let transcript = try await RecognitionRunner().run(engine, request)
                measurements.append(
                    Measurement(
                        id: utterance.id, category: utterance.category, audioSeconds: seconds,
                        inferenceSeconds: (ContinuousClock.now - start).seconds,
                        wordErrorRate: WordErrorRate.of(reference: utterance.text, hypothesis: transcript.text)))
                try FileManager.default.removeItem(at: url)
            }
        }
        await engine.unload()
        let report = Self.report(
            name: name, corpusVersion: corpus.version, warmUp: warmUp,
            peakMemory: Self.peakMemoryBytes() - memoryBefore, measurements: measurements)
        try Self.write(report, name: name)
        #expect(!measurements.isEmpty)
    }

    static func report(
        name: String, corpusVersion: Int, warmUp: Double, peakMemory: Int, measurements: [Measurement]
    ) -> String {
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        let sorted = measurements.map(\.inferenceSeconds).sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        var lines = [
            "# Recognition benchmark — \(name)",
            "",
            "Corpus v\(corpusVersion) · \(ProcessInfo.processInfo.operatingSystemVersionString) · "
                + "\(ProcessInfo.processInfo.physicalMemory >> 30) GB · \(Date().formatted(.iso8601))",
            "",
            "| Metric | Value |",
            "|---|---|",
            String(format: "| Warm-up | %.2f s |", warmUp),
            String(format: "| Mean inference | %.2f s |", mean(measurements.map(\.inferenceSeconds))),
            String(format: "| p95 inference | %.2f s |", p95),
            String(
                format: "| Mean real-time factor | %.3f |",
                mean(measurements.map { $0.inferenceSeconds / max($0.audioSeconds, 0.01) })),
            String(format: "| Peak memory increase | %.0f MB |", Double(peakMemory) / 1_048_576),
            String(format: "| Mean WER | %.1f %% |", mean(measurements.map(\.wordErrorRate)) * 100),
            "",
            "| Category | Utterances | Mean WER |",
            "|---|---|---|",
        ]
        for category in Set(measurements.map(\.category)).sorted() {
            let group = measurements.filter { $0.category == category }
            lines.append(
                String(format: "| %@ | %d | %.1f %% |", category, group.count, mean(group.map(\.wordErrorRate)) * 100))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func write(_ report: String, name: String) throws {
        let directory = repositoryRoot.appendingPathComponent("build/benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).md")
        try Data(report.utf8).write(to: url)
    }
}

struct BenchmarkUtterance: Decodable {
    let id: String
    let category: String
    let text: String
}

/// Points an engine at a model file outside the managed store.
struct FixedModelLocation: ModelAssetManaging {
    let url: URL

    func state(of asset: ModelAssetID) async -> ModelInstallState { .installed }
    func installedFile(for asset: ModelAssetID, named name: String) async -> URL? { url }
    func availableBytes() async -> Int64 { 0 }
    func install(
        _ consent: ModelDownloadConsent, progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState { .installed }
    func pause(_ asset: ModelAssetID) async {}
    func remove(_ asset: ModelAssetID) async throws(ModelAssetError) {}
    func removeUnusableFiles() async {}
}
