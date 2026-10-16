import Domain
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

struct ShortcutPreferencesTests {
    @Test func shortcutAndModePersist() throws {
        let suite = "ShortcutPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = KeyboardShortcut(keyCode: 0x02, modifiers: [.control, .option], keyLabel: "D")

        let preferences = UserDefaultsPreferences(defaults: defaults)
        #expect(preferences.dictationShortcut == nil)
        #expect(preferences.activationMode == .pushToTalk)
        preferences.dictationShortcut = shortcut
        preferences.activationMode = .toggle

        let reloaded = UserDefaultsPreferences(defaults: defaults)
        #expect(reloaded.dictationShortcut == shortcut)
        #expect(reloaded.activationMode == .toggle)
    }
}
