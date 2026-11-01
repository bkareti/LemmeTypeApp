import Foundation

/// How long dictation history is kept (E6-S3, ADR 0025). Off by default:
/// nothing is stored until the user chooses a period.
public enum HistoryRetention: String, CaseIterable, Codable, Sendable {
    case off
    case oneDay = "one-day"
    case oneWeek = "one-week"
    case oneMonth = "one-month"
    case untilDeleted = "until-deleted"

    public var isOn: Bool { self != .off }

    /// How old an entry may get; `nil` means no age limit (the entry cap still applies).
    public var maximumAge: TimeInterval? {
        switch self {
        case .off: 0
        case .oneDay: 24 * 3600
        case .oneWeek: 7 * 24 * 3600
        case .oneMonth: 30 * 24 * 3600
        case .untilDeleted: nil
        }
    }

    /// Stable lowercase name for diagnostics.
    public var identifier: String { rawValue }
}

/// How the recorded text reached the user.
public enum HistoryDelivery: String, Codable, Sendable {
    case inserted
    case copied
}

/// One dictation the user accepted. Holds only the final text and plain facts
/// about it — never audio, text from before a rewrite, cursor context, the
/// selection, or the app (ADR 0025).
public struct DictationHistoryEntry: Identifiable, Codable, Equatable, Sendable, CustomStringConvertible {
    public let id: UUID
    public let createdAt: Date
    /// The text the user accepted by Insert or Copy.
    public let text: String
    /// Identifier of the dictation mode (never its name, which the user wrote).
    public let mode: String
    /// BCP 47 identifier or `auto`.
    public let language: String
    public let delivery: HistoryDelivery
    public let words: Int

    public init(
        id: UUID = UUID(), createdAt: Date, text: String, mode: String, language: String,
        delivery: HistoryDelivery
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.mode = mode
        self.language = language
        self.delivery = delivery
        self.words = text.split(whereSeparator: \.isWhitespace).count
    }

    /// The text never appears in logs or reports.
    public var description: String { "DictationHistoryEntry(<redacted>)" }
}

/// The recorded dictations, newest first. A pure value: every change keeps the
/// entry cap and the ordering.
public struct DictationHistory: Equatable, Sendable {
    /// At most this many entries are kept; the oldest go first.
    public static let entryLimit = 1_000
    /// Longer results are not recorded rather than cut short.
    public static let maximumTextLength = 20_000

    public private(set) var entries: [DictationHistoryEntry]

    public static let empty = DictationHistory()

    public init(entries: [DictationHistoryEntry] = []) {
        self.entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(Self.entryLimit))
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    public mutating func append(_ entry: DictationHistoryEntry) {
        self = DictationHistory(entries: entries + [entry])
    }

    /// Removes the entry; returns whether it existed.
    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != before
    }

    public mutating func removeAll() {
        entries = []
    }

    /// How many entries a `retention` period would remove at `now`.
    public func expiredCount(for retention: HistoryRetention, now: Date) -> Int {
        guard let age = retention.maximumAge else { return 0 }
        return entries.filter { now.timeIntervalSince($0.createdAt) > age }.count
    }

    /// Removes entries older than `retention` allows; returns how many.
    @discardableResult
    public mutating func purge(for retention: HistoryRetention, now: Date) -> Int {
        guard let age = retention.maximumAge else { return 0 }
        let before = entries.count
        entries.removeAll { now.timeIntervalSince($0.createdAt) > age }
        return before - entries.count
    }
}

/// Why history could not be read, written, or exported. Never carries text.
public enum DictationHistoryError: LemmeTypeError, Equatable {
    /// The stored file could not be read; it was moved aside, not overwritten.
    case unreadable
    /// The file was written by a newer LemmeType.
    case unsupportedVersion
    case storageFailure

    public var identifier: String {
        switch self {
        case .unreadable: "history.unreadable"
        case .unsupportedVersion: "history.unsupported-version"
        case .storageFailure: "history.storage-failure"
        }
    }
}

/// The versioned file format of the history, used by the local store and by
/// export. Readable JSON; keys never change within a format version.
public struct DictationHistoryArchive: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let formatName = "com.lemmetype.history"

    public var format: String
    public var formatVersion: Int
    public var entries: [DictationHistoryEntry]

    public init(_ history: DictationHistory) {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        entries = history.entries
    }

    /// Pretty-printed JSON with sorted keys and ISO 8601 dates.
    public func encoded() throws(DictationHistoryError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(self)
        } catch {
            throw .storageFailure
        }
    }

    /// The history in `data`, or why it cannot be used. A newer version is
    /// refused, never rewritten.
    public static func decode(_ data: Data) throws(DictationHistoryError) -> DictationHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: DictationHistoryArchive
        do {
            archive = try decoder.decode(DictationHistoryArchive.self, from: data)
        } catch {
            throw .unreadable
        }
        guard archive.format == formatName else { throw .unreadable }
        guard archive.formatVersion <= currentFormatVersion else { throw .unsupportedVersion }
        return DictationHistory(entries: archive.entries)
    }
}

/// What loading the history produced.
public struct DictationHistoryLoad: Equatable, Sendable {
    public let history: DictationHistory
    /// Set when the stored file could not be used; it was kept, moved aside.
    public let issue: DictationHistoryError?

    public init(history: DictationHistory, issue: DictationHistoryError? = nil) {
        self.history = history
        self.issue = issue
    }
}

/// Keeps the history on this Mac (ADR 0025). Implementations never log the
/// entries and never overwrite a file they could not read.
public protocol DictationHistoryStoring: Sendable {
    /// The stored history, or an empty one when nothing is stored. Reads only:
    /// it never creates files.
    func load() async -> DictationHistoryLoad
    /// Replaces the stored history atomically.
    func save(_ history: DictationHistory) async throws(DictationHistoryError)
    /// Deletes the stored history and any unreadable copies moved aside.
    func deleteAll() async throws(DictationHistoryError)
}

/// Receives each result the user accepted. A no-op when history is off.
public protocol DictationHistoryRecording: Sendable {
    func record(_ text: String, for session: DictationSession, delivery: HistoryDelivery) async
}

/// The default recorder for components created without history (tests, previews).
public struct DiscardingHistory: DictationHistoryRecording {
    public init() {}

    public func record(_ text: String, for session: DictationSession, delivery: HistoryDelivery) async {}
}

/// What the Privacy pane shows.
public struct DictationHistorySnapshot: Equatable, Sendable {
    public let retention: HistoryRetention
    public let entries: [DictationHistoryEntry]
    /// Set when the stored file could not be read.
    public let issue: DictationHistoryError?

    public init(retention: HistoryRetention, entries: [DictationHistoryEntry], issue: DictationHistoryError?) {
        self.retention = retention
        self.entries = entries
        self.issue = issue
    }
}

/// Reads and changes the history for the Settings pane.
public protocol DictationHistoryManaging: DictationHistoryRecording {
    func snapshot() async -> DictationHistorySnapshot
    /// Removes entries the current retention has expired; a no-op when history is off.
    func purgeExpired() async
    /// How many entries `retention` would delete right now (for confirmations).
    func entriesRemoved(by retention: HistoryRetention) async -> Int
    /// Stores the choice and deletes what it expires (everything for `off`).
    func apply(_ retention: HistoryRetention) async throws(DictationHistoryError)
    func delete(_ id: UUID) async throws(DictationHistoryError)
    func deleteAll() async throws(DictationHistoryError)
    /// The versioned JSON the user may save.
    func exportData() async throws(DictationHistoryError) -> Data
}
