import Domain
import Foundation
import Synchronization

/// A release list from memory, for tests and UI tests. Counts requests.
public final class FakeUpdateFeed: UpdateFeed {
    private struct State {
        var releases: [ReleaseInfo]
        var error: UpdateError?
        var calls = 0
    }

    private let state: Mutex<State>

    public init(releases: [ReleaseInfo] = [], error: UpdateError? = nil) {
        state = Mutex(State(releases: releases, error: error))
    }

    public var calls: Int { state.withLock { $0.calls } }

    public func set(_ releases: [ReleaseInfo], error: UpdateError? = nil) {
        state.withLock {
            $0.releases = releases
            $0.error = error
        }
    }

    public func releases() async throws(UpdateError) -> [ReleaseInfo] {
        let snapshot = state.withLock { state -> State in
            state.calls += 1
            return state
        }
        if let error = snapshot.error { throw error }
        return snapshot.releases
    }

    /// A release on this project's releases page.
    public static func release(_ version: String, prerelease: Bool = false) -> ReleaseInfo {
        let parsed = SemanticVersion(version) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        let page = URL(string: "https://github.com/bkareti/LemmeTypeApp/releases/tag/v\(version)")
        return ReleaseInfo(
            version: parsed, pageURL: page ?? URL(fileURLWithPath: "/"), isPrerelease: prerelease)
    }
}
