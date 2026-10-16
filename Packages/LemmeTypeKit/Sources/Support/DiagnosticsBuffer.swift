import Domain
import Foundation
import Synchronization

/// In-memory ring buffer of recent diagnostic events. Nothing is written to
/// disk or sent anywhere; the user exports a report explicitly.
public final class DiagnosticsBuffer: DiagnosticsRecording {
    public static let defaultCapacity = 500

    private let capacity: Int
    private let now: @Sendable () -> Date
    private let events = Mutex<[DiagnosticEvent]>([])

    public init(capacity: Int = DiagnosticsBuffer.defaultCapacity, now: @escaping @Sendable () -> Date = Date.init) {
        self.capacity = capacity
        self.now = now
    }

    public func record(
        _ category: DiagnosticCategory,
        _ name: StaticString,
        _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {
        let event = DiagnosticEvent(timestamp: now(), category: category, name: name, attributes: attributes)
        events.withLock { events in
            events.append(event)
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
        }
    }

    public func snapshot() -> [DiagnosticEvent] {
        events.withLock { $0 }
    }
}
