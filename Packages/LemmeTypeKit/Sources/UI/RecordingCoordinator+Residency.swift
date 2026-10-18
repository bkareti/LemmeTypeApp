import Domain

/// Model residency around sessions (E5-S4): busy while recording or
/// processing, idle afterwards. Calls run in order, one after another, so an
/// "idle" can never overtake the next session's "busy".
extension RecordingCoordinator {
    func markResidencyBusy(warmingUp: Bool) {
        guard let residency else { return }
        let preferred = activeSettings?.enginePreference.selected
        let language = activeSettings?.language ?? preferences.dictationLanguage
        enqueueResidency {
            await residency.sessionBusy()
            if warmingUp {
                await residency.warmUp(preferred: preferred, language: language)
            }
        }
    }

    func markResidencyIdle() {
        guard let residency else { return }
        enqueueResidency { await residency.sessionIdle() }
    }

    /// Waits for queued residency calls. For tests.
    public func settleResidency() async {
        await residencyQueue?.value
    }

    private func enqueueResidency(_ work: @escaping @Sendable () async -> Void) {
        let previous = residencyQueue
        residencyQueue = Task {
            await previous?.value
            await work()
        }
    }
}
