import Foundation

/// Whether an on-device rewriter can run now (E3-S4,
/// docs/decisions/0018-on-device-rewriting.md).
public enum RewriterAvailability: Equatable, Sendable {
    case ready
    /// Apple Intelligence is turned off in System Settings.
    case notEnabled
    /// This Mac cannot run the on-device model.
    case deviceNotEligible
    /// The model is still downloading or preparing.
    case modelNotReady
    /// The model does not support the requested language.
    case unsupportedLanguage
    /// Unavailable for another reason (for example a newer OS state).
    case unavailable

    public var isReady: Bool { self == .ready }

    /// Stable lowercase name for diagnostics.
    public var identifier: String {
        switch self {
        case .ready: "ready"
        case .notEnabled: "not-enabled"
        case .deviceNotEligible: "device-not-eligible"
        case .modelNotReady: "model-not-ready"
        case .unsupportedLanguage: "unsupported-language"
        case .unavailable: "unavailable"
        }
    }
}

/// One rewrite: apply a spoken instruction to the selected text. In memory only.
public struct RewriteRequest: Sendable {
    public let instruction: String
    public let text: String
    /// BCP 47 language of the instruction (the dictation language).
    public let language: String

    public init(instruction: String, text: String, language: String) {
        self.instruction = instruction
        self.text = text
        self.language = language
    }
}

extension RewriteRequest: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "RewriteRequest(redacted)" }
    public var debugDescription: String { description }
}

public enum RewriteError: LemmeTypeError, Equatable {
    case unavailable(RewriterAvailability)
    /// The text and instruction do not fit in the model's context.
    case tooLong
    /// The model's safety guardrails or a refusal stopped the rewrite.
    case refused
    /// The model returned nothing usable.
    case emptyResult
    /// The model is busy with another request.
    case busy
    case cancelled
    case failed

    public var identifier: String {
        switch self {
        case .unavailable(let availability): "rewrite.\(availability.identifier)"
        case .tooLong: "rewrite.too-long"
        case .refused: "rewrite.refused"
        case .emptyResult: "rewrite.empty-result"
        case .busy: "rewrite.busy"
        case .cancelled: "rewrite.cancelled"
        case .failed: "rewrite.failed"
        }
    }

    /// Trying again unchanged can help.
    public var isRetryable: Bool {
        switch self {
        case .busy, .failed, .emptyResult, .unavailable(.modelNotReady): true
        default: false
        }
    }
}

/// A local language model that rewrites text (E3-S4). Implementations must
/// run on device, make no network request, and keep nothing after
/// `rewrite` returns. Call through ``TextRewritingRunner``.
public protocol TextRewriting: Sendable {
    func availability(language: String) async -> RewriterAvailability
    /// Returns the rewritten text, or throws. Must honour task cancellation.
    func rewrite(_ request: RewriteRequest) async throws(RewriteError) -> String
}

/// Runs a rewriter with the guarantees callers rely on: a rewriter that is
/// not ready is never called, and a cancelled task never gets a result.
public struct TextRewritingRunner: Sendable {
    public init() {}

    public func run(_ rewriter: any TextRewriting, _ request: RewriteRequest) async throws(RewriteError) -> String {
        let availability = await rewriter.availability(language: request.language)
        guard availability.isReady else { throw .unavailable(availability) }
        if Task.isCancelled { throw .cancelled }
        let result: String
        do {
            result = try await rewriter.rewrite(request)
        } catch {
            if Task.isCancelled { throw .cancelled }
            throw error
        }
        if Task.isCancelled { throw .cancelled }
        guard result.contains(where: { !$0.isWhitespace }) else { throw .emptyResult }
        return result
    }
}

/// Cleans model output: trims, and removes wrapping quotes or a code fence
/// that the original text did not have. Pure, so every engine shares it.
public enum RewriteOutput {
    public static func clean(_ output: String, original: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), !original.contains("```"), text.count >= 6 {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] {
            let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2, text.hasPrefix(open), text.hasSuffix(close), !trimmedOriginal.hasPrefix(open) {
                text = String(text.dropFirst().dropLast())
            }
        }
        return text
    }
}
