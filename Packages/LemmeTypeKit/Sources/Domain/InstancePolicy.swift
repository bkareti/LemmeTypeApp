import Foundation

/// Decides which copy of LemmeType keeps running when more than one is launched.
///
/// The earliest-launched instance wins so that two simultaneous launches cannot
/// both yield (and leave nothing running) or both stay (and fight over the
/// microphone and shortcut).
public enum InstancePolicy {
    public struct Instance: Equatable, Sendable {
        public let processIdentifier: Int32
        public let launchDate: Date?

        public init(processIdentifier: Int32, launchDate: Date?) {
            self.processIdentifier = processIdentifier
            self.launchDate = launchDate
        }
    }

    /// Returns the instance the current process should hand over to, or `nil`
    /// if the current process should keep running.
    public static func instanceToYieldTo(current: Instance, others: [Instance]) -> Instance? {
        others
            .filter { $0.processIdentifier != current.processIdentifier }
            .filter { isEarlier($0, than: current) }
            .min { isEarlier($0, than: $1) }
    }

    private static func isEarlier(_ lhs: Instance, than rhs: Instance) -> Bool {
        let lhsDate = lhs.launchDate ?? .distantPast
        let rhsDate = rhs.launchDate ?? .distantPast
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.processIdentifier < rhs.processIdentifier
    }
}
