import Foundation
import Synchronization

/// A date a test moves by hand, for code that takes a `now: () -> Date`.
public final class TestNow: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_000))

    public init() {}

    public var date: Date { value.withLock { $0 } }

    public func advance(by seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
