/// An API key. Its description is redacted so string interpolation cannot leak it.
public struct CloudCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let secret: String

    public init(secret: String) {
        self.secret = secret
    }

    public var description: String { "CloudCredential(redacted)" }
    public var debugDescription: String { description }
}

/// Where the engine finds the key for a provider. `nil` means none is stored,
/// and the engine then reports that it cannot run.
public protocol CloudCredentialProviding: Sendable {
    func credential(for provider: CloudSpeechProviderID) async -> CloudCredential?
}
