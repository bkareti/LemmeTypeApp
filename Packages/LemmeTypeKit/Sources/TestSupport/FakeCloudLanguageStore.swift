import Domain
import Synchronization

/// Keeps the Cloud speech language list in memory, standing in for preferences.
public final class FakeCloudLanguageStore: CloudLanguageStoring {
    private let state: Mutex<[String]?>

    public init(_ languages: [String]? = nil) {
        state = Mutex(languages)
    }

    public var cloudLanguages: [String]? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
