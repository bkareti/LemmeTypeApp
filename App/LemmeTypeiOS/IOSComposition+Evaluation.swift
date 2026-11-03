#if DEBUG
    import Domain
    import Editing
    import Foundation
    import Lifecycle
    import ModelAssets
    import Recognition
    import Support
    import TestSupport
    import UIKit

    /// Debug-only on-device evaluation: the corpus evaluation of `docs/testing/evaluation-harness.md`
    /// run inside the iPhone or iPad app, with the app's own model store, memory check, and
    /// performance plan, so a report says what this device does. `scripts/run-ios-evaluation.sh`
    /// copies the manifests and audio into the app's Documents folder, launches the app, and
    /// copies the report back:
    ///
    ///     Documents/LemmeTypeEvaluation/manifests/*.json   the committed manifests
    ///     Documents/LemmeTypeEvaluation/corpus/            the root their audio paths are relative to
    ///     Documents/LemmeTypeEvaluation/reports/           written: one EvaluationReport
    ///     Documents/LemmeTypeEvaluation/status.json        written last: done or failed, and why
    ///
    /// `manifests` and `corpus` are deleted when the run ends, whatever the outcome.
    ///
    /// Reports hold scores and timings only, never text. Unlike the Mac run there is no socket
    /// watch on iOS, so a device run is made in Airplane Mode (MA-70).
    extension IOSComposition {
        struct EvaluationRequest: Equatable {
            /// `-LemmeTypeEvaluation <model id>` turns the run on.
            static let argument = "-LemmeTypeEvaluation"
            static let taskArgument = "-LemmeTypeEvaluationTask"
            static let modeArgument = "-LemmeTypeEvaluationMode"
            static let styleArgument = "-LemmeTypeEvaluationStyle"
            static let languagesArgument = "-LemmeTypeEvaluationLanguages"
            static let labelArgument = "-LemmeTypeEvaluationLabel"

            let model: ModelAssetID
            var task: String?
            var mode = "clean"
            var style: String?
            var languages: String?
            var label: String?

            init(model: ModelAssetID) {
                self.model = model
            }

            init?(arguments: [String]) {
                func value(after flag: String) -> String? {
                    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                    return arguments[index + 1]
                }
                guard let model = value(after: Self.argument) else { return nil }
                self.model = ModelAssetID(rawValue: model)
                task = value(after: Self.taskArgument)
                mode = value(after: Self.modeArgument) ?? mode
                style = value(after: Self.styleArgument)
                languages = value(after: Self.languagesArgument)
                label = value(after: Self.labelArgument)
            }
        }

        /// What `status.json` says; the script waits for it.
        struct EvaluationStatus: Codable, Equatable {
            /// `done` or `failed`.
            let status: String
            /// A stable identifier when it failed, such as `engine.assets-missing`.
            var reason: String?
            var report: String?
            var runs: Int?
        }

        static func evaluationFolder() -> URL {
            URL.documentsDirectory.appendingPathComponent("LemmeTypeEvaluation", isDirectory: true)
        }

        /// Runs the request, writes `status.json`, and returns the process exit status (0 when a report was written).
        static func runEvaluation(_ request: EvaluationRequest, folder: URL = evaluationFolder()) async -> Int32 {
            removeLeftoverWork()
            // A long run must not be ended by the screen locking.
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let status: EvaluationStatus
            do {
                status = try await evaluate(request, folder: folder)
            } catch let failure as EvaluationFailure {
                status = EvaluationStatus(status: "failed", reason: failure.reason)
            } catch is EvaluationOptions.Problem {
                status = EvaluationStatus(status: "failed", reason: "evaluation.unknown-option")
            } catch {
                Log.recognition.error("On-device evaluation failed")
                status = EvaluationStatus(status: "failed", reason: "evaluation.error")
            }
            // Corpus audio never stays on the device: what the script copied in is removed
            // (on the Simulator the corpus is a link to the Mac's cache, and only the link goes).
            for name in ["corpus", "manifests"] {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            do {
                try JSONEncoder().encode(status).write(to: folder.appendingPathComponent("status.json"))
            } catch {
                Log.recognition.error("On-device evaluation could not write its status")
                return 2
            }
            return status.status == "done" ? 0 : 1
        }

        static let workPrefix = "LemmeTypeEvaluation-"

        /// A run that crashed can leave its work folder, and a recording in it, in `tmp`.
        static func removeLeftoverWork(in directory: URL = FileManager.default.temporaryDirectory) {
            let entries =
                (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.lastPathComponent.hasPrefix(workPrefix) {
                try? FileManager.default.removeItem(at: entry)
            }
        }

        struct EvaluationFailure: Error {
            let reason: String
        }

        private static func evaluate(_ request: EvaluationRequest, folder: URL) async throws -> EvaluationStatus {
            guard let asset = ModelCatalog.whisperModels.first(where: { $0.id == request.model }) else {
                throw EvaluationFailure(reason: "evaluation.unknown-model")
            }
            let mode = try EvaluationOptions.mode(request.mode, style: request.style)
            let task = try EvaluationOptions.task(request.task)
            let manifests = try FileManager.default.contentsOfDirectory(
                at: folder.appendingPathComponent("manifests", isDirectory: true), includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !manifests.isEmpty else { throw EvaluationFailure(reason: "evaluation.no-manifests") }
            let root = folder.appendingPathComponent("corpus", isDirectory: true)

            let preferences = UserDefaultsPreferences()
            let plan = performancePlan(preferences: preferences, conditions: SystemConditionsMonitor().current)
            let engine = WhisperEngine(
                assets: ModelAssetStore.makeDefault(diagnostics: DiscardingDiagnostics()), hardware: .current,
                availableMemory: availableMemory,
                settings: {
                    WhisperRunSettings(
                        choice: .specific(asset.id), order: plan.whisperModelOrder, threads: plan.inferenceThreads,
                        usesGPU: plan.usesGPU && gpuRunsWhisper)
                })
            let availability = await engine.availability()
            guard availability.isReady else { throw EvaluationFailure(reason: "engine.\(availability.identifier)") }

            let report = try await CorpusEvaluation.run(
                engine: engine,
                selections: manifests.map { CorpusEvaluation.Selection(manifestURL: $0, root: root) },
                task: task, mode: mode, label: request.label ?? "ios-\(asset.id.rawValue)",
                languages: EvaluationOptions.languages(request.languages),
                workDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(workPrefix)\(UUID().uuidString)", isDirectory: true),
                reviewsEveryResult: true,
                rewriter: mode.effectiveStyle.isNone ? nil : FoundationModelsRewriter())
            let written = try report.write(to: folder.appendingPathComponent("reports", isDirectory: true))
            return EvaluationStatus(
                status: "done", report: written.lastPathComponent, runs: report.runs.count)
        }
    }
#endif
