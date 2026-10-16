/// Chooses the engine for a new session. Only local engines exist, and the
/// choice never falls back silently to a different engine than the user picked.
public enum EngineSelector {
    public enum Choice: Equatable, Sendable {
        case engine(RecognitionEngineID)
        /// The user's chosen engine cannot run; `alternatives` are ready engines.
        case unavailable(RecognitionEngineID, EngineAvailability, alternatives: [RecognitionEngineID])
        case noneAvailable
    }

    /// - Parameters:
    ///   - preferred: The user's engine, or `nil` for Automatic.
    ///   - candidates: Every engine in recommendation order with its availability.
    /// - Returns: The engine to use, or why none can be used.
    public static func choose(
        preferred: RecognitionEngineID?,
        candidates: [(id: RecognitionEngineID, availability: EngineAvailability)]
    ) -> Choice {
        let ready = candidates.filter { $0.availability.isReady }.map(\.id)
        guard let preferred else {
            return ready.first.map(Choice.engine) ?? .noneAvailable
        }
        // An engine that no longer exists (for example after an update) is
        // treated as Automatic.
        guard let chosen = candidates.first(where: { $0.id == preferred }) else {
            return choose(preferred: nil, candidates: candidates)
        }
        if chosen.availability.isReady { return .engine(preferred) }
        return .unavailable(preferred, chosen.availability, alternatives: ready)
    }
}
