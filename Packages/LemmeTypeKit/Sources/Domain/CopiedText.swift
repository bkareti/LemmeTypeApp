import Foundation

/// How long copied text stays on the pasteboard before the system removes it
/// (ADR 0027). Short, because the user is about to paste it.
public enum CopiedTextLifetime: Int, CaseIterable, Codable, Sendable {
    case oneMinute = 60
    case twoMinutes = 120
    case tenMinutes = 600

    public static let `default` = CopiedTextLifetime.twoMinutes

    /// The preference key the choice is stored under.
    public static let storageKey = "copiedTextLifetime"

    /// The stored choice, or the default when nothing valid is stored.
    public static func stored(in defaults: UserDefaults) -> CopiedTextLifetime {
        CopiedTextLifetime(rawValue: defaults.integer(forKey: storageKey)) ?? .default
    }

    public var seconds: TimeInterval { TimeInterval(rawValue) }
}

/// The general pasteboard on a phone: the item stays on this device (no
/// Universal Clipboard) and expires after `lifetime` seconds.
@MainActor
public protocol ExpiringPasteboardWriting: Sendable {
    func write(_ text: String, lifetime: TimeInterval)
}

/// Copies reviewed text for the user to paste into another app. It only runs
/// when the user chooses Copy; it never sends anything. The text is never logged.
public struct ExpiringTextCopier: TextCopying {
    private let writer: any ExpiringPasteboardWriting
    private let lifetime: @Sendable () -> CopiedTextLifetime

    public init(
        writer: any ExpiringPasteboardWriting,
        lifetime: @escaping @Sendable () -> CopiedTextLifetime = { .default }
    ) {
        self.writer = writer
        self.lifetime = lifetime
    }

    public func copy(_ text: String) async {
        await writer.write(text, lifetime: lifetime().seconds)
    }
}

/// Delivery for a platform that cannot insert into another app: dictation has
/// no target, so there is nothing to deliver to. Results reach the user only
/// through an explicit copy.
public struct NoTargetDelivery: TextDelivering {
    public init() {}

    public func deliver(_ text: String, to target: ActivationTarget?) async -> DeliveryOutcome {
        .problem(.noTarget)
    }
}
