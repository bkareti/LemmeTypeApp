/// Chooses the engine for a new session. The choice never falls back silently
/// to a different engine than the user picked, and a cloud engine runs only
/// when it is the one the user picked (ADR 0031).
public enum EngineSelector {
    public enum Choice: Equatable, Sendable {
        case engine(RecognitionEngineID)
        /// The user's chosen engine cannot run; `alternatives` are ready engines.
        case unavailable(RecognitionEngineID, EngineAvailability, alternatives: [RecognitionEngineID])
        case noneAvailable
    }

    /// - Parameters:
    ///   - preferred: The user's engine, or `nil` for Automatic.
    ///   - fallsBackAutomatically: The user approved using another ready
    ///     engine when theirs isn't ready, instead of being asked.
    ///   - candidates: Every engine in recommendation order with its availability.
    /// - Returns: The engine to use, or why none can be used.
    public static func choose(
        preferred: RecognitionEngineID?,
        fallsBackAutomatically: Bool = false,
        candidates: [(id: RecognitionEngineID, availability: EngineAvailability)]
    ) -> Choice {
        let ready = candidates.filter { $0.availability.isReady && !$0.id.isCloud }.map(\.id)
        guard let preferred else {
            return ready.first.map(Choice.engine) ?? .noneAvailable
        }
        // An engine that no longer exists (for example after an update) is
        // treated as Automatic.
        guard let chosen = candidates.first(where: { $0.id == preferred }) else {
            return choose(preferred: nil, candidates: candidates)
        }
        if chosen.availability.isReady { return .engine(preferred) }
        if fallsBackAutomatically, let alternative = ready.first { return .engine(alternative) }
        return .unavailable(preferred, chosen.availability, alternatives: ready)
    }
}
