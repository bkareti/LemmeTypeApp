import Foundation

/// What the iPhone app tells the LemmeType keyboard about an Action Button
/// dictation (ADR 0032). Only the app writes it; the keyboard runs without Full
/// Access, so it can read this but cannot write back.
public struct KeyboardHandoff: Codable, Equatable, Sendable, CustomStringConvertible {
    public enum Phase: String, Codable, Sendable {
        case idle
        case listening
        case writing
        case ready
        case failed
    }

    /// One piece of text the keyboard should insert.
    public struct Insertion: Equatable, Sendable {
        public let id: UUID
        public let text: String
    }

    /// How long a finished result may wait for the keyboard. The app erases it
    /// after this, and the keyboard ignores anything older, because the keyboard
    /// cannot tell the app it has finished.
    public static let lifetime: TimeInterval = 25

    public var phase: Phase
    public var resultID: UUID?
    public var text: String?
    public var createdAt: Date?
    /// Why the dictation failed; never contains dictated text.
    public var failureMessage: String?

    public init(
        phase: Phase = .idle, resultID: UUID? = nil, text: String? = nil, createdAt: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.phase = phase
        self.resultID = resultID
        self.text = text
        self.createdAt = createdAt
        self.failureMessage = failureMessage
    }

    public static let idle = KeyboardHandoff()

    public static func ready(text: String, id: UUID = UUID(), at date: Date = .now) -> KeyboardHandoff {
        KeyboardHandoff(phase: .ready, resultID: id, text: text, createdAt: date)
    }

    public static func failed(_ message: String) -> KeyboardHandoff {
        KeyboardHandoff(phase: .failed, failureMessage: message)
    }

    /// The text to insert now, if there is a fresh result this keyboard has not
    /// already inserted.
    public func insertion(now: Date, alreadyInserted: UUID?) -> Insertion? {
        guard phase == .ready, let resultID, resultID != alreadyInserted, let text, let createdAt else { return nil }
        let age = now.timeIntervalSince(createdAt)
        guard age >= 0, age < Self.lifetime else { return nil }
        return Insertion(id: resultID, text: text)
    }

    /// What the keyboard should do with a result.
    public enum Delivery: Equatable, Sendable {
        case none
        case insert(Insertion)
        /// The text may belong to another field, so it waits for an explicit tap.
        case offer(Insertion)
    }

    /// A result goes in by itself only into the field that was open when the
    /// recording started. Anywhere else, the person chooses.
    public func delivery(now: Date, alreadyInserted: UUID?, recordingField: UUID?, currentField: UUID?) -> Delivery {
        guard let insertion = insertion(now: now, alreadyInserted: alreadyInserted) else { return .none }
        guard let recordingField, recordingField == currentField else { return .offer(insertion) }
        return .insert(insertion)
    }

    /// Never includes the text, so this value is safe in a log or a test failure.
    public var description: String {
        "KeyboardHandoff(phase: \(phase.rawValue), hasText: \(text != nil))"
    }
}

/// Where the app leaves the status and the finished text for the keyboard.
public protocol KeyboardHandoffPublishing: Sendable {
    func publish(_ handoff: KeyboardHandoff)
    func clear()
}

public enum ActionDictationStatus: Equatable, Sendable {
    case writing
    case failed
}

/// The Live Activity that iOS requires for the whole of a recording started
/// without opening the app (`AudioRecordingIntent`).
@MainActor
public protocol ActionDictationPresenting: Sendable {
    func begin() throws
    func show(_ status: ActionDictationStatus) async
    func end() async
}

/// Time to finish work once the microphone has stopped keeping the app alive.
@MainActor
public protocol BackgroundTimeRequesting: Sendable {
    func begin(onExpire: @escaping @MainActor () -> Void)
    func end()
}

/// Whether a dictation is running with another app in front. Audio and
/// recognition settings are read off the main actor, so this is thread-safe:
/// `lock` guards the only mutable value.
public final class BackgroundDictationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    public init() {}

    public var isActive: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }
}
