#if DEBUG
    import Domain
    import Foundation
    import Support
    import TestSupport

    /// Debug-only end-to-end benchmark (E2-S10): runs the versioned corpus
    /// through every ready engine of the live composition, inside the app so
    /// Apple Speech has its Speech Recognition authorization. Writes metrics
    /// only (`<engine>.json`/`.md`) and quits. Started by
    /// `scripts/run-e2e-benchmark.sh`.
    extension AppComposition {
        /// `-LemmeTypeBenchmark <corpus.json> <output directory>`
        static let benchmarkArgument = "-LemmeTypeBenchmark"

        struct BenchmarkRequest {
            let corpus: URL
            let output: URL
        }

        static func benchmarkRequest(arguments: [String]) -> BenchmarkRequest? {
            guard let index = arguments.firstIndex(of: benchmarkArgument), arguments.count > index + 2 else {
                return nil
            }
            return BenchmarkRequest(
                corpus: URL(fileURLWithPath: arguments[index + 1]),
                output: URL(fileURLWithPath: arguments[index + 2], isDirectory: true))
        }

        /// Returns the process exit status: 0 when at least one engine ran.
        func runBenchmark(_ request: BenchmarkRequest) async -> Int32 {
            let corpus: BenchmarkCorpus
            do {
                corpus = try BenchmarkCorpus.load(from: request.corpus)
            } catch {
                Log.recognition.error("Benchmark corpus could not be read")
                return 2
            }
            if speechAuthorizer.status() == .notRequested {
                _ = await speechAuthorizer.requestAuthorization()
            }
            var completed = 0
            for engine in recognitionEngines {
                let id = engine.descriptor.id.rawValue
                let availability = await engine.availability()
                guard availability.isReady else {
                    Log.recognition.notice(
                        "Benchmark skipped \(id, privacy: .public): \(availability.identifier, privacy: .public)")
                    continue
                }
                do {
                    let work = FileManager.default.temporaryDirectory
                        .appendingPathComponent("LemmeTypeBenchmark-\(UUID().uuidString)", isDirectory: true)
                    let report = try await DictationBenchmark.run(engine: engine, corpus: corpus, workDirectory: work)
                    try DictationBenchmark.write(report, to: request.output)
                    completed += 1
                } catch {
                    Log.recognition.error("Benchmark failed for \(id, privacy: .public)")
                }
            }
            return completed > 0 ? 0 : 1
        }
    }
#endif
