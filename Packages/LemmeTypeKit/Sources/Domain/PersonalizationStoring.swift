/// What loading the personalization store produced.
public struct PersonalizationLoad: Equatable, Sendable {
    public let library: PersonalizationLibrary
    /// Set when the stored file could not be used; it was kept, moved aside.
    public let issue: PersonalizationError?

    public init(library: PersonalizationLibrary, issue: PersonalizationError? = nil) {
        self.library = library
        self.issue = issue
    }
}

/// Keeps the personalization library on this Mac (E4-S1, ADR 0020).
///
/// Implementations never log or report the library's contents and never
/// overwrite a file they could not read.
public protocol PersonalizationStoring: Sendable {
    /// The stored library, or an empty one when nothing is stored. A file that
    /// cannot be read is moved aside and reported as ``PersonalizationError/unreadable``
    /// (or ``PersonalizationError/unsupportedVersion``).
    func load() async -> PersonalizationLoad
    /// Replaces the stored library atomically.
    func save(_ library: PersonalizationLibrary) async throws(PersonalizationError)
    /// Deletes the stored library and any unreadable copies moved aside (E4-S8).
    func deleteAll() async throws(PersonalizationError)
}
