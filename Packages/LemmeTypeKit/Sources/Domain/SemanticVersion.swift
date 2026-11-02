import Foundation

/// A Semantic Versioning 2.0 version such as `0.2.0` or `1.0.0-beta.2` (E7-S3).
/// Build metadata (`+…`) is accepted and ignored, as the specification says.
public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// The dot-separated pre-release identifiers; empty for a release.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `1.2.3`, `v1.2.3`, `1.2.3-beta.1`, and `1.2.3+45`. A missing patch
    /// (`1.2`) counts as `0`. Anything else is `nil`.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        var core = rest
        var tail: Substring?
        if let dash = rest.firstIndex(of: "-") {
            core = rest[..<dash]
            tail = rest[rest.index(after: dash)...]
        }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(numbers.count), numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        var identifiers: [String] = []
        if let tail {
            identifiers = tail.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let valid = identifiers.allSatisfy {
                !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            }
            guard valid else { return nil }
        }
        self.init(
            major: numbers[0] ?? 0, minor: numbers[1] ?? 0, patch: numbers.count == 3 ? (numbers[2] ?? 0) : 0,
            prerelease: identifiers)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false  // a release is newer than its pre-releases
        case (false, true): return true
        case (false, false): return precedes(lhs.prerelease, rhs.prerelease)
        }
    }

    /// Pre-release precedence: numeric identifiers compare as numbers and rank
    /// below alphanumeric ones; a shorter list that matches so far ranks lower.
    private static func precedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case (let leftNumber?, let rightNumber?): return leftNumber < rightNumber
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.count < rhs.count
    }
}
