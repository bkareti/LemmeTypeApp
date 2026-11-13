import Domain
import Foundation
import Testing

/// The JSON files in `shared/fixtures/` describe rules that the Android app
/// (`android/`) implements again in Kotlin (ADR 0035, E14-S7). These tests
/// check that the files say exactly what the Swift code does, so a change on
/// either side fails one of the two test suites instead of drifting.
struct SharedFixturesTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures", isDirectory: true)

    static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Cleanup corpus

    static let corpus: [CleanupCase] =
        (try? load("cleanup-corpus.json", as: CleanupCorpus.self))?.cases ?? []

    @Test func corpusIsPresent() throws {
        let corpus = try Self.load("cleanup-corpus.json", as: CleanupCorpus.self)
        #expect(corpus.cases.count >= 39)
        #expect(Set(corpus.cases.flatMap(\.rules)) == Set(CleanupRule.allCases.map(\.rawValue)))
    }

    @Test(arguments: corpus)
    func cleanWritingMatchesTheSharedCorpus(_ testCase: CleanupCase) {
        let result = TextCleaner().apply(testCase.input, mode: .clean)
        #expect(result.text == testCase.clean)
        #expect(Set(result.transformations.map(\.rule.rawValue)) == Set(testCase.rules))
    }

    @Test(arguments: corpus)
    func exactDictationKeepsTheSharedCorpusWords(_ testCase: CleanupCase) {
        #expect(TextCleaner().apply(" " + testCase.input + "  ", mode: .exact).text == testCase.input)
    }

    @Test func whitespaceAndTransformationsMatch() throws {
        let corpus = try Self.load("cleanup-corpus.json", as: CleanupCorpus.self)
        for item in corpus.whitespace {
            #expect(TextCleaner.normalizeWhitespace(item.input) == item.exact)
        }
        for item in corpus.transformations {
            let changes = TextCleaner().apply(item.input, mode: .clean).transformations.map {
                CleanupChange(rule: $0.rule.rawValue, before: $0.before, after: $0.after)
            }
            #expect(changes == item.expected)
        }
        let input = "um " + corpus.protected.joined(separator: " um ")
        let output = TextCleaner().apply(input, mode: .clean).text
        for token in corpus.protected {
            #expect(output.contains(token))
        }
    }

    // MARK: Recorder transitions

    static let sampleError = AudioCaptureError.interrupted
    static let sampleIssue = DictationIssue.reviewText

    static func name(of state: RecorderState) -> String {
        switch state {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .stopping: "stopping"
        case .processing: "processing"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed: "failed"
        case .needsAttention: "needs-attention"
        }
    }

    static func name(of event: RecorderEvent) -> String {
        switch event {
        case .activate: "activate"
        case .captureStarted: "capture-started"
        case .stopRequested: "stop-requested"
        case .captureFinished: "capture-finished"
        case .processingFinished: "processing-finished"
        case .cancel: "cancel"
        case .fail: "fail"
        case .processingNeedsAttention: "processing-needs-attention"
        case .retry: "retry"
        case .reset: "reset"
        }
    }

    static let states: [RecorderState] = [
        .idle, .preparing, .recording, .stopping, .processing, .completed, .cancelled, .failed(sampleError),
        .needsAttention(sampleIssue),
    ]
    static let events: [RecorderEvent] = [
        .activate, .captureStarted, .stopRequested, .captureFinished, .processingFinished, .cancel,
        .fail(sampleError), .processingNeedsAttention(sampleIssue), .retry, .reset,
    ]

    @Test func recorderTransitionsMatchTheSharedTable() throws {
        let table = try Self.load("recorder-transitions.json", as: SharedTransitions.self)
        #expect(table.states == Self.states.map(Self.name(of:)))
        #expect(table.events == Self.events.map(Self.name(of:)))
        #expect(table.transitions.count == Self.states.count * Self.events.count)
        for row in table.transitions {
            let state = try #require(Self.states.first { Self.name(of: $0) == row.from })
            let event = try #require(Self.events.first { Self.name(of: $0) == row.event })
            let next = RecorderStateMachine.transition(from: state, on: event)
            #expect(next.map(Self.name(of:)) == row.next, "\(row.from) + \(row.event)")
        }
    }

    // MARK: Model catalog

    @Test func modelCatalogMatchesTheSharedPins() throws {
        let catalog = try Self.load("model-catalog.json", as: SharedCatalog.self)
        let swift = ModelCatalog.all.map { asset in
            SharedModel(
                id: asset.id.rawValue, displayName: asset.displayName, version: asset.version,
                engine: asset.engine.rawValue,
                files: asset.files.map {
                    SharedModelFile(name: $0.name, url: $0.url.absoluteString, sha256: $0.sha256, bytes: $0.bytes)
                },
                languages: asset.languages, tasks: asset.tasks.map(\.rawValue).sorted(), tier: asset.tier.rawValue,
                runtimeMemoryBytes: asset.runtimeMemoryBytes, license: asset.license)
        }
        #expect(catalog.models == swift)
        #expect(Set(catalog.allowedHosts) == ModelCatalog.allowedHosts)
    }

    // MARK: Recognition errors

    // One case per error, so a new error does not compile until it is named here and in the fixture.
    // swiftlint:disable:next cyclomatic_complexity
    static func name(of error: RecognitionError) -> String {
        switch error {
        case .cancelled: "cancelled"
        case .assetsMissing: "assets-missing"
        case .unsupported: "unsupported"
        case .permissionDenied: "permission-denied"
        case .audioUnreadable: "audio-unreadable"
        case .noSpeechDetected: "no-speech-detected"
        case .silentAudio: "silent-audio"
        case .modelLoadFailed: "model-load-failed"
        case .languageUncertain: "language-uncertain"
        case .engineFailure: "engine-failure"
        case .cloudOffline: "cloud-offline"
        case .cloudKeyRejected: "cloud-key-rejected"
        case .subscriptionRequired: "subscription-required"
        case .cloudRateLimited: "cloud-rate-limited"
        case .cloudQuotaExhausted: "cloud-quota-exhausted"
        case .cloudServiceFailed: "cloud-service-failed"
        case .cloudUnavailable: "cloud-unavailable"
        }
    }

    static let errors: [RecognitionError] = [
        .cancelled, .assetsMissing, .unsupported(.language), .permissionDenied, .audioUnreadable, .noSpeechDetected,
        .silentAudio, .modelLoadFailed, .languageUncertain, .engineFailure(code: 1), .cloudOffline, .cloudKeyRejected,
        .subscriptionRequired, .cloudRateLimited, .cloudQuotaExhausted, .cloudServiceFailed, .cloudUnavailable,
    ]

    @Test func recognitionErrorsMatchTheSharedList() throws {
        let shared = try Self.load("recognition-errors.json", as: SharedErrors.self).errors
        let swift = Self.errors.map {
            SharedError(case: Self.name(of: $0), identifier: $0.identifier, retryable: $0.isRetryable)
        }
        #expect(shared == swift)
    }
}

