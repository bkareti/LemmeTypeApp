import Foundation

/// Why a transfer stopped.
public enum ModelDownloadFailure: Error, Equatable, Sendable {
    /// Paused or cancelled; `resumeData` continues the transfer later.
    case cancelled(resumeData: Data?)
    /// Network or HTTP failure. `code` is a URL error code or HTTP status.
    case failed(code: Int, resumeData: Data?)
}

/// Transfers one file to a destination on disk. The network edge of
/// `ModelAssetStore`, replaceable in tests.
public protocol ModelDownloading: Sendable {
    func download(
        from url: URL,
        resumeData: Data?,
        to destination: URL,
        progress: @escaping @Sendable (_ received: Int64, _ expected: Int64) -> Void
    ) async throws(ModelDownloadFailure)

    /// Stops the transfer of `url`, producing resume data when possible.
    func pause(_ url: URL) async
}
