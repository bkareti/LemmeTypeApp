import Foundation

/// Structured, privacy-safe diagnostics.
///
/// Redaction is enforced by the types rather than by convention: event names
/// and attribute keys must be compile-time literals, and values are limited to
/// counts, flags, durations, and identifiers that match a strict pattern. Audio,
/// transcripts, field or clipboard text, file contents, device or app names,
/// and vocabulary cannot be represented.
public enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case permissions
    case shortcut
    case audio
    case recorder
    case recognition
    case models
    case delivery
    case editing
    case personalization
    case history
}

public enum DiagnosticValue: Codable, Equatable, Sendable {
    /// A lowercase identifier (enum case, error identifier, state name).
    case identifier(String)
    case count(Int)
    case flag(Bool)
    case seconds(Double)

    public static let redactedIdentifier = "redacted"

    /// Accepts `^[a-z0-9][a-z0-9._-]{0,63}$`; anything else becomes `"redacted"`.
    public static func id(_ raw: String) -> DiagnosticValue {
        .identifier(isSafeIdentifier(raw) ? raw : redactedIdentifier)
    }

    public static func isSafeIdentifier(_ raw: String) -> Bool {
        guard let first = raw.unicodeScalars.first, raw.unicodeScalars.count <= 64 else { return false }
        let lower = Unicode.Scalar("a").value...Unicode.Scalar("z").value
        let digit = Unicode.Scalar("0").value...Unicode.Scalar("9").value
        guard lower.contains(first.value) || digit.contains(first.value) else { return false }
        return raw.unicodeScalars.allSatisfy {
            lower.contains($0.value) || digit.contains($0.value) || $0 == "." || $0 == "_" || $0 == "-"
        }
    }
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let category: DiagnosticCategory
    public let name: String
    public let attributes: [String: DiagnosticValue]

    public init(
        timestamp: Date,
        category: DiagnosticCategory,
        name: StaticString,
        attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {
        self.timestamp = timestamp
        self.category = category
        self.name = name.description
        var values: [String: DiagnosticValue] = [:]
        for (key, value) in attributes {
            // Re-validate so a hand-built `.identifier` cannot bypass redaction.
            if case .identifier(let raw) = value {
                values[key.description] = .id(raw)
            } else {
                values[key.description] = value
            }
        }
        self.attributes = values
    }
}

/// Records diagnostic events. Implementations must never block the caller.
public protocol DiagnosticsRecording: Sendable {
    func record(
        _ category: DiagnosticCategory,
        _ name: StaticString,
        _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    )
}

extension DiagnosticsRecording {
    public func record(_ category: DiagnosticCategory, _ name: StaticString) {
        record(category, name, [:])
    }
}

/// Default for components created without diagnostics (tests, previews).
public struct DiscardingDiagnostics: DiagnosticsRecording {
    public init() {}

    public func record(
        _ category: DiagnosticCategory,
        _ name: StaticString,
        _ attributes: KeyValuePairs<StaticString, DiagnosticValue>
    ) {}
}

/// The exportable report. Only fields listed here can ever leave the app.
/// Schema 2 (E7-S5) added the support fields; every one is an identifier or a flag.
public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    /// A report with a full event buffer stays under 1 MB (E7-S5), small enough to attach anywhere.
    public static let maximumEncodedBytes = 1_048_576

    public let schemaVersion: Int
    public let generatedAt: Date
    public let appVersion: String
    public let appBuild: String
    public let distributionChannel: String
    public let osVersion: String
    public let hardwareModel: String
    public let permissions: [String: String]
    public let activationMode: String
    public let previousRunEndedUnexpectedly: Bool
    public let installedModels: [String]
    public let dictationLanguage: String
    public let speechOutput: String
    public let performanceProfile: String
    public let historyRetention: String
    public let updateChecksWeekly: Bool
    public let events: [DiagnosticEvent]

    public init(
        generatedAt: Date,
        appVersion: String,
        appBuild: String,
        osVersion: String,
        hardwareModel: String,
        permissions: [String: String],
        activationMode: String,
        events: [DiagnosticEvent],
        support: SupportSnapshot = .empty
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.distributionChannel = support.channel.rawValue
        self.osVersion = osVersion
        self.hardwareModel = hardwareModel
        self.permissions = permissions
        self.activationMode = activationMode
        self.previousRunEndedUnexpectedly = support.previousRunEndedUnexpectedly
        self.installedModels = support.installedModels
        self.dictationLanguage = support.dictationLanguage
        self.speechOutput = support.speechOutput
        self.performanceProfile = support.performanceProfile
        self.historyRetention = support.historyRetention
        self.updateChecksWeekly = support.updateChecksWeekly
        self.events = events
    }
}