// MARK: Fixture shapes

struct CleanupCase: Decodable, Sendable, CustomTestStringConvertible {
    let category: String
    let input: String
    let clean: String
    let rules: [String]
    var testDescription: String { "\(category): \(input)" }
}

private struct CleanupWhitespace: Decodable {
    let input: String
    let exact: String
}

private struct CleanupChange: Decodable, Equatable {
    let rule: String
    let before: String
    let after: String
}

private struct CleanupTransformationCase: Decodable {
    let input: String
    let expected: [CleanupChange]
}

private struct CleanupCorpus: Decodable {
    let cases: [CleanupCase]
    let whitespace: [CleanupWhitespace]
    let transformations: [CleanupTransformationCase]
    let protected: [String]
}

private struct SharedTransition: Decodable {
    let from: String
    let event: String
    /// `null` means the transition is rejected.
    let next: String?

    enum CodingKeys: String, CodingKey {
        case from, event
        case next = "to"
    }
}

private struct SharedTransitions: Decodable {
    let states: [String]
    let events: [String]
    let transitions: [SharedTransition]
}

private struct SharedModelFile: Decodable, Equatable {
    let name: String
    let url: String
    let sha256: String
    let bytes: Int64
}

private struct SharedModel: Decodable, Equatable {
    let id: String
    let displayName: String
    let version: String
    let engine: String
    let files: [SharedModelFile]
    let languages: [String]
    let tasks: [String]
    let tier: String
    let runtimeMemoryBytes: UInt64
    let license: String
}

private struct SharedCatalog: Decodable {
    let allowedHosts: [String]
    let models: [SharedModel]
}

private struct SharedError: Decodable, Equatable {
    let `case`: String
    let identifier: String
    let retryable: Bool
}

private struct SharedErrors: Decodable {
    let errors: [SharedError]
}
