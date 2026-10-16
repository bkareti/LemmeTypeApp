/// Small, non-sensitive app preferences persisted between launches.
public protocol AppPreferences: AnyObject, Sendable {
    var hasCompletedOnboarding: Bool { get set }
}
