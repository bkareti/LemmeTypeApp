import Foundation
import Testing

@testable import UI

/// E7-S7: text that shows a date follows the reader's locale. Sizes and lists use
/// the same `.formatted(...)` styles everywhere; `scripts/check-localization.py`
/// fails on hand-built formats, so these cover the one helper that takes a locale.
@MainActor
struct LocalizationFormattingTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15, 08:00 UTC

    @Test func historyDatesFollowTheLocale() {
        let american = HistorySettingsModel.when(date, locale: Locale(identifier: "en_US"))
        let german = HistorySettingsModel.when(date, locale: Locale(identifier: "de_DE"))
        let japanese = HistorySettingsModel.when(date, locale: Locale(identifier: "ja_JP"))
        #expect(american != german && german != japanese && american != japanese)
        #expect(german.contains("2027"))
        #expect(japanese.contains("2027"))
    }

    @Test func theSameLocaleGivesTheSameText() {
        let locale = Locale(identifier: "fr_FR")
        #expect(HistorySettingsModel.when(date, locale: locale) == HistorySettingsModel.when(date, locale: locale))
    }

    @Test func listsAndSizesUseLocaleAwareStyles() {
        let english = ["a", "b", "c"].formatted(.list(type: .and).locale(Locale(identifier: "en_US")))
        let spanish = ["a", "b", "c"].formatted(.list(type: .and).locale(Locale(identifier: "es_ES")))
        #expect(english != spanish, "the joining word is the locale's own")
        let american = Int64(1_500_000).formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US")))
        let german = Int64(1_500_000).formatted(.byteCount(style: .file).locale(Locale(identifier: "de_DE")))
        #expect(american != german, "decimal separators follow the locale")
    }
}
