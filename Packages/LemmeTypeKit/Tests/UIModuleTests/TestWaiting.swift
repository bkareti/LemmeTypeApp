import Foundation

/// Waits until `condition` holds, polling, for at most `timeout`. Tests use it
/// instead of a fixed sleep so a slow CI runner cannot make them flaky.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
