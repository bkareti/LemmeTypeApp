import Domain
import Foundation
import TestSupport
import Testing

/// The report the harness writes and `scripts/evaluation-report.py` reads. The
/// fixture is shared with the Python tests, so both sides agree on the format.
struct EvaluationReportTests {
    static let fixture = CorpusManifestTests.repositoryRoot
        .appendingPathComponent("scripts/tests/fixtures/evaluation-report.json")
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-EvaluationReport-\(UUID().uuidString)", isDirectory: true)

    /// Every key path in a JSON value, with array elements merged; null values are left out
    /// because Swift omits a `nil` optional.
    static func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        switch value {
        case let object as [String: Any]:
            object.reduce(into: Set<String>()) { paths, entry in
                if entry.value is NSNull { return }
                let path = prefix.isEmpty ? entry.key : "\(prefix).\(entry.key)"
                paths.insert(path)
                // `skipped` is keyed by reason, which differs between runs.
                if entry.key != "skipped" { paths.formUnion(keyPaths(entry.value, prefix: path)) }
            }
        case let array as [Any]:
            array.reduce(into: Set<String>()) { $0.formUnion(keyPaths($1, prefix: prefix + "[]")) }
        default:
            []
        }
    }

    private func manifest(_ name: String, _ manifest: CorpusManifest) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try JSONEncoder().encode(manifest).write(to: url)
        return url
    }

    private func recordings() throws -> CorpusManifest {
        let source = CorpusManifestTests.source
        var cases: [CorpusManifest.Case] = []
        for (id, language, english) in [("hi-1", "hi", "I will come."), ("en-1", "en-US", nil)] {
            let url = root.appendingPathComponent("\(id).wav")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try AudioClip.tone(seconds: 1).write(to: url)
            cases.append(
                .init(
                    id: id, source: source.id, language: language,
                    audio: .init(path: "\(id).wav", sha256: try CorpusManifest.sha256(of: url), seconds: 1),
                    reference: "i will come", englishReference: english, category: "read", tags: ["numbers"],
                    review: .datasetHuman))
        }
        return CorpusManifest(
            name: "recordings", sources: [source], cases: cases,
            variants: [CorpusVariant(id: "noisy", transform: .noise, snrDecibels: 10, seed: 3)])
    }

    private func engine() -> FakeRecognitionEngine {
        FakeRecognitionEngine(
            id: .whisper, script: .init(text: "I will come"), supportedLanguages: ["en", "hi"],
            tasks: [.transcribe, .translateToEnglish])
    }

    @Test func theSharedFixtureDecodes() throws {
        let report = try EvaluationReport.load(from: Self.fixture)

        #expect(report.schema == EvaluationReport.schemaVersion)
        #expect(report.label == "fixture")
        #expect(report.runs.count == 9)
        #expect(report.runs.first { $0.id == "noise-loud@te" }?.result.score.textWithoutSpeech == true)
        #expect(report.runs.first { $0.id == "fleurs-hi_in-1~noise-snr10" }?.variantID == "noise-snr10")
    }

    @Test func aRealRunWritesExactlyTheFixturesKeys() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let selections = [
            CorpusEvaluation.Selection(manifestURL: try manifest("recordings.json", try recordings()), root: root),
            CorpusEvaluation.Selection(
                manifestURL: try manifest(
                    "edge.json",
                    CorpusManifest(
                        name: "edge",
                        generated: [
                            .init(id: "quiet", kind: .silence, seconds: 1, languages: ["hi"], category: "no-speech")
                        ])),
                root: root),
        ]

        let report = try await CorpusEvaluation.run(
            engine: engine(), selections: selections, label: "fake", workDirectory: root.appendingPathComponent("work"))
        let written = try report.write(to: root.appendingPathComponent("out"))

        let ours = try JSONSerialization.jsonObject(with: Data(contentsOf: written))
        let theirs = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixture))
        #expect(Self.keyPaths(ours) == Self.keyPaths(theirs))
        #expect(written.lastPathComponent == "fake-transcribe-clean.json")
        #expect(report.runs.map(\.id) == ["hi-1", "en-1", "hi-1~noisy", "en-1~noisy", "quiet@hi"])
        #expect(report.corpora.map(\.runs) == [4, 1])
        #expect(report.warmUpSeconds >= 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("work").path))
    }

    @Test func translationSkipsWhatCannotBeScoredAndSaysWhy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = CorpusEvaluation.Selection(
            manifestURL: try manifest("recordings.json", try recordings()), root: root)

        let report = try await CorpusEvaluation.run(
            engine: engine(), selections: [selection], task: .translateToEnglish,
            workDirectory: root.appendingPathComponent("work"))

        #expect(report.runs.map(\.id) == ["hi-1", "hi-1~noisy"])
        #expect(report.skipped == ["already-english": 2])
        #expect(report.task == "translate-to-english")
    }

    @Test func aLanguageFilterKeepsOnlyThoseLanguages() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = CorpusEvaluation.Selection(
            manifestURL: try manifest("recordings.json", try recordings()), root: root)

        let report = try await CorpusEvaluation.run(
            engine: engine(), selections: [selection], languages: ["en"],
            workDirectory: root.appendingPathComponent("work"))

        #expect(report.runs.map(\.id) == ["en-1", "en-1~noisy"])
    }

    @Test func reportsCarryNoSpokenOrReferenceText() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = CorpusEvaluation.Selection(
            manifestURL: try manifest("recordings.json", try recordings()), root: root)

        let report = try await CorpusEvaluation.run(
            engine: engine(), selections: [selection], workDirectory: root.appendingPathComponent("work"))
        let text = try String(contentsOf: try report.write(to: root.appendingPathComponent("out")), encoding: .utf8)

        #expect(!text.lowercased().contains("will come"))
    }
}
