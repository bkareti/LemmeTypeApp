/// Version information for display and diagnostics.
public struct BuildInfo: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Reads `CFBundleShortVersionString` and `CFBundleVersion`, falling back to
    /// `"unknown"` so a malformed bundle never crashes the app.
    public init(infoDictionary: [String: Any]?) {
        self.version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.build = infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    public var displayString: String {
        "\(version) (\(build))"
    }
}
