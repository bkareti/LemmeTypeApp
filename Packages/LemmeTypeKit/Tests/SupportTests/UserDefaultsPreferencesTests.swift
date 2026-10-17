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

/// E3-S1: context switches and exclusions; identifiers only, never text.
struct ContextPreferencesTests {
    @Test func contextDefaults() throws {
        let suite = "ContextPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsPreferences(defaults: defaults)
        #expect(!preferences.usesFormattingContext)
        #expect(preferences.allowsVoiceEditing)
        #expect(preferences.contextExcludedApplications.isEmpty)
    }

    @Test func contextPreferences() throws {
        let suite = "ContextPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsPreferences(defaults: defaults)
        preferences.usesFormattingContext = true
        preferences.allowsVoiceEditing = false
        preferences.contextExcludedApplications = ["com.tinyspeck.slackmacgap"]

        let reloaded = UserDefaultsPreferences(defaults: defaults)
        #expect(reloaded.contextPolicy.usesFormattingContext)
        #expect(!reloaded.contextPolicy.allowsVoiceEditing)
        #expect(reloaded.contextPolicy.excludedApplications == ["com.tinyspeck.slackmacgap"])
        // Only flags and bundle identifiers are stored.
        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(stored.keys) == ["usesFormattingContext", "allowsVoiceEditing", "contextExcludedApplications"])
    }
}

/// E4-S5: the Epic 2 writing mode migrates to the matching built-in mode.
struct DictationModePreferencesTests {
    @Test func defaultModeFollowsTheOldWritingModeUntilChosen() throws {
        let suite = "DictationModePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsPreferences(defaults: defaults)
        #expect(preferences.dictationMode == .exact)
        preferences.writingMode = .clean
        #expect(UserDefaultsPreferences(defaults: defaults).dictationMode == .clean)

        let custom = DictationModeID(rawValue: "custom-abc")
        preferences.dictationMode = custom
        #expect(UserDefaultsPreferences(defaults: defaults).dictationMode == custom)
        // Only the identifier is stored, never a mode's settings or name.
        #expect(defaults.string(forKey: "dictationMode") == "custom-abc")
    }
}
