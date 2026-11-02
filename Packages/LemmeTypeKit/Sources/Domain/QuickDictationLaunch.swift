import Foundation
import Synchronization

/// A request, left by an App Intent, to start dictating as soon as the app is
/// on screen (E8-S7).
public struct QuickDictationLaunchRequest: Equatable, Sendable {
    public let id: UUID
    public let requestedAt: Date

    public init(id: UUID = UUID(), requestedAt: Date) {
        self.id = id
        self.requestedAt = requestedAt
    }
}

/// Holds at most one launch request. It is consumed once, and an old request is
/// ignored, so opening the app a minute after a shortcut ran never starts the
/// microphone by surprise.
public final class LaunchRequestInbox: Sendable {
    /// How long a request stays valid.
    public let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let pending = Mutex<QuickDictationLaunchRequest?>(nil)

    public init(lifetime: TimeInterval = 10, now: @escaping @Sendable () -> Date = { Date() }) {
        self.lifetime = lifetime
        self.now = now
    }

    /// Leaves a request, replacing any earlier one.
    @discardableResult
    public func post() -> QuickDictationLaunchRequest {
        let request = QuickDictationLaunchRequest(requestedAt: now())
        pending.withLock { $0 = request }
        return request
    }

    /// The request, if one is waiting and has not expired. Clears it either way.
    public func consume() -> QuickDictationLaunchRequest? {
        let request = pending.withLock { current -> QuickDictationLaunchRequest? in
            defer { current = nil }
            return current
        }
        guard let request, now().timeIntervalSince(request.requestedAt) <= lifetime else { return nil }
        return request
    }
}
