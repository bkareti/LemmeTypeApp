import Foundation

/// Identity of a downloadable model asset. Raw values are stable.
public struct ModelAssetID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let whisperBaseEnglish = ModelAssetID(rawValue: "whisper-base-en")
}

/// One file of a model, pinned by size and SHA-256 digest.
public struct ModelFile: Equatable, Sendable {
    public let name: String
    public let url: URL
    /// Lowercase hexadecimal SHA-256 of the complete file.
    public let sha256: String
    public let bytes: Int64

    public init(name: String, url: URL, sha256: String, bytes: Int64) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.bytes = bytes
    }
}

/// A downloadable model and everything the user needs to decide whether to
/// download it. Entries exist only in ``ModelCatalog``, which is version
/// controlled: sources and digests are never accepted from user input or the
/// network.
public struct ModelAsset: Equatable, Sendable, Identifiable {
    public let id: ModelAssetID
    public let displayName: String
    public let version: String
    public let engine: RecognitionEngineID
    public let files: [ModelFile]
    /// BCP 47 language codes.
    public let languages: [String]
    public let license: String
    public let licenseURL: URL
    public let hardware: HardwareRequirement

    public init(
        id: ModelAssetID,
        displayName: String,
        version: String,
        engine: RecognitionEngineID,
        files: [ModelFile],
        languages: [String],
        license: String,
        licenseURL: URL,
        hardware: HardwareRequirement
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.engine = engine
        self.files = files
        self.languages = languages
        self.license = license
        self.licenseURL = licenseURL
        self.hardware = hardware
    }

    /// Bytes transferred by a full download.
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    /// Disk space used once installed (models are stored uncompressed).
    public var installedBytes: Int64 { downloadBytes }
    /// Free space required to start: staging copy plus a safety margin.
    public var requiredFreeBytes: Int64 { downloadBytes + max(downloadBytes / 10, 100_000_000) }
}

/// What a Mac needs to run a model well.
public struct HardwareRequirement: Equatable, Sendable {
    public let requiresAppleSilicon: Bool
    public let minimumMemoryBytes: UInt64

    public init(requiresAppleSilicon: Bool, minimumMemoryBytes: UInt64) {
        self.requiresAppleSilicon = requiresAppleSilicon
        self.minimumMemoryBytes = minimumMemoryBytes
    }

    /// The reason this Mac cannot run the model, if any.
    public func unsupportedReason(for hardware: HardwareProfile) -> UnsupportedReason? {
        if requiresAppleSilicon && !hardware.isAppleSilicon { return .hardware }
        if hardware.physicalMemoryBytes < minimumMemoryBytes { return .insufficientMemory }
        return nil
    }
}

/// The facts about this Mac that model compatibility depends on.
public struct HardwareProfile: Equatable, Sendable {
    public let isAppleSilicon: Bool
    public let physicalMemoryBytes: UInt64

    public init(isAppleSilicon: Bool, physicalMemoryBytes: UInt64) {
        self.isAppleSilicon = isAppleSilicon
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    public static var current: HardwareProfile {
        #if arch(arm64)
            let appleSilicon = true
        #else
            let appleSilicon = false
        #endif
        return HardwareProfile(
            isAppleSilicon: appleSilicon, physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }
}

/// The user's explicit agreement to download `asset`, created by the
/// confirmation UI after showing the download and storage size. Downloads
/// cannot start without one.
public struct ModelDownloadConsent: Equatable, Sendable {
    public let asset: ModelAssetID
    /// The download size the user saw; must match the catalog.
    public let acknowledgedBytes: Int64

    public init(asset: ModelAsset) {
        self.asset = asset.id
        self.acknowledgedBytes = asset.downloadBytes
    }

    public init(asset: ModelAssetID, acknowledgedBytes: Int64) {
        self.asset = asset
        self.acknowledgedBytes = acknowledgedBytes
    }

    public func isValid(for asset: ModelAsset) -> Bool {
        self.asset == asset.id && acknowledgedBytes == asset.downloadBytes
    }
}

/// Where a model is in its lifecycle.
public enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    /// Stopped with resumable progress kept in staging.
    case paused(receivedBytes: Int64, totalBytes: Int64)
    case verifying
    case installed
    case failed(ModelAssetError)

    public var isInstalled: Bool { self == .installed }

    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }

    /// 0...1 while downloading or paused.
    public var fractionCompleted: Double? {
        switch self {
        case .downloading(let received, let total), .paused(let received, let total):
            total > 0 ? min(1, Double(received) / Double(total)) : 0
        default: nil
        }
    }
}

public enum ModelAssetError: LemmeTypeError, Equatable {
    case consentRequired
    case unknownAsset
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
    case downloadFailed(code: Int)
    case digestMismatch
    case sizeMismatch
    case alreadyInProgress
    case storageFailure
    /// The source is not an HTTPS URL on an allowlisted host.
    case untrustedSource

    public var identifier: String {
        switch self {
        case .consentRequired: "model.consent-required"
        case .unknownAsset: "model.unknown-asset"
        case .insufficientStorage: "model.insufficient-storage"
        case .downloadFailed: "model.download-failed"
        case .digestMismatch: "model.digest-mismatch"
        case .sizeMismatch: "model.size-mismatch"
        case .alreadyInProgress: "model.already-in-progress"
        case .storageFailure: "model.storage-failure"
        case .untrustedSource: "model.untrusted-source"
        }
    }
}

/// Downloads, verifies, and removes catalog models.
public protocol ModelAssetManaging: Sendable {
    func state(of asset: ModelAssetID) async -> ModelInstallState
    /// The verified, active file for `asset`, or `nil` when not installed.
    func installedFile(for asset: ModelAssetID, named name: String) async -> URL?
    /// Free space on the models volume.
    func availableBytes() async -> Int64
    /// Downloads (resuming a paused download when possible), verifies every
    /// file's size and SHA-256, and activates the model. `progress` receives
    /// every state change. Returns `.installed`, or `.paused` when the
    /// download was paused or the calling task was cancelled.
    @discardableResult
    func install(
        _ consent: ModelDownloadConsent,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState
    /// Stops an active download, keeping resumable progress.
    func pause(_ asset: ModelAssetID) async
    /// Deletes the model's managed files (active and staged).
    func remove(_ asset: ModelAssetID) async throws(ModelAssetError)
    /// Launch housekeeping: deletes outdated versions and unknown staging data.
    func removeUnusableFiles() async
}
