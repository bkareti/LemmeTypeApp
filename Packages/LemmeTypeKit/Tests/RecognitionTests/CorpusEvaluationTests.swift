// macOS only: the socket watch is macOS-only; on iPhone and iPad the app runs the
// evaluation itself (`IOSComposition+Evaluation.swift`, scripts/run-ios-evaluation.sh).
#if os(macOS)
    import Domain
    import Editing
    import Foundation
    import TestSupport
    import Testing

    @testable import Recognition

    /// Opt-in corpus evaluation with a real Whisper model (docs/testing/evaluation-harness.md).
    /// Runs the committed manifests against the fetched corpus, with a socket watch
    /// proving no network was used, and writes an `EvaluationReport` to
    /// `build/evaluation/`. Run it with `scripts/run-evaluation.sh`.
    ///
    /// - `LEMMETYPE_EVALUATION=1` turns it on.
    /// - `LEMMETYPE_CORPUS_ROOT`: the fetched FLEURS folder.
    /// - `LEMMETYPE_EVALUATION_MODEL`: a model id such as `whisper-small` (default: every installed multilingual model).
    /// - `LEMMETYPE_EVALUATION_TASK`: `transcribe` (default) or `translate-to-english`.
    /// - `LEMMETYPE_EVALUATION_LANGUAGES`: such as `hi,te` (default: all).
    /// - `LEMMETYPE_EVALUATION_MODE`: `exact`, `clean` (default), or `message`.
    /// - `LEMMETYPE_EVALUATION_STYLE`: a style such as `professional-email-concise` (tone-format-length) on
    ///   top of Clean Writing, rewritten by the on-device model; needs Apple Intelligence.
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_EVALUATION"] == "1"), .serialized)
    struct CorpusEvaluationTests {
        static let environment = ProcessInfo.processInfo.environment

        static var models: [ModelAsset] {
            let installed = ModelCatalog.whisperModels.filter {
                FileManager.default.fileExists(atPath: RecognitionBenchmarkTests.modelURL(for: $0).path)
            }
            guard let wanted = environment["LEMMETYPE_EVALUATION_MODEL"] else {
                return installed.filter { $0.languages.count > 1 }
            }
            return installed.filter { $0.id.rawValue == wanted }
        }

        @Test func everyChosenModelOnTheCorpus() async throws {
            let root = URL(fileURLWithPath: try #require(Self.environment["LEMMETYPE_CORPUS_ROOT"]), isDirectory: true)
            let task = try EvaluationOptions.task(Self.environment["LEMMETYPE_EVALUATION_TASK"])
            let languages = EvaluationOptions.languages(Self.environment["LEMMETYPE_EVALUATION_LANGUAGES"])
            try #require(!Self.models.isEmpty, "Install the Whisper model to evaluate first")
            let mode = try EvaluationOptions.mode(
                Self.environment["LEMMETYPE_EVALUATION_MODE"] ?? "clean",
                style: Self.environment["LEMMETYPE_EVALUATION_STYLE"])
            let corpus = RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent("docs/testing/corpus")
            let selections = ["fleurs.json", "edge-cases.json"].map {
                CorpusEvaluation.Selection(manifestURL: corpus.appendingPathComponent($0), root: root)
            }

            for asset in Self.models {
                let engine = WhisperEngine(
                    assets: FixedModelLocation(url: RecognitionBenchmarkTests.modelURL(for: asset)), hardware: .current,
                    runtime: WhisperCppRuntime(), settings: { WhisperRunSettings(choice: .specific(asset.id)) })
                let watch = SocketWatch()
                let report = try await CorpusEvaluation.run(
                    engine: engine, selections: selections, task: task, mode: mode, label: asset.id.rawValue,
                    languages: languages,
                    workDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeTests-Evaluation-\(UUID().uuidString)", isDirectory: true),
                    rewriter: mode.effectiveStyle.isNone ? nil : FoundationModelsRewriter())
                let sockets = watch.stop()

                #expect(sockets.isEmpty, "the evaluation opened \(sockets)")
                _ = try report.write(
                    to: RecognitionBenchmarkTests.repositoryRoot.appendingPathComponent("build/evaluation"))
                #expect(!report.runs.isEmpty)
            }
        }
    }
#endif
