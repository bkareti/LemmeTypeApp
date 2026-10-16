import Domain
import Synchronization

/// In-memory `AppPreferences`.
public final class FakePreferences: AppPreferences {
    private let completed: Mutex<Bool>

    public init(hasCompletedOnboarding: Bool = false) {
        completed = Mutex(hasCompletedOnboarding)
    }

    public var hasCompletedOnboarding: Bool {
        get { completed.withLock { $0 } }
        set { completed.withLock { $0 = newValue } }
    }
}
