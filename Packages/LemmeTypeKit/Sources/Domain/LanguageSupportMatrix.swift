import Foundation

/// How far a language has been checked (E9-S1). Raw values are stable.
public enum LanguageSupportStatus: String, Codable, Sendable {
    /// Selectable and expected to work, but quality has not been measured and
    /// approved. The UI says so.
    case evaluation
    /// Measured against the review rubric and approved (see ``LanguageSupportRow/measurement``).
    case validated
}

/// One tested combination of language, engine, and task.
public struct LanguageSupportRow: Equatable, Sendable {
    public let language: String
    public let engine: RecognitionEngineID
    public let task: RecognitionTask
    /// The model size recommended for this combination. Smaller models still
    /// run; Settings points out when a larger one is recommended.
    public let recommendedTier: ModelTier
    public let status: LanguageSupportStatus
    /// Where the approved measurement is recorded. Required for `validated`.
    public let measurement: String?
}

/// The published support matrix (E9-S1, docs/decisions/0023-multilingual-dictation.md).
/// It is the single source for what the app calls supported: a language is
/// `validated` only with a recorded measurement.
public enum LanguageSupportMatrix {
    private static let englishMeasurement = "docs/testing/performance-thresholds.md (E2-S10, E5-S7)"

    public static let rows: [LanguageSupportRow] = [
        // English dictation was measured and accepted in Epics 2 and 5.
        row("en", .appleSpeech, .transcribe, .balanced, .validated, englishMeasurement),
        row("en", .whisper, .transcribe, .balanced, .validated, englishMeasurement),
        // Indian languages: expected to need Small; nothing is measured yet.
        row("hi", .whisper, .transcribe, .mostAccurate, .evaluation),
        row("hi", .whisper, .translateToEnglish, .mostAccurate, .evaluation),
        row("te", .whisper, .transcribe, .mostAccurate, .evaluation),
        row("te", .whisper, .translateToEnglish, .mostAccurate, .evaluation),
    ]

    private static func row(
        _ language: String, _ engine: RecognitionEngineID, _ task: RecognitionTask, _ tier: ModelTier,
        _ status: LanguageSupportStatus, _ measurement: String? = nil
    ) -> LanguageSupportRow {
        LanguageSupportRow(
            language: language, engine: engine, task: task, recommendedTier: tier, status: status,
            measurement: measurement)
    }

    /// The row for a language (any BCP 47 identifier) and task on `engine`.
    public static func row(
        language: String, task: RecognitionTask, engine: RecognitionEngineID = .whisper
    ) -> LanguageSupportRow? {
        let code = SpokenLanguages.code(of: language)
        return rows.first { $0.language == code && $0.task == task && $0.engine == engine }
    }

    /// The least-validated status across every row for `language`, or `nil`
    /// when the language is not in the matrix.
    public static func status(of language: String) -> LanguageSupportStatus? {
        let code = SpokenLanguages.code(of: language)
        let statuses = rows.filter { $0.language == code }.map(\.status)
        guard !statuses.isEmpty else { return nil }
        return statuses.contains(.evaluation) ? .evaluation : .validated
    }
}
