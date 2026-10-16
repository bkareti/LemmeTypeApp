import Foundation
import Support
import Testing

struct UserDefaultsPreferencesTests {
    @Test func onboardingFlagPersistsAcrossInstances() throws {
        let suite = "UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!UserDefaultsPreferences(defaults: defaults).hasCompletedOnboarding)
        UserDefaultsPreferences(defaults: defaults).hasCompletedOnboarding = true
        #expect(UserDefaultsPreferences(defaults: defaults).hasCompletedOnboarding)
    }
}
