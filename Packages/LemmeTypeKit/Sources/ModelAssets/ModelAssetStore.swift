import Domain
import Foundation
import Support
import Synchronization

/// Downloads, verifies, activates, and removes catalog models (layout in
/// ``ModelStorageLayout``; root is Application Support/LemmeType/Models).
///
/// A file moves from staging to active only after its size and SHA-256 match
/// the version-controlled ``ModelCatalog``; mismatches are deleted.
public actor ModelAssetStore: ModelAssetManaging {
    public nonisolated var root: URL { layout.root }
    private let layout: ModelStorageLayout
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
        self.layout = ModelStorageLayout(root: root)
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

    /// Free space for important (user-initiated) data on the volume holding `url`.
    public static let volumeFreeSpace: @Sendable (URL) -> Int64 = { url in
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: State

    public func state(of id: ModelAssetID) -> ModelInstallState {
        if let state = transient[id] { return state }
        guard let asset = asset(id) else { return .notInstalled }
        if layout.isActive(asset) { return .installed }
        let staged = layout.stagedBytes(asset)
        return staged > 0 || layout.hasResumeData(asset)
            ? .paused(receivedBytes: staged, totalBytes: asset.downloadBytes) : .notInstalled
    }

    public func installedFile(for id: ModelAssetID, named name: String) -> URL? {
        guard let asset = asset(id), layout.isActive(asset), asset.files.contains(where: { $0.name == name })
        else { return nil }
        return layout.activeDirectory(asset).appendingPathComponent(name)
    }

    public func availableBytes() -> Int64 {
        freeSpace(layout.existingAncestor())
    }

    // MARK: Install

    @discardableResult
    public func install(
        _ consent: ModelDownloadConsent,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState {
        let asset = try preflight(consent)
        if layout.isActive(asset) {
            progress(.installed)
            return .installed
        }
        do {
            try checkFreeSpace(for: asset)
            diagnostics.record(.models, "model.download-started", ["asset": .id(asset.id.rawValue)])
            try layout.createDirectory(layout.stagingDirectory(asset))
            if let paused = try await downloadMissingFiles(asset, progress: progress) {
                return paused
            }
            update(asset, .verifying, progress)
            try layout.verifyStaged(asset)
            try layout.activate(asset)
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
        guard let asset = asset(id) else { return }
        for file in asset.files {
            await downloader.pause(file.url)
        }
    }

    // MARK: Remove

    public func remove(_ id: ModelAssetID) async throws(ModelAssetError) {
        guard let asset = asset(id) else { throw .unknownAsset }
        if transient[id]?.isBusy == true {
            await pause(id)
        }
        try layout.remove(asset)
        transient[id] = nil
        diagnostics.record(.models, "model.removed", ["asset": .id(asset.id.rawValue)])
        Log.models.info("Model removed: \(asset.id.rawValue, privacy: .public)")
    }

    public func removeUnusableFiles() {
        layout.removeUnusable(keeping: catalog)
    }

    // MARK: Steps

    private func asset(_ id: ModelAssetID) -> ModelAsset? {
        catalog.first { $0.id == id }
    }

    private func preflight(_ consent: ModelDownloadConsent) throws(ModelAssetError) -> ModelAsset {
        guard let asset = asset(consent.asset) else { throw .unknownAsset }
        guard consent.isValid(for: asset) else { throw .consentRequired }
        guard asset.files.allSatisfy({ ModelCatalog.isTrustedSource($0.url) }) else { throw .untrustedSource }
        if transient[asset.id]?.isBusy == true { throw .alreadyInProgress }
        return asset
    }

    private func checkFreeSpace(for asset: ModelAsset) throws(ModelAssetError) {
        let available = availableBytes()
        let required = asset.requiredFreeBytes - layout.stagedBytes(asset)
        guard available >= required else {
            throw .insufficientStorage(requiredBytes: required, availableBytes: available)
        }
    }

    /// Downloads every file not yet staged. Returns `.paused` if a transfer
    /// was paused, `nil` when all files are staged.
    private func downloadMissingFiles(
        _ asset: ModelAsset,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState? {
        var completedBytes: Int64 = 0
        for file in asset.files {
            if layout.size(of: layout.stagedFile(asset, file)) == nil {
                update(asset, .downloading(receivedBytes: completedBytes, totalBytes: asset.downloadBytes), progress)
                if let received = try await transfer(asset, file, completedBytes: completedBytes, progress: progress) {
                    let paused = ModelInstallState.paused(receivedBytes: received, totalBytes: asset.downloadBytes)
                    update(asset, paused, progress)
                    return paused
                }
            }
            completedBytes += file.bytes
        }
        return nil
    }

    /// Transfers one file. Returns the bytes received if paused, `nil` when done.
    /// Stale resume data (the system discarded the partial file) gets one
    /// fresh restart.
    private func transfer(
        _ asset: ModelAsset,
        _ file: ModelFile,
        completedBytes: Int64,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> Int64? {
        var resumeData = try? Data(contentsOf: layout.resumeDataFile(asset, file))
        let total = asset.downloadBytes
        let lastReceived = ByteCounter()
        let report: @Sendable (Int64, Int64) -> Void = { received, _ in
            lastReceived.set(received)
            progress(.downloading(receivedBytes: completedBytes + received, totalBytes: total))
        }
        while true {
            do {
                try await downloader.download(
                    from: file.url, resumeData: resumeData, to: layout.stagedFile(asset, file), progress: report)
                layout.removeResumeData(for: asset, file)
                return nil
            } catch {
                switch error {
                case .cancelled(let data):
                    layout.saveResumeData(data, for: asset, file)
                    return completedBytes + (data == nil ? 0 : lastReceived.value)
                case .failed(let code, let data):
                    if data == nil && resumeData != nil {
                        layout.removeResumeData(for: asset, file)
                        resumeData = nil
                        continue
                    }
                    layout.saveResumeData(data, for: asset, file)
                    if data == nil { layout.removeResumeData(for: asset, file) }
                    throw .downloadFailed(code: code)
                }
            }
        }
    }

    private func update(
        _ asset: ModelAsset,
        _ state: ModelInstallState,
        _ progress: @Sendable (ModelInstallState) -> Void
    ) {
        transient[asset.id] = state.isBusy ? state : nil
        progress(state)
    }

    private func fail(_ asset: ModelAsset, _ error: ModelAssetError, progress: @Sendable (ModelInstallState) -> Void) {
        transient[asset.id] = nil
        diagnostics.record(
            .models, "model.install-failed", ["asset": .id(asset.id.rawValue), "error": .id(error.identifier)])
        Log.models.error("Model install failed: \(error.identifier, privacy: .public)")
        progress(.failed(error))
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
