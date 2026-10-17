import Domain
import Foundation
import TestSupport
import Testing

@testable import Recognition

/// Opt-in recognition benchmark (docs/decisions/0012-local-whisper-model.md,
/// docs/testing/performance-thresholds.md). Runs the versioned corpus through
/// the full pipeline with `DictationBenchmark` and writes metrics only to
/// `build/benchmarks/`.
///
/// Run with `scripts/run-recognition-benchmark.sh` on a Mac with Whisper
/// models installed (or `LEMMETYPE_WHISPER_MODEL=/path/to/ggml-base.en.bin`);
/// every installed size is measured.
/// Apple Speech needs Speech Recognition authorization, which a test runner
/// can't get, so it runs inside the app (`scripts/run-e2e-benchmark.sh`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_BENCHMARK"] == "1"))
struct RecognitionBenchmarkTests {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Where a model lives: `LEMMETYPE_WHISPER_MODEL` (Base only) or the managed store.
    static func modelURL(for asset: ModelAsset) -> URL {
        if asset.id == .whisperBaseEnglish, let path = ProcessInfo.processInfo.environment["LEMMETYPE_WHISPER_MODEL"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LemmeType/Models/\(asset.id.rawValue)/\(asset.version)")
            .appendingPathComponent(asset.files[0].name)
    }

    /// Base keeps the `whisper` report name (and thresholds) from Epic 2;
    /// the other sizes report under their model id (E5-S7).
    static func label(for asset: ModelAsset) -> String {
        asset.id == .whisperBaseEnglish ? RecognitionEngineID.whisper.rawValue : asset.id.rawValue
    }

    /// Every installed Whisper model: load time (`warmUpSeconds`), real-time
    /// factor, memory (`peakMemoryIncreaseMB`), latency, and accuracy.
    @Test func everyInstalledWhisperModel() async throws {
        let installed = ModelCatalog.whisperModels.filter {
            FileManager.default.fileExists(atPath: Self.modelURL(for: $0).path)
        }
        try #require(!installed.isEmpty, "Install a Whisper model first")
        let corpus = try BenchmarkCorpus.load(
            from: Self.repositoryRoot.appendingPathComponent("docs/testing/benchmark-corpus.json"))
        for asset in installed {
            let engine = WhisperEngine(
                assets: FixedModelLocation(url: Self.modelURL(for: asset)), hardware: .current,
                runtime: WhisperCppRuntime(),
                settings: { WhisperRunSettings(choice: .specific(asset.id)) })
            let report = try await DictationBenchmark.run(
                engine: engine, corpus: corpus,
                workDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("LemmeTypeTests-Benchmark-\(UUID().uuidString)", isDirectory: true),
                label: Self.label(for: asset))
            try DictationBenchmark.write(report, to: Self.repositoryRoot.appendingPathComponent("build/benchmarks"))
            #expect(report.sessions > 0)
        }
    }
}

/// Points an engine at a model file outside the managed store.
struct FixedModelLocation: ModelAssetManaging {
    let url: URL

    func state(of asset: ModelAssetID) async -> ModelInstallState { .installed }
    func installedFile(for asset: ModelAssetID, named name: String) async -> URL? { url }
    func verifiedFile(for asset: ModelAssetID, named name: String) async -> URL? { url }
    func availableBytes() async -> Int64 { 0 }
    func install(
        _ consent: ModelDownloadConsent, progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState { .installed }
    func pause(_ asset: ModelAssetID) async {}
    func remove(_ asset: ModelAssetID) async throws(ModelAssetError) {}
    func removeUnusableFiles() async {}
}
