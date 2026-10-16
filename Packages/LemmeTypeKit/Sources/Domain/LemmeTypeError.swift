/// Base protocol for every expected failure in LemmeType.
///
/// The ``identifier`` is a stable, dotted, lowercase string (for example
/// `"audio.device-unavailable"`). It appears in diagnostics and support
/// conversations, so it must never change once shipped and must never contain
/// user data.
public protocol LemmeTypeError: Error, Sendable {
    var identifier: String { get }
}
