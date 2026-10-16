// The only network code in LemmeType (docs/decisions/0011-model-downloads.md):
// it downloads catalog model files after the user confirms, never during
// dictation. The lint rule against network APIs is disabled for this file only.
// swiftlint:disable no_network_apis

import Domain
import Foundation
import Support

/// Downloads model files with `URLSession`: ephemeral configuration (no
/// cookies, cache, or credentials), HTTPS to allowlisted hosts only, with
/// resume data for paused or interrupted transfers.
public final class URLSessionModelDownloader: ModelDownloading {
    private let delegate = DownloadDelegate()
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func download(
        from url: URL,
        resumeData: Data?,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws(ModelDownloadFailure) {
        guard ModelCatalog.isTrustedSource(url) else { throw .failed(code: -1, resumeData: nil) }
        let session = self.session
        let delegate = self.delegate
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    let task =
                        resumeData.map { session.downloadTask(withResumeData: $0) }
                        ?? session.downloadTask(with: url)
                    delegate.register(
                        task, url: url,
                        transfer: Transfer(destination: destination, progress: progress, continuation: continuation))
                    task.resume()
                }
            } onCancel: {
                delegate.pause(url)
            }
        } catch let failure as ModelDownloadFailure {
            throw failure
        } catch {
            throw .failed(code: -1, resumeData: nil)
        }
    }

    public func pause(_ url: URL) async {
        delegate.pause(url)
    }
}

private struct Transfer {
    let destination: URL
    let progress: @Sendable (Int64, Int64) -> Void
    let continuation: CheckedContinuation<Void, any Error>
    var task: URLSessionDownloadTask?
    var url: URL?
    var outcome: Result<Void, ModelDownloadFailure>?
    var isPausing = false
}

/// `@unchecked Sendable`: `transfers` is only accessed while holding `lock`;
/// continuations are resumed exactly once, outside the lock.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    func register(_ task: URLSessionDownloadTask, url: URL, transfer: Transfer) {
        var transfer = transfer
        transfer.task = task
        transfer.url = url
        lock.lock()
        transfers[task.taskIdentifier] = transfer
        lock.unlock()
    }

    func pause(_ url: URL) {
        lock.lock()
        let entry = transfers.first { $0.value.url == url && !$0.value.isPausing }
        if let entry {
            transfers[entry.key]?.isPausing = true
        }
        lock.unlock()
        guard let entry, let task = entry.value.task else { return }
        let identifier = entry.key
        task.cancel(byProducingResumeData: { [weak self] data in
            self?.finish(identifier, .failure(.cancelled(resumeData: data)))
        })
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let progress = transfers[downloadTask.taskIdentifier]?.progress
        lock.unlock()
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let destination = transfers[downloadTask.taskIdentifier]?.destination
        lock.unlock()
        guard let destination else { return }
        let outcome: Result<Void, ModelDownloadFailure>
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            outcome = .failure(.failed(code: response.statusCode, resumeData: nil))
        } else {
            // The system deletes `location` when this method returns.
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                outcome = .success(())
            } catch {
                outcome = .failure(.failed(code: (error as NSError).code, resumeData: nil))
            }
        }
        lock.lock()
        transfers[downloadTask.taskIdentifier]?.outcome = outcome
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let transfer = transfers[task.taskIdentifier]
        lock.unlock()
        guard let transfer else { return }
        // A pause finishes from its resume-data callback instead.
        if transfer.isPausing { return }
        if let error {
            let nsError = error as NSError
            let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            let failure: ModelDownloadFailure =
                nsError.code == NSURLErrorCancelled
                ? .cancelled(resumeData: resumeData) : .failed(code: nsError.code, resumeData: resumeData)
            Log.models.error("Model download stopped: \(nsError.code, privacy: .public)")
            finish(task.taskIdentifier, .failure(failure))
        } else {
            finish(task.taskIdentifier, transfer.outcome ?? .failure(.failed(code: -1, resumeData: nil)))
        }
    }

    private func finish(_ identifier: Int, _ outcome: Result<Void, ModelDownloadFailure>) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: identifier)
        lock.unlock()
        transfer?.continuation.resume(with: outcome.mapError { $0 as any Error })
    }
}
// swiftlint:enable no_network_apis
