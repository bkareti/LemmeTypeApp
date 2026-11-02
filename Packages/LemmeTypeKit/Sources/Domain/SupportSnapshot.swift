import Foundation

/// Where this build came from (ADR 0026).
public enum DistributionChannel: String, Codable, Sendable {
    /// A Release build downloaded from GitHub Releases.
    case direct
    /// A Debug build from a developer's checkout.
    case development
}

/// Settings that help support, expressed as identifiers and flags only (E7-S5).
/// Nothing the user wrote or said: no language names for modes, no text, no paths.
public struct SupportSnapshot: Equatable, Sendable {
    public var channel: DistributionChannel
    public var previousRunEndedUnexpectedly: Bool
    /// Identifiers of installed models, such as `whisper-base-en`.
    public var installedModels: [String]
    /// A lowercase language code or `auto`.
    public var dictationLanguage: String
    /// `original` or `english`.
    public var speechOutput: String
    public var performanceProfile: String
    public var historyRetention: String
    public var updateChecksWeekly: Bool

    public init(
        channel: DistributionChannel = .development, previousRunEndedUnexpectedly: Bool = false,
        installedModels: [String] = [], dictationLanguage: String = "en-us", speechOutput: String = "original",
        performanceProfile: String = "automatic", historyRetention: String = "off", updateChecksWeekly: Bool = false
    ) {
        self.channel = channel
        self.previousRunEndedUnexpectedly = previousRunEndedUnexpectedly
        self.installedModels = installedModels.sorted()
        self.dictationLanguage = dictationLanguage
        self.speechOutput = speechOutput
        self.performanceProfile = performanceProfile
        self.historyRetention = historyRetention
        self.updateChecksWeekly = updateChecksWeekly
    }

    public static let empty = SupportSnapshot()
}
