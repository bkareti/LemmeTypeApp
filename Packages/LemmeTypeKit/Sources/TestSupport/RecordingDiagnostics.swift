import Domain
import Foundation
import Synchronization

/// Collects diagnostics events in memory.
public final class RecordingDiagnostics: DiagnosticsRecording {
    private let storage = Mutex<[DiagnosticEvent]>([])
    public var events: [DiagnosticEvent] { storage.withLock { $0 } }

    public init() {}

    public func record(
        _ category: DiagnosticCategory, _ name: StaticString, _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {
        let event = DiagnosticEvent(timestamp: Date(), category: category, name: name, attributes: attributes)
        storage.withLock { $0.append(event) }
    }
}
