import CryptoKit
import Domain
import Foundation
import Synchronization
import Testing

@testable import ModelAssets

/// Scripted transfers: each call consumes the next step.
final class FakeModelDownloader: ModelDownloading {
    enum Step {
        case deliver(Data)
        case pause(resumeData: Data?)
        case fail(code: Int, resumeData: Data?)
    }

    private let steps: Mutex<[Step]>
    private let calls = Mutex<[Data?]>([])
    private let pauses = Mutex(0)

    init(_ steps: [Step]) {
        self.steps = Mutex(steps)
    }

    /// Resume data passed to each call.
    var resumeDataPerCall: [Data?] { calls.withLock { $0 } }
    var pauseCount: Int { pauses.withLock { $0 } }

    func download(
        from url: URL,
        resumeData: Data?,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws(ModelDownloadFailure) {
        calls.withLock { $0.append(resumeData) }
        let step = steps.withLock { $0.isEmpty ? Step.fail(code: -1, resumeData: nil) : $0.removeFirst() }
        switch step {
        case .deliver(let data):
            progress(Int64(data.count / 2), Int64(data.count))
            do {
                try data.write(to: destination)
            } catch {
                throw .failed(code: -2, resumeData: nil)
            }
            progress(Int64(data.count), Int64(data.count))
        case .pause(let data):
            throw .cancelled(resumeData: data)
        case .fail(let code, let data):
            throw .failed(code: code, resumeData: data)
        }
    }

    func pause(_ url: URL) async {
        pauses.withLock { $0 += 1 }
    }
}

final class StateLog: Sendable {
    private let states = Mutex<[ModelInstallState]>([])
    var all: [ModelInstallState] { states.withLock { $0 } }
    func append(_ state: ModelInstallState) { states.withLock { $0.append(state) } }
}

struct ModelAssetStoreTests {
    static let content = Data("pretend this is a speech model".utf8)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LemmeTypeTests-Models-\(UUID().uuidString)", isDirectory: true)

    static func asset(content: Data = content, sha256: String? = nil, host: String = "huggingface.co") -> ModelAsset {
        let digest = sha256 ?? SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        return ModelAsset(
            id: ModelAssetID(rawValue: "test-model"),
            displayName: "Test Model",
            version: "1",
            engine: .whisper,
            files: [
                ModelFile(
                    name: "model.bin",
                    url: URL(string: "https://\(host)/test/model.bin") ?? URL(fileURLWithPath: "/"),
                    sha256: digest,
                    bytes: Int64(content.count))
            ],
            languages: ["en"],
            license: "MIT",
            licenseURL: URL(fileURLWithPath: "/LICENSE"),
            hardware: HardwareRequirement(requiresAppleSilicon: false, minimumMemoryBytes: 0)
        )
    }

    func makeStore(
        _ downloader: FakeModelDownloader,
        asset: ModelAsset = Self.asset(),
        freeSpace: Int64 = 10_000_000_000,
        retryDelays: [Duration] = [],
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) -> ModelAssetStore {
        ModelAssetStore(
            root: root, downloader: downloader, catalog: [asset], freeSpace: { _ in freeSpace },
            retryDelays: retryDelays, sleep: { _ in }, diagnostics: diagnostics)
    }

    private var consent: ModelDownloadConsent { ModelDownloadConsent(asset: Self.asset()) }

    private func filesUnderRoot() -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        var files: [String] = []
        while let next = enumerator?.nextObject() as? String {
            files.append(next)
        }
        return files
    }

    @Test func downloadVerifiesAndActivates() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(FakeModelDownloader([.deliver(Self.content)]))
        let log = StateLog()

        let result = try await store.install(consent) { log.append($0) }

