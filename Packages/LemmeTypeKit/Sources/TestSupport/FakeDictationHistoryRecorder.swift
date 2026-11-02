import Domain
import Synchronization

/// Remembers what was offered to the history, without storing anything.
public final class FakeDictationHistoryRecorder: DictationHistoryRecording {
    public struct Call: Equatable, Sendable {
        public let text: String
        public let delivery: HistoryDelivery
    }

    private let storage = Mutex<[Call]>([])

    public init() {}

    public var calls: [Call] { storage.withLock { $0 } }

    public func record(_ text: String, for session: DictationSession, delivery: HistoryDelivery) async {
        storage.withLock { $0.append(Call(text: text, delivery: delivery)) }
    }
}
