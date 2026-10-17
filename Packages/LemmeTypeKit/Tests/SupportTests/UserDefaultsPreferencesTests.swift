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

struct DictationPreferencesTests {
    @Test func dictationLanguageDefaultsToUSEnglishAndPersists() throws {
        let suite = "DictationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserDefaultsPreferences(defaults: defaults).dictationLanguage == "en-US")
        UserDefaultsPreferences(defaults: defaults).dictationLanguage = "en-GB"
        #expect(UserDefaultsPreferences(defaults: defaults).dictationLanguage == "en-GB")
    }

    @Test func writingModeAndEngineDefaultToExactAndAutomatic() throws {
        let suite = "DictationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsPreferences(defaults: defaults)
        #expect(preferences.writingMode == .exact)
        #expect(preferences.selectedEngine == nil)
        preferences.writingMode = .clean
        preferences.selectedEngine = .whisper
        let reloaded = UserDefaultsPreferences(defaults: defaults)
        #expect(reloaded.writingMode == .clean)
        #expect(reloaded.selectedEngine == .whisper)
        reloaded.selectedEngine = nil
        #expect(UserDefaultsPreferences(defaults: defaults).selectedEngine == nil)
    }

    @Test func clipboardFallbackDefaultsToPasteAndRestore() throws {
        let suite = "ClipboardPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserDefaultsPreferences(defaults: defaults).clipboardFallback == .default)
        let policy = ClipboardFallbackPolicy(fallback: .copyOnly, restoreDelay: 1)
        UserDefaultsPreferences(defaults: defaults).clipboardFallback = policy
        #expect(UserDefaultsPreferences(defaults: defaults).clipboardFallback == policy)
    }
}