        #expect(result == .installed)
        #expect(await store.state(of: Self.asset().id) == .installed)
        let file = try #require(await store.installedFile(for: Self.asset().id, named: "model.bin"))
        #expect(try Data(contentsOf: file) == Self.content)
        #expect(log.all.first == .downloading(receivedBytes: 0, totalBytes: Int64(Self.content.count)))
        #expect(log.all.contains(.verifying))
        #expect(log.all.last == .installed)
        #expect(!filesUnderRoot().contains { $0.hasPrefix("Staging/test-model/") })
    }

    @Test func downloadNeedsConsentMatchingTheShownSize() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([.deliver(Self.content)])
        let store = makeStore(downloader)

        await #expect(throws: ModelAssetError.consentRequired) {
            try await store.install(ModelDownloadConsent(asset: Self.asset().id, acknowledgedBytes: 1)) { _ in }
        }
        #expect(downloader.resumeDataPerCall.isEmpty)
    }

    @Test func untrustedSourcesAreRejected() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = Self.asset(host: "example.com")
        let downloader = FakeModelDownloader([.deliver(Self.content)])
        let store = makeStore(downloader, asset: asset)

        await #expect(throws: ModelAssetError.untrustedSource) {
            try await store.install(ModelDownloadConsent(asset: asset)) { _ in }
        }
        #expect(downloader.resumeDataPerCall.isEmpty)
    }

    @Test func insufficientStorageNeverStartsAndReportsTheRequiredSpace() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([.deliver(Self.content)])
        let store = makeStore(downloader, freeSpace: 1_000)

        await #expect(
            throws: ModelAssetError.insufficientStorage(
                requiredBytes: Self.asset().requiredFreeBytes, availableBytes: 1_000)
        ) {
            try await store.install(consent) { _ in }
        }
        #expect(downloader.resumeDataPerCall.isEmpty)
    }

    @Test func digestMismatchDeletesTheFileAndIsRecoverable() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tampered = Data("pretend this is a speech modeX".utf8)  // same length, different bytes
        let downloader = FakeModelDownloader([.deliver(tampered), .deliver(Self.content)])
        let store = makeStore(downloader)

        await #expect(throws: ModelAssetError.digestMismatch) {
            try await store.install(consent) { _ in }
        }
        #expect(await store.state(of: Self.asset().id) == .notInstalled)
        #expect(await store.installedFile(for: Self.asset().id, named: "model.bin") == nil)
        #expect(!filesUnderRoot().contains { $0.hasSuffix("model.bin") })

        // Retry succeeds.
        #expect(try await store.install(consent) { _ in } == .installed)
    }

    @Test func sizeMismatchIsRejected() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(FakeModelDownloader([.deliver(Data("short".utf8))]))
        await #expect(throws: ModelAssetError.sizeMismatch) {
            try await store.install(consent) { _ in }
        }
        #expect(await store.state(of: Self.asset().id) == .notInstalled)
    }

    @Test func pausedDownloadResumesWithItsResumeData() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let resume = Data("resume-token".utf8)
        let downloader = FakeModelDownloader([.pause(resumeData: resume), .deliver(Self.content)])
        let store = makeStore(downloader)

        let first = try await store.install(consent) { _ in }
        guard case .paused = first else {
            Issue.record("expected paused, got \(first)")
            return
        }
        guard case .paused = await store.state(of: Self.asset().id) else {
            Issue.record("paused state not kept")
            return
        }
        #expect(await store.installedFile(for: Self.asset().id, named: "model.bin") == nil)

        #expect(try await store.install(consent) { _ in } == .installed)
        #expect(downloader.resumeDataPerCall == [nil, resume])
    }

    @Test func staleResumeDataRestartsFromScratch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([
            .pause(resumeData: Data("stale".utf8)),
            .fail(code: -3003, resumeData: nil),
            .deliver(Self.content),
        ])
        let store = makeStore(downloader)

        _ = try await store.install(consent) { _ in }
        #expect(try await store.install(consent) { _ in } == .installed)
        #expect(downloader.resumeDataPerCall == [nil, Data("stale".utf8), nil])
    }

    @Test func interruptedDownloadIsNeverTreatedAsInstalled() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(FakeModelDownloader([.fail(code: -1005, resumeData: nil)]))

        await #expect(throws: ModelAssetError.downloadFailed(code: -1005)) {
            try await store.install(consent) { _ in }
        }
        #expect(await store.state(of: Self.asset().id) == .notInstalled)
        #expect(await store.installedFile(for: Self.asset().id, named: "model.bin") == nil)
    }

    @Test func removeDeletesManagedFilesOnly() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(FakeModelDownloader([.deliver(Self.content)]))
        try await store.install(consent) { _ in }
        let unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)

        try await store.remove(Self.asset().id)

        #expect(await store.state(of: Self.asset().id) == .notInstalled)
        #expect(await store.installedFile(for: Self.asset().id, named: "model.bin") == nil)
        #expect(filesUnderRoot().filter { !$0.hasPrefix("Staging") } == ["unrelated.txt"])
    }

    @Test func stateSurvivesANewStoreInstance() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await makeStore(FakeModelDownloader([.deliver(Self.content)])).install(consent) { _ in }
        #expect(await makeStore(FakeModelDownloader([])).state(of: Self.asset().id) == .installed)
    }

    @Test func outdatedVersionsAreRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("test-model/0", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appendingPathComponent("model.bin"))
        let store = makeStore(FakeModelDownloader([]))

        await store.removeUnusableFiles()

        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func fileDigestMatchesCryptoKit() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("digest.bin")
        try Self.content.write(to: url)
        #expect(try FileDigest.sha256(of: url) == Self.asset().files[0].sha256)
    }

    // MARK: E5-S3 — verification before use and recovery

    @Test func verifiedFileChecksOncePerLaunchUntilTheFileChanges() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = CountingDiagnostics()
        let store = makeStore(FakeModelDownloader([.deliver(Self.content)]), diagnostics: diagnostics)
        try await store.install(consent) { _ in }

        let url = try #require(await store.verifiedFile(for: Self.asset().id, named: "model.bin"))
        #expect(await store.verifiedFile(for: Self.asset().id, named: "model.bin") == url)
        #expect(diagnostics.count(of: "model.verified") == 1)
    }

    @Test func modifiedFileIsDeletedAndNeverReturned() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(FakeModelDownloader([.deliver(Self.content), .deliver(Self.content)]))
        try await store.install(consent) { _ in }
        let url = try #require(await store.installedFile(for: Self.asset().id, named: "model.bin"))
        // Same size, different bytes: only the digest can tell.
        var tampered = Self.content
        tampered[0] ^= 0xFF
        try tampered.write(to: url)

        #expect(await store.verifiedFile(for: Self.asset().id, named: "model.bin") == nil)
        #expect(await store.installedFile(for: Self.asset().id, named: "model.bin") == nil)
        #expect(await store.state(of: Self.asset().id) == .failed(.digestMismatch))

        // A fresh download clears it.
        try await store.install(consent) { _ in }
        #expect(await store.state(of: Self.asset().id) == .installed)
        #expect(await store.verifiedFile(for: Self.asset().id, named: "model.bin") != nil)
    }

    @Test func transientFailuresRetryFromTheResumePoint() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let partial = Data("partial".utf8)
        let downloader = FakeModelDownloader([.fail(code: -1005, resumeData: partial), .deliver(Self.content)])
        let store = makeStore(downloader, retryDelays: [.seconds(2), .seconds(5)])

        #expect(try await store.install(consent) { _ in } == .installed)
        #expect(downloader.resumeDataPerCall == [nil, partial])
    }

    @Test func retriesStopAfterTwoAndKeepResumableProgress() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([
            .fail(code: -1001, resumeData: Data("a".utf8)), .fail(code: -1009, resumeData: Data("b".utf8)),
            .fail(code: -1005, resumeData: Data("c".utf8)),
        ])
        let store = makeStore(downloader, retryDelays: [.seconds(2), .seconds(5)])

        await #expect(throws: ModelAssetError.downloadFailed(code: -1005)) {
            try await store.install(consent) { _ in }
        }
        #expect(downloader.resumeDataPerCall.count == 3)
        // Resume is offered and continues from the saved point.
        guard case .paused = await store.state(of: Self.asset().id) else {
            Issue.record("expected a paused, resumable download")
            return
        }
    }

    @Test func permanentFailuresAreNotRetried() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([.fail(code: 404, resumeData: nil), .deliver(Self.content)])
        let store = makeStore(downloader, retryDelays: [.seconds(2)])
        await #expect(throws: ModelAssetError.downloadFailed(code: 404)) {
            try await store.install(consent) { _ in }
        }
        #expect(downloader.resumeDataPerCall.count == 1)
    }

    @Test func pausedProgressSurvivesARelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeModelDownloader([.pause(resumeData: Data("resume".utf8)), .deliver(Self.content)])
        _ = try await makeStore(downloader).install(consent) { _ in }

        let relaunched = makeStore(downloader)
        guard case .paused = await relaunched.state(of: Self.asset().id) else {
            Issue.record("expected paused after relaunch")
            return
        }
        #expect(try await relaunched.install(consent) { _ in } == .installed)
        #expect(downloader.resumeDataPerCall.last == Data("resume".utf8))
    }
}

/// Counts diagnostics events by name.
final class CountingDiagnostics: DiagnosticsRecording {
    private let names = Mutex<[String]>([])

    func record(
        _ category: DiagnosticCategory, _ name: StaticString, _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {
        names.withLock { $0.append(name.description) }
    }

    func count(of name: String) -> Int { names.withLock { $0.filter { $0 == name }.count } }
}
