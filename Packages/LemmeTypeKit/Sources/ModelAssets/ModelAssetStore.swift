import Domain
import Foundation
import Support
import Synchronization

/// Downloads, verifies, activates, and removes catalog models.
///
/// Layout under `root` (Application Support/LemmeType/Models by default):
/// - `Staging/<asset>/` — files being downloaded or verified, plus resume data.
///   Nothing here is ever used for recognition.
/// - `<asset>/<version>/` — the active, verified files and a `.verified` marker.
///
/// A file moves from staging to active only after its size and SHA-256 match
/// the version-controlled ``ModelCatalog``; mismatches are deleted.
public actor ModelAssetStore: ModelAssetManaging {
    public let root: URL
    private let downloader: any ModelDownloading
    private let catalog: [ModelAsset]
    private let freeSpace: @Sendable (URL) -> Int64
    private let diagnostics: any DiagnosticsRecording
    private var transient: [ModelAssetID: ModelInstallState] = [:]

    public init(
        root: URL,
        downloader: any ModelDownloading,
        catalog: [ModelAsset] = ModelCatalog.all,
        freeSpace: @escaping @Sendable (URL) -> Int64 = ModelAssetStore.volumeFreeSpace,
        diagnostics: any DiagnosticsRecording = DiscardingDiagnostics()
    ) {
        self.root = root
        self.downloader = downloader
        self.catalog = catalog
        self.freeSpace = freeSpace
        self.diagnostics = diagnostics
    }

    public static func makeDefault(diagnostics: any DiagnosticsRecording) -> ModelAssetStore {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ModelAssetStore(
            root: support.appendingPathComponent("LemmeType/Models", isDirectory: true),
            downloader: URLSessionModelDownloader(),
            diagnostics: diagnostics
        )
    }

    // MARK: State

    public func state(of id: ModelAssetID) -> ModelInstallState {
        if let state = transient[id] { return state }
        guard let asset = catalog.first(where: { $0.id == id }) else { return .notInstalled }
        if isActive(asset) { return .installed }
        let staged = stagedBytes(asset)
        return staged > 0 || hasResumeData(asset)
            ? .paused(receivedBytes: staged, totalBytes: asset.downloadBytes) : .notInstalled
    }

    public func installedFile(for id: ModelAssetID, named name: String) -> URL? {
        guard let asset = catalog.first(where: { $0.id == id }), isActive(asset),
            asset.files.contains(where: { $0.name == name })
        else { return nil }
        return activeDirectory(asset).appendingPathComponent(name)
    }

    public func availableBytes() -> Int64 {
        freeSpace(existingAncestor(of: root))
    }

    // MARK: Install

    @discardableResult
    public func install(
        _ consent: ModelDownloadConsent,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState {
        guard let asset = catalog.first(where: { $0.id == consent.asset }) else { throw .unknownAsset }
        guard consent.isValid(for: asset) else { throw .consentRequired }
        guard asset.files.allSatisfy({ ModelCatalog.isTrustedSource($0.url) }) else { throw .untrustedSource }
        if transient[asset.id]?.isBusy == true { throw .alreadyInProgress }
        if isActive(asset) {
            progress(.installed)
            return .installed
        }
        let available = availableBytes()
        let required = asset.requiredFreeBytes - stagedBytes(asset)
        guard available >= required else {
            let error = ModelAssetError.insufficientStorage(requiredBytes: required, availableBytes: available)
            fail(asset, error, progress: progress)
            throw error
        }
        diagnostics.record(.models, "model.download-started", ["asset": .id(asset.id.rawValue)])

        do {
            try createDirectory(stagingDirectory(asset))
        } catch {
            fail(asset, error, progress: progress)
            throw error
        }

        var completedBytes: Int64 = 0
        for file in asset.files {
            let staged = stagedFile(asset, file)
            if !FileManager.default.fileExists(atPath: staged.path) {
                let outcome = await transfer(asset, file, completedBytes: completedBytes, progress: progress)
                switch outcome {
                case .finished:
                    break
                case .paused(let received):
                    return set(asset, .paused(receivedBytes: received, totalBytes: asset.downloadBytes), progress)
                case .failed(let error):
                    fail(asset, error, progress: progress)
                    throw error
                }
            }
            completedBytes += file.bytes
        }

        set(asset, .verifying, progress)
        for file in asset.files {
            if let error = verify(stagedFile(asset, file), against: file) {
                try? FileManager.default.removeItem(at: stagedFile(asset, file))
                fail(asset, error, progress: progress)
                throw error
            }
        }
        do {
            try activate(asset)
        } catch {
            fail(asset, error, progress: progress)
            throw error
        }
        transient[asset.id] = nil
        diagnostics.record(.models, "model.installed", ["asset": .id(asset.id.rawValue)])
        Log.models.info("Model installed: \(asset.id.rawValue, privacy: .public)")
        progress(.installed)
        return .installed
    }

    public func pause(_ id: ModelAssetID) async {
        guard let asset = catalog.first(where: { $0.id == id }) else { return }
        for file in asset.files {
            await downloader.pause(file.url)
        }
    }

    // MARK: Remove

    public func remove(_ id: ModelAssetID) async throws(ModelAssetError) {
        guard let asset = catalog.first(where: { $0.id == id }) else { throw .unknownAsset }
        if transient[id]?.isBusy == true {
            await pause(id)
        }
        let manager = FileManager.default
        for directory in [assetDirectory(asset), stagingDirectory(asset)]
        where manager.fileExists(atPath: directory.path) {
            do {
                try manager.removeItem(at: directory)
            } catch {
                throw .storageFailure
            }
        }
        transient[id] = nil
        diagnostics.record(.models, "model.removed", ["asset": .id(asset.id.rawValue)])
        Log.models.info("Model removed: \(asset.id.rawValue, privacy: .public)")
    }

    /// Deletes files that can never be used: staged files without resume data
    /// that failed verification earlier, and versions no longer in the catalog.
    public func removeUnusableFiles() {
        let manager = FileManager.default
        for asset in catalog {
            let directory = assetDirectory(asset)
            let versions = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
            for version in versions where version != asset.version {
                try? manager.removeItem(at: directory.appendingPathComponent(version))
            }
        }
        let known = Set(catalog.map(\.id.rawValue))
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        for name in (try? manager.contentsOfDirectory(atPath: staging.path)) ?? [] where !known.contains(name) {
            try? manager.removeItem(at: staging.appendingPathComponent(name))
        }
    }

    // MARK: Transfer

    private enum TransferOutcome {
        case finished
        case paused(receivedBytes: Int64)
        case failed(ModelAssetError)
    }

    private func transfer(
        _ asset: ModelAsset,
        _ file: ModelFile,
        completedBytes: Int64,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async -> TransferOutcome {
        let resumeURL = resumeDataFile(asset, file)
        var resumeData = try? Data(contentsOf: resumeURL)
        let total = asset.downloadBytes
        set(asset, .downloading(receivedBytes: completedBytes, totalBytes: total), progress)
        let lastReceived = ByteCounter()
        let report: @Sendable (Int64, Int64) -> Void = { received, _ in
            lastReceived.set(received)
            progress(.downloading(receivedBytes: completedBytes + received, totalBytes: total))
        }
        // One attempt with resume data, and one fresh attempt if the resume
        // data was stale (the system had already discarded the partial file).
        for attempt in 0..<2 {
            do {
                try await downloader.download(
                    from: file.url, resumeData: resumeData, to: stagedFile(asset, file), progress: report)
                try? FileManager.default.removeItem(at: resumeURL)
                return .finished
            } catch .cancelled(let data) {
                save(data, to: resumeURL)
                return .paused(receivedBytes: completedBytes + (data == nil ? 0 : lastReceived.value))
            } catch .failed(let code, let data) {
                if let data {
                    save(data, to: resumeURL)
                    return .failed(.downloadFailed(code: code))
                }
                try? FileManager.default.removeItem(at: resumeURL)
                if attempt == 0 && resumeData != nil {
                    resumeData = nil
                    continue
                }
                return .failed(.downloadFailed(code: code))
            }
        }
        return .failed(.downloadFailed(code: -1))
    }

    private func verify(_ url: URL, against file: ModelFile) -> ModelAssetError? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        guard size == file.bytes else { return .sizeMismatch }
        guard let digest = try? FileDigest.sha256(of: url), digest == file.sha256.lowercased() else {
            return .digestMismatch
        }
        return nil
    }

    private func activate(_ asset: ModelAsset) throws(ModelAssetError) {
        let manager = FileManager.default
        let active = activeDirectory(asset)
        do {
            if manager.fileExists(atPath: assetDirectory(asset).path) {
                try manager.removeItem(at: assetDirectory(asset))
            }
            try createDirectory(active)
            for file in asset.files {
                try manager.moveItem(at: stagedFile(asset, file), to: active.appendingPathComponent(file.name))
            }
            try Data(asset.files.map(\.sha256).joined(separator: "\n").utf8)
                .write(to: active.appendingPathComponent(Self.marker), options: .atomic)
            try? manager.removeItem(at: stagingDirectory(asset))
        } catch {
            try? manager.removeItem(at: assetDirectory(asset))
            throw .storageFailure
        }
    }

    // MARK: Helpers

    @discardableResult
    private func set(
        _ asset: ModelAsset,
        _ state: ModelInstallState,
        _ progress: @Sendable (ModelInstallState) -> Void
    ) -> ModelInstallState {
        transient[asset.id] = state.isBusy ? state : nil
        progress(state)
        return state
    }

    private func fail(
        _ asset: ModelAsset,
        _ error: ModelAssetError,
        progress: @Sendable (ModelInstallState) -> Void
    ) {
        transient[asset.id] = nil
        diagnostics.record(
            .models, "model.install-failed", ["asset": .id(asset.id.rawValue), "error": .id(error.identifier)])
        Log.models.error("Model install failed: \(error.identifier, privacy: .public)")
        progress(.failed(error))
    }

    private func isActive(_ asset: ModelAsset) -> Bool {
        let active = activeDirectory(asset)
        let manager = FileManager.default
        guard manager.fileExists(atPath: active.appendingPathComponent(Self.marker).path) else { return false }
        return asset.files.allSatisfy { file in
            let size =
                (try? manager.attributesOfItem(atPath: active.appendingPathComponent(file.name).path)[.size]
                as? NSNumber)?.int64Value
            return size == file.bytes
        }
    }

    /// Bytes of completely downloaded files waiting in staging.
    private func stagedBytes(_ asset: ModelAsset) -> Int64 {
        asset.files.reduce(0) { total, file in
            let size =
                (try? FileManager.default.attributesOfItem(atPath: stagedFile(asset, file).path)[.size]
                as? NSNumber)?.int64Value
            return total + (size ?? 0)
        }
    }

    private func hasResumeData(_ asset: ModelAsset) -> Bool {
        asset.files.contains { FileManager.default.fileExists(atPath: resumeDataFile(asset, $0).path) }
    }

    private func save(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func createDirectory(_ url: URL) throws(ModelAssetError) {
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw .storageFailure
        }
    }

    private func existingAncestor(of url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path) && candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private static let marker = ".verified"

    private func assetDirectory(_ asset: ModelAsset) -> URL {
        root.appendingPathComponent(asset.id.rawValue, isDirectory: true)
    }

    private func activeDirectory(_ asset: ModelAsset) -> URL {
        assetDirectory(asset).appendingPathComponent(asset.version, isDirectory: true)
    }

    private func stagingDirectory(_ asset: ModelAsset) -> URL {
        root.appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(asset.id.rawValue, isDirectory: true)
    }

    private func stagedFile(_ asset: ModelAsset, _ file: ModelFile) -> URL {
        stagingDirectory(asset).appendingPathComponent(file.name)
    }

    private func resumeDataFile(_ asset: ModelAsset, _ file: ModelFile) -> URL {
        stagingDirectory(asset).appendingPathComponent(file.name + ".resume")
    }

    /// Free space for important (user-initiated) data on the volume holding `url`.
    public static let volumeFreeSpace: @Sendable (URL) -> Int64 = { url in
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

/// Latest byte count reported by a transfer.
private final class ByteCounter: Sendable {
    private let storage = Mutex<Int64>(0)

    var value: Int64 { storage.withLock { $0 } }

    func set(_ bytes: Int64) {
        storage.withLock { $0 = bytes }
    }
}
