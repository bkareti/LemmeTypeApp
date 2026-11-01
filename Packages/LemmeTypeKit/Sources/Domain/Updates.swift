import Foundation

/// A published release the update check can offer (E7-S3, ADR 0026). Only
/// metadata: the app never downloads or runs a release.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    /// The release's page on GitHub; the user opens it in a browser.
    public let pageURL: URL
    public let isPrerelease: Bool

    public init(version: SemanticVersion, pageURL: URL, isPrerelease: Bool) {
        self.version = version
        self.pageURL = pageURL
        self.isPrerelease = isPrerelease
    }
}

/// Why an update check could not finish. Stable identifiers; never carries a
/// response body or any text from the network.
public enum UpdateError: LemmeTypeError, Equatable {
    /// No connection, or GitHub could not be reached in time.
    case offline
    /// GitHub limited the request; try again later.
    case rateLimited
    /// The answer was not a release list this version understands.
    case badResponse
    /// The answer was larger than the limit.
    case tooLarge
    /// A release pointed somewhere other than this project's releases page.
    case untrustedLink
    /// This build's own version could not be read.
    case unknownVersion

    public var identifier: String {
        switch self {
        case .offline: "update.offline"
        case .rateLimited: "update.rate-limited"
        case .badResponse: "update.bad-response"
        case .tooLarge: "update.too-large"
        case .untrustedLink: "update.untrusted-link"
        case .unknownVersion: "update.unknown-version"
        }
    }
}

/// Where release metadata comes from. The only implementation uses the network
/// (module `Updates`); tests use a fake.
public protocol UpdateFeed: Sendable {
    /// Published, non-draft releases, newest first as the source orders them.
    func releases() async throws(UpdateError) -> [ReleaseInfo]
}

/// What the update check knows.
public enum UpdateStatus: Equatable, Sendable {
    /// Not checked yet in this run.
    case unknown
    case checking
    case upToDate(checkedAt: Date)
    case available(ReleaseInfo, checkedAt: Date)
    /// The project has not published a release (or none is newer than a pre-release build).
    case noReleases(checkedAt: Date)
    case failed(UpdateError, checkedAt: Date)
    /// A dictation session is active; nothing was requested.
    case deferred

    public var checkedAt: Date? {
        switch self {
        case .upToDate(let date), .noReleases(let date): date
        case .available(_, let date), .failed(_, let date): date
        case .unknown, .checking, .deferred: nil
        }
    }

    public var identifier: String {
        switch self {
        case .unknown: "unknown"
        case .checking: "checking"
        case .upToDate: "up-to-date"
        case .available: "available"
        case .noReleases: "no-releases"
        case .failed(let error, _): error.identifier
        case .deferred: "deferred"
        }
    }
}

/// Checks for a newer version. Only ever called because the user asked, or
/// because they turned on the weekly check.
public protocol UpdateChecking: Sendable {
    var status: UpdateStatus { get async }
    /// A check the user asked for.
    @discardableResult
    func checkNow() async -> UpdateStatus
    /// The weekly check: does nothing unless the user turned it on and a week has passed.
    func checkIfDue() async
}
