import Domain
import Synchronization

/// A scripted ``TextRewriting``: returns `result(instruction, text)` or throws.
public final class FakeTextRewriter: TextRewriting {
    public enum Script: Sendable {
        case uppercase
        case text(String)
        case failure(RewriteError)
    }

    private struct State {
        var availability: RewriterAvailability
        var script: Script
        var delay: Duration?
        var requests: [String] = []
    }

    private let state: Mutex<State>

    public init(availability: RewriterAvailability = .ready, script: Script = .uppercase, delay: Duration? = nil) {
        state = Mutex(State(availability: availability, script: script, delay: delay))
    }

    /// Instructions received, for assertions.
    public var instructions: [String] { state.withLock { $0.requests } }
    public var rewriteCount: Int { instructions.count }

    public func setAvailability(_ availability: RewriterAvailability) {
        state.withLock { $0.availability = availability }
    }

    public func availability(language: String) async -> RewriterAvailability {
        state.withLock { $0.availability }
    }

    public func rewrite(_ request: RewriteRequest) async throws(RewriteError) -> String {
        let (availability, script, delay) = state.withLock { state in
            state.requests.append(request.instruction)
            return (state.availability, state.script, state.delay)
        }
        guard availability.isReady else { throw .unavailable(availability) }
        if let delay {
            do { try await Task.sleep(for: delay) } catch { throw .cancelled }
        }
        switch script {
        case .uppercase: return request.text.uppercased()
        case .text(let text): return text
        case .failure(let error): throw error
        }
    }
}

/// Behaviour every ``TextRewriting`` implementation must show. Returns
/// violations instead of asserting, like ``RecognitionEngineContract``.
public enum TextRewriterContract {
    public static func verify(_ rewriter: any TextRewriting, language: String = "en-US") async -> [String] {
        var issues: [String] = []
        let availability = await rewriter.availability(language: language)
        if !DiagnosticValue.isSafeIdentifier(availability.identifier) {
            issues.append("availability identifier is not stable")
        }
        let request = RewriteRequest(instruction: "make it shorter", text: "contract check text", language: language)
        if !availability.isReady {
            do {
                _ = try await rewriter.rewrite(request)
                issues.append("rewriter returned text while \(availability.identifier)")
            } catch {
                if case .unavailable = error {
                } else if error != .cancelled {
                    issues.append("rewriter threw \(error.identifier) while \(availability.identifier)")
                }
            }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TextRewritingRunner().run(rewriter, request)
        }
        if (try? await cancelled.value) != nil {
            issues.append("a cancelled request produced a result")
        }
        if "\(request)".contains("contract check text") {
            issues.append("request description leaks text")
        }
        return issues
    }
}
