import Domain
import UI

/// Runs the weekly update check, when the user turned it on (ADR 0026), and the
/// user-started check from the menu. Owns the timer; nothing runs unless asked.
@MainActor
final class UpdatesController {
    let checker: any UpdateChecking
    let model: UpdatesSettingsModel
    private var weeklyTask: Task<Void, Never>?

    init(checker: any UpdateChecking, model: UpdatesSettingsModel) {
        self.checker = checker
        self.model = model
    }

    /// Looks at the schedule now and every few hours while the app runs. A check
    /// is made only if the weekly setting is on and a week has passed.
    func startWeeklySchedule() {
        weeklyTask?.cancel()
        weeklyTask = Task { [checker, model] in
            while !Task.isCancelled {
                await checker.checkIfDue()
                await model.refresh()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func stop() {
        weeklyTask?.cancel()
        weeklyTask = nil
    }
}
