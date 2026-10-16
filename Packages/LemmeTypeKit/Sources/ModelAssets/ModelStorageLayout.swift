import Domain
import Foundation

/// Where model files live and the file operations on them:
/// - `Staging/<asset>/` — files being downloaded or verified, plus resume data.
///   Nothing here is ever used for recognition.
/// - `<asset>/<version>/` — the active, verified files and a `.verified` marker.
struct ModelStorageLayout: Sendable {
    let root: URL

    private static let marker = ".verified"
    private var manager: FileManager { .default }

    func assetDirectory(_ asset: ModelAsset) -> URL {
        root.appendingPathComponent(asset.id.rawValue, isDirectory: true)
    }

    func activeDirectory(_ asset: ModelAsset) -> URL {
        assetDirectory(asset).appendingPathComponent(asset.version, isDirectory: true)
    }

    var stagingRoot: URL {
        root.appendingPathComponent("Staging", isDirectory: true)
    }

    func stagingDirectory(_ asset: ModelAsset) -> URL {
        stagingRoot.appendingPathComponent(asset.id.rawValue, isDirectory: true)
    }

    func stagedFile(_ asset: ModelAsset, _ file: ModelFile) -> URL {
        stagingDirectory(asset).appendingPathComponent(file.name)
    }

    func resumeDataFile(_ asset: ModelAsset, _ file: ModelFile) -> URL {
        stagingDirectory(asset).appendingPathComponent(file.name + ".resume")
    }

    // MARK: Queries

    func isActive(_ asset: ModelAsset) -> Bool {
        let active = activeDirectory(asset)
        guard manager.fileExists(atPath: active.appendingPathComponent(Self.marker).path) else { return false }
        return asset.files.allSatisfy { size(of: active.appendingPathComponent($0.name)) == $0.bytes }
    }

    /// Bytes of completely downloaded files waiting in staging.
    func stagedBytes(_ asset: ModelAsset) -> Int64 {
        asset.files.reduce(0) { $0 + (size(of: stagedFile(asset, $1)) ?? 0) }
    }

    func hasResumeData(_ asset: ModelAsset) -> Bool {
        asset.files.contains { manager.fileExists(atPath: resumeDataFile(asset, $0).path) }
    }

    func size(of url: URL) -> Int64? {
        (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// The nearest existing directory, for free-space queries before `root` exists.
    func existingAncestor() -> URL {
        var candidate = root
        while !manager.fileExists(atPath: candidate.path) && candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    // MARK: Operations

    func createDirectory(_ url: URL) throws(ModelAssetError) {
        do {
            try manager.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw .storageFailure
        }
    }

    func saveResumeData(_ data: Data?, for asset: ModelAsset, _ file: ModelFile) {
        guard let data else { return }
        try? data.write(to: resumeDataFile(asset, file), options: .atomic)
    }

    func removeResumeData(for asset: ModelAsset, _ file: ModelFile) {
        try? manager.removeItem(at: resumeDataFile(asset, file))
    }

    /// Checks every staged file's size and SHA-256; deletes and reports the first mismatch.
    func verifyStaged(_ asset: ModelAsset) throws(ModelAssetError) {
        for file in asset.files {
            let url = stagedFile(asset, file)
            var failure: ModelAssetError?
            if size(of: url) != file.bytes {
                failure = .sizeMismatch
            } else if (try? FileDigest.sha256(of: url)) != file.sha256.lowercased() {
                failure = .digestMismatch
            }
            if let failure {
                try? manager.removeItem(at: url)
                throw failure
            }
        }
    }

    /// Moves verified files into place, replacing any other version.
    func activate(_ asset: ModelAsset) throws(ModelAssetError) {
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

    /// Deletes the asset's active and staged files.
    func remove(_ asset: ModelAsset) throws(ModelAssetError) {
        for directory in [assetDirectory(asset), stagingDirectory(asset)]
        where manager.fileExists(atPath: directory.path) {
            do {
                try manager.removeItem(at: directory)
            } catch {
                throw .storageFailure
            }
        }
    }

    /// Deletes versions not in `catalog` and staging folders of unknown assets.
    func removeUnusable(keeping catalog: [ModelAsset]) {
        for asset in catalog {
            let directory = assetDirectory(asset)
            for version in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
            where version != asset.version {
                try? manager.removeItem(at: directory.appendingPathComponent(version))
            }
        }
        let known = Set(catalog.map(\.id.rawValue))
        for name in (try? manager.contentsOfDirectory(atPath: stagingRoot.path)) ?? [] where !known.contains(name) {
            try? manager.removeItem(at: stagingRoot.appendingPathComponent(name))
        }
    }
}
