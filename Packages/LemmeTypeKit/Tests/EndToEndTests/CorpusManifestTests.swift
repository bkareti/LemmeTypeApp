import Domain
import Foundation
import TestSupport
import Testing

/// The corpus manifest: validation, SHA-256 checks before anything is scored,
/// generated no-speech cases, variants that keep the reference, and the
/// committed manifests in `docs/testing/corpus/`.
struct CorpusManifestTests {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Corpus-\(UUID().uuidString)", isDirectory: true)

    private var corpus: URL { root.appendingPathComponent("corpus", isDirectory: true) }
    private var work: URL { root.appendingPathComponent("work", isDirectory: true) }

    static let source = CorpusManifest.Source(
        id: "test", title: "Test", license: "CC0-1.0", licenseURL: "https://example.org", url: "https://example.org",
        revision: "1", attribution: "Made for tests")

    private func recording(
        _ id: String, _ clip: AudioClip = .tone(seconds: 1), review: CorpusManifest.Review = .datasetHuman
    )
        throws -> CorpusManifest.Case
    {
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        let url = corpus.appendingPathComponent("\(id).wav")
        try clip.write(to: url)
        let digest = try CorpusManifest.sha256(of: url)
        return CorpusManifest.Case(
            id: id, source: "test", language: "hi",
            audio: .init(path: "\(id).wav", sha256: digest, seconds: clip.duration), reference: "मैं कल आऊँगा।",
            englishReference: "I will come tomorrow.", category: "read", tags: ["fixture"], review: review)
    }

    private func engine(_ text: String) -> FakeRecognitionEngine {
        FakeRecognitionEngine(
            id: .whisper, script: .init(text: text), supportedLanguages: ["en", "hi", "te", "kn", "ta"],
            tasks: [.transcribe, .translateToEnglish])
    }

    @Test func theCommittedManifestsAreValid() throws {
        let folder = Self.repositoryRoot.appendingPathComponent("docs/testing/corpus", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
        #expect(names.contains("edge-cases.json"))
        #expect(names.contains("variants.json"))
        for name in names {
            let manifest = try CorpusManifest.load(from: folder.appendingPathComponent(name))
            #expect(manifest.problems().isEmpty, "\(name): \(manifest.problems())")
        }
        let edgeCases = try CorpusManifest.load(from: folder.appendingPathComponent("edge-cases.json"))
        let items = try edgeCases.items(root: root)
        #expect(items.count == 40)
        #expect(items.allSatisfy { $0.reference.isEmpty && $0.review == .byConstruction })
    }

    @Test func problemsNameEveryBrokenRule() throws {
        let good = try recording("a")
        let manifest = CorpusManifest(
            name: "broken", sources: [Self.source],
            cases: [
                good,
                .init(
                    id: "a", source: "elsewhere", language: "hi",
                    audio: .init(path: "../a.wav", sha256: "ABC", seconds: 1),
                    reference: "", englishReference: nil, category: "read", tags: [], review: .datasetHuman),
            ],
            variants: [CorpusVariant(id: "fast", transform: .speed, factor: 3)])
        let problems = manifest.problems()

        #expect(problems.contains("duplicate id a"))
        #expect(problems.contains("a: unknown source elsewhere"))
        #expect(problems.contains("a: sha256 is not 64 hex digits"))
        #expect(problems.contains("a: audio path must stay inside the corpus root"))
        #expect(problems.contains("a: a recording needs a human reference"))
        #expect(problems.contains("fast: speed needs a factor in 0.5…2, not 1"))
        #expect(throws: CorpusManifest.CorpusError.invalidManifest(problems)) { try manifest.items(root: corpus) }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aChangedOrMissingRecordingIsNeverScored() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try recording("a")
        let manifest = CorpusManifest(name: "t", sources: [Self.source], cases: [item])
        #expect(try manifest.items(root: corpus).count == 1)

        try AudioClip.tone(seconds: 2).write(to: corpus.appendingPathComponent("a.wav"))
        #expect(throws: CorpusManifest.CorpusError.checksumMismatch(caseID: "a")) { try manifest.items(root: corpus) }
        try FileManager.default.removeItem(at: corpus.appendingPathComponent("a.wav"))
        #expect(throws: CorpusManifest.CorpusError.missingAudio(caseID: "a")) { try manifest.items(root: corpus) }
    }

    @Test func unverifiedReferencesAreSkippedUnlessAskedFor() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = CorpusManifest(
            name: "t", sources: [Self.source],
            cases: [try recording("human"), try recording("model", review: .unverified)])

        #expect(try manifest.items(root: corpus).map(\.id) == ["human"])
        #expect(try manifest.items(root: corpus, includeUnverified: true).map(\.id) == ["human", "model"])
    }

