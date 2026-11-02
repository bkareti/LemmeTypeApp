#if DEBUG
    import Domain
    import Foundation

    /// Runs every item of one or more corpus manifests through one engine and
    /// collects an ``EvaluationReport``: warm-up and peak memory for the run,
    /// then each item through ``EvaluationRunner``.
    public enum CorpusEvaluation {
        /// A manifest and where its recordings are on this device.
        public struct Selection: Sendable {
            public let manifestURL: URL
            /// The fetched corpus folder; unused by manifests without recordings.
            public let root: URL

            public init(manifestURL: URL, root: URL) {
                self.manifestURL = manifestURL
                self.root = root
            }
        }

        /// - `languages`: only items in these languages (BCP 47 base, such as `hi`), or all when `nil`.
        /// - `progress`: called after each item with the number done and the total.
        public static func run(
            engine: any SpeechRecognitionEngine, selections: [Selection], task: RecognitionTask = .transcribe,
            writingMode: WritingMode = .clean, label: String? = nil, languages: Set<String>? = nil,
            workDirectory: URL, hardware: HardwareProfile = .current, reviewsEveryResult: Bool = false,
            progress: @Sendable (Int, Int) -> Void = { _, _ in }
        ) async throws -> EvaluationReport {
            var corpora: [EvaluationReport.Corpus] = []
            var items: [CorpusItem] = []
            var skipped: [String: Int] = [:]
            for selection in selections {
                let manifest = try CorpusManifest.load(from: selection.manifestURL)
                var chosen: [CorpusItem] = []
                for item in try manifest.items(root: selection.root) {
                    if let languages, !languages.contains(SpokenLanguages.code(of: item.language)) { continue }
                    if let reason = unscorable(item, for: task) {
                        skipped[reason, default: 0] += 1
                    } else {
                        chosen.append(item)
                    }
                }
                corpora.append(
                    .init(
                        name: manifest.name, sha256: try CorpusManifest.sha256(of: selection.manifestURL),
                        runs: chosen.count))
                items += chosen
            }

            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }
            let memoryBefore = EvaluationHost.peakResidentBytes()
            let warmUpStart = ContinuousClock.now
            try await engine.prepare()
            let warmUp = (ContinuousClock.now - warmUpStart).benchmarkSeconds
            let runner = EvaluationRunner(
                engine: engine, workDirectory: workDirectory.appendingPathComponent("sessions", isDirectory: true),
                hardware: hardware, reviewsEveryResult: reviewsEveryResult)

            var runs: [EvaluationRun] = []
            runs.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                let result = try await item.run(
                    with: runner, workDirectory: workDirectory, task: task, writingMode: writingMode)
                runs.append(
                    EvaluationRun(
                        id: item.id, baseID: item.baseID, variantID: item.variantID, source: item.source,
                        tags: item.tags, review: item.review.rawValue, result: result))
                progress(index + 1, items.count)
            }
            await engine.unload()

            return EvaluationReport(
                schema: EvaluationReport.schemaVersion, label: label ?? engine.descriptor.id.rawValue,
                engine: engine.descriptor.id.rawValue, task: task.rawValue, writingMode: writingMode.rawValue,
                date: Date(), operatingSystem: EvaluationHost.operatingSystem,
                hardwareModel: EvaluationHost.hardwareModel(), physicalMemoryGB: EvaluationHost.physicalMemoryGB,
                warmUpSeconds: warmUp,
                peakMemoryIncreaseMB: Double(EvaluationHost.peakResidentBytes() - memoryBefore) / 1_048_576,
                corpora: corpora, skipped: skipped, runs: runs)
        }

        /// Why an item cannot be scored for `task`, or `nil` when it can.
        static func unscorable(_ item: CorpusItem, for task: RecognitionTask) -> String? {
            switch task {
            case .transcribe:
                nil
            case .translateToEnglish:
                if SpokenLanguages.isEnglish(item.language) {
                    "already-english"
                } else if item.englishReference == nil {
                    "no-english-reference"
                } else {
                    nil
                }
            }
        }
    }
#endif
