import Domain
import Foundation
import Testing

@testable import UI

/// E12-S3: how the grammar option and Proper English read in Settings.
struct StyleSummaryTests {
    @Test func theSummaryNamesGrammarCorrection() {
        #expect(StyleOptions(correctsGrammar: true).summary == "Correct grammar")
        #expect(StyleOptions(tone: .casual, correctsGrammar: true).summary == "Casual · Correct grammar")
        #expect(StyleOptions.none.summary.isEmpty)
    }

    @Test func properEnglishHasADisplayName() {
        #expect(DictationMode.properEnglish.displayName == "Proper English")
    }

    @Test func theModelNoticeNamesTheDeviceItRunsOn() {
        #expect(RewriterAvailability.deviceNotEligible.rewriteReason.hasPrefix(DeviceWords.thisDevice))
    }
}
