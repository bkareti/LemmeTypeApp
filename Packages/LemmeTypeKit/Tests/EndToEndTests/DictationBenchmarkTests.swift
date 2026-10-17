import Domain
import Foundation
import TestSupport
import Testing

/// The benchmark harness itself (E2-S10): real `say` synthesis and noise, a
/// scripted engine, metrics only. Skipped where the voice isn't installed.
struct DictationBenchmarkTests {
    static let hasVoice: Bool = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "?"]
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return false }
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return output.contains("Samantha")
    }()

    @Test(.enabled(if: hasVoice)) func reportsMetricsWithoutTextOrAudio() async throws {
        let corpusJSON = """
            {"version": 99, "voices": [{"name": "Samantha", "accent": "en-US"}],
             "noise": {"snrDecibels": 10, "seed": 7},
             "utterances": [
               {"id": "a", "category": "conversational", "text": "Thanks for the update."},
               {"id": "b", "category": "numeric", "text": "Gate twenty three closes soon."}]}
            """
        let corpusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-Corpus-\(UUID().uuidString).json")
        try Data(corpusJSON.utf8).write(to: corpusURL)
        defer { try? FileManager.default.removeItem(at: corpusURL) }
        let corpus = try BenchmarkCorpus.load(from: corpusURL)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-Bench-\(UUID().uuidString)", isDirectory: true)
        let engine = FakeRecognitionEngine(id: .appleSpeech, script: .init(text: "thanks for the update"))

        let report = try await DictationBenchmark.run(engine: engine, corpus: corpus, workDirectory: work)

        #expect(report.sessions == 4)  // two sentences, each clean and noisy
        #expect(report.failedSessions == 0)
        #expect(report.corpusVersion == 99)
        #expect(report.wordErrorRateByCategory["conversational"] == 0)
        #expect((report.wordErrorRateByCategory["numeric"] ?? 0) > 0)
        #expect(report.audioSeconds.mean > 0.5)
        #expect(report.stopToDeliverySeconds.mean >= report.inferenceSeconds.mean)
        #expect(!FileManager.default.fileExists(atPath: work.path))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-BenchOut-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }
        try DictationBenchmark.write(report, to: output)
        let written =
            try String(contentsOf: output.appendingPathComponent("apple-speech.json"), encoding: .utf8)
            + String(contentsOf: output.appendingPathComponent("apple-speech.md"), encoding: .utf8)
        #expect(!written.contains("update"))
        #expect(!written.contains("twenty"))
        #expect(written.contains("stopToDeliverySeconds"))
    }
}
