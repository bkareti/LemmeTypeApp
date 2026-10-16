import Domain
import Foundation
import Synchronization

/// In-memory model installs for tests and UI tests. Installs complete
/// immediately (or fail with a scripted error); no network or disk is used.
public final class FakeModelAssetManager: ModelAssetManaging {
    private struct State {
        var states: [ModelAssetID: ModelInstallState]
        var installError: ModelAssetError?
        var availableBytes: Int64
        var installCount = 0
        var removeCount = 0
    }

    private let state: Mutex<State>
    private let installedDirectory: URL

    public init(
        installed: Set<ModelAssetID> = [],
        installError: ModelAssetError? = nil,
        availableBytes: Int64 = 50_000_000_000,
        installedDirectory: URL = URL(fileURLWithPath: "/nonexistent/LemmeTypeFakeModels")
    ) {
        state = Mutex(
            State(
                states: Dictionary(uniqueKeysWithValues: installed.map { ($0, .installed) }),
                installError: installError,
                availableBytes: availableBytes
            ))
        self.installedDirectory = installedDirectory
    }

    public var installCount: Int { state.withLock { $0.installCount } }
    public var removeCount: Int { state.withLock { $0.removeCount } }

    public func state(of asset: ModelAssetID) async -> ModelInstallState {
        state.withLock { $0.states[asset] ?? .notInstalled }
    }

    public func installedFile(for asset: ModelAssetID, named name: String) async -> URL? {
        let installed = state.withLock { $0.states[asset] == .installed }
        return installed ? installedDirectory.appendingPathComponent(name) : nil
    }

    public func availableBytes() async -> Int64 {
        state.withLock { $0.availableBytes }
    }

    @discardableResult
    public func install(
        _ consent: ModelDownloadConsent,
        progress: @escaping @Sendable (ModelInstallState) -> Void
    ) async throws(ModelAssetError) -> ModelInstallState {
        guard let asset = ModelCatalog.asset(consent.asset) else { throw .unknownAsset }
        guard consent.isValid(for: asset) else { throw .consentRequired }
        let error = state.withLock { state -> ModelAssetError? in
            state.installCount += 1
            if let error = state.installError {
                state.states[consent.asset] = .notInstalled
                return error
            }
            state.states[consent.asset] = .installed
            return nil
        }
        progress(.downloading(receivedBytes: 0, totalBytes: asset.downloadBytes))
        if let error {
            progress(.failed(error))
            throw error
        }
        progress(.verifying)
        progress(.installed)
        return .installed
    }

    public func pause(_ asset: ModelAssetID) async {}

    public func remove(_ asset: ModelAssetID) async throws(ModelAssetError) {
        state.withLock {
            $0.removeCount += 1
            $0.states[asset] = nil
        }
    }

    public func removeUnusableFiles() async {}
}
