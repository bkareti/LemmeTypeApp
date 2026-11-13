import Domain
import Foundation
import Synchronization

/// An entitlement check whose answer the test chooses, and that counts how often it was asked.
public final class FakeEntitlement: EntitlementChecking {
    private let state: Mutex<(decision: EntitlementDecision, asked: Int)>

    public init(_ decision: EntitlementDecision = .allowed) {
        state = Mutex((decision, 0))
    }

    public func set(_ decision: EntitlementDecision) { state.withLock { $0.decision = decision } }
    public var asked: Int { state.withLock { $0.asked } }

    public func decision() async -> EntitlementDecision {
        state.withLock {
            $0.asked += 1
            return $0.decision
        }
    }
}

/// Keeps the high-water mark in memory.
public final class FakeEntitlementLedger: EntitlementLedgerStoring {
    private let value: Mutex<Date?>

    public init(_ mark: Date? = nil) {
        value = Mutex(mark)
    }

    public var highWaterMark: Date? {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

/// Keeps the summary in memory.
public final class FakeEntitlementSummaryStore: EntitlementSummaryStoring {
    private let value = Mutex<EntitlementSummary?>(nil)

    public init() {}

    public func write(_ summary: EntitlementSummary) { value.withLock { $0 = summary } }
    public func read() -> EntitlementSummary? { value.withLock { $0 } }
    public func clear() { value.withLock { $0 = nil } }
}