    @Test func variantsSampleRecordingsAndKeepTheirReferences() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = CorpusManifest(
            name: "t", sources: [Self.source], cases: [try recording("a"), try recording("b"), try recording("c")],
            variants: [
                CorpusVariant(id: "noisy", transform: .noise, snrDecibels: 10, seed: 7),
                CorpusVariant(id: "long", transform: .repeat, count: 2, gap: 0.5, sampleEvery: 2),
            ])
        let items = try manifest.items(root: corpus)

        #expect(items.map(\.id) == ["a", "b", "c", "a~noisy", "b~noisy", "c~noisy", "a~long", "c~long"])
        let noisy = try #require(items.first { $0.id == "a~noisy" })
        #expect(noisy.reference == "मैं कल आऊँगा।")
        #expect(noisy.variantID == "noisy")
        #expect(noisy.tags.contains("variant:noise"))
        let long = try #require(items.first { $0.id == "a~long" })
        #expect(long.reference == "मैं कल आऊँगा। मैं कल आऊँगा।")
        #expect(long.englishReference == "I will come tomorrow. I will come tomorrow.")
    }

    @Test func itemsRunThroughThePipelineAndLeaveNothingBehind() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = CorpusManifest(
            name: "t", sources: [Self.source], cases: [try recording("a", .tone(seconds: 1.5))],
            generated: [
                .init(
                    id: "quiet", kind: .silence, seconds: 1, amplitude: nil, seed: nil, languages: ["hi"],
                    category: "no-speech")
            ],
            variants: [CorpusVariant(id: "late", transform: .pad, leading: 1, trailing: 2)])
        let runner = EvaluationRunner(engine: engine("मैं कल आऊँगा"), workDirectory: work)
        var results: [String: EvaluationResult] = [:]

        for item in try manifest.items(root: corpus) {
            results[item.id] = try await item.run(with: runner, workDirectory: work)
        }

        #expect(results["a"]?.score.wordErrorRate == 0)
        #expect(abs((results["a~late"]?.audioSeconds ?? 0) - 4.5) < 0.01)
        #expect(results["a~late"]?.score.wordErrorRate == 0)
        #expect(results["quiet@hi"]?.score.textWithoutSpeech == true)  // the fake always "hears" speech
        #expect(FileManager.default.fileExists(atPath: corpus.appendingPathComponent("a.wav").path))
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? []).isEmpty)
    }

    @Test func aTranslationRunUsesTheHumanEnglishReference() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = CorpusManifest(name: "t", sources: [Self.source], cases: [try recording("a")])
        let runner = EvaluationRunner(engine: engine("I will come tomorrow"), workDirectory: work)

        let result = try await #require(try manifest.items(root: corpus).first)
            .run(with: runner, workDirectory: work, task: .translateToEnglish)

        #expect(result.outcome == "review.translation")
        #expect(result.score.wordErrorRate == 0)
    }

    @Test func speedChangesTheLengthAndKeepsTheSampleRate() {
        let tone = AudioClip.tone(seconds: 2)
        #expect(abs(tone.speed(1.1).duration - 2 / 1.1) < 0.001)
        #expect(abs(tone.speed(0.9).duration - 2 / 0.9) < 0.001)
        #expect(tone.speed(0.9).sampleRate == tone.sampleRate)
        #expect(tone.speed(1) == tone)
        #expect(tone.speed(1.1) == tone.speed(1.1))
    }
}

/// Opt-in: checks a fetched corpus on this Mac against the committed manifest, so the
/// Swift checksum check and `scripts/corpus.py verify` agree on real recordings.
///
///     LEMMETYPE_CORPUS_ROOT=~/Library/Caches/LemmeTypeCorpus/fleurs/<revision> \
///       swift test --package-path Packages/LemmeTypeKit --filter CorpusOnDiskTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LEMMETYPE_CORPUS_ROOT"] != nil))
struct CorpusOnDiskTests {
    @Test func everyFleursRecordingMatchesItsManifest() async throws {
        let root = URL(
            fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LEMMETYPE_CORPUS_ROOT"]),
            isDirectory: true)
        let manifest = try CorpusManifest.load(
            from: CorpusManifestTests.repositoryRoot.appendingPathComponent("docs/testing/corpus/fleurs.json"))

        let items = try manifest.items(root: root)

        let recordings = items.filter { $0.variantID == nil }
        #expect(recordings.count == manifest.cases.count)
        #expect(recordings.allSatisfy { $0.review == .datasetHuman && !$0.reference.isEmpty })
        #expect(items.count > recordings.count)  // variants are sampled too

        // FLEURS stores 32-bit float WAVE; one real recording goes through the pipeline at full length.
        let first = try #require(recordings.first)
        let expected = try #require(manifest.cases.first { $0.id == first.id }).audio.seconds
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-CorpusOnDisk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let engine = FakeRecognitionEngine(id: .whisper, script: .init(text: "x"), supportedLanguages: ["hi", "te"])
        let result = try await first.run(
            with: EvaluationRunner(engine: engine, workDirectory: work), workDirectory: work)
        #expect(abs(result.audioSeconds - expected) < 0.001)
        #expect(result.producedText)
    }
}
