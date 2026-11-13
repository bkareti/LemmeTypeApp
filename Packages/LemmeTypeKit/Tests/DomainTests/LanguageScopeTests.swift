import Domain
import Testing

/// ADR 0029: what an English-only build offers.
struct LanguageScopeTests {
    @Test func englishOnlyOffersEveryEnglishRegionAndNothingElse() {
        let scope = LanguageScope.englishOnly
        #expect(scope.offers(language: "en-US"))
        #expect(scope.offers(language: "en-GB"))
        #expect(scope.offers(language: "en"))
        #expect(!scope.offers(language: "hi"))
        #expect(!scope.offers(language: "te"))
        #expect(!scope.offers(language: SpokenLanguages.automatic), "detection chooses among other languages")
    }

    @Test func englishOnlyHasNothingToTranslate() {
        #expect(LanguageScope.englishOnly.speechOutputs == [.original])
        #expect(LanguageScope.allLanguages.speechOutputs == SpeechOutput.allCases)
    }

    @Test func englishOnlyListsOnlyTheEnglishModels() {
        let listed = ModelCatalog.all.filter(LanguageScope.englishOnly.lists).map(\.id)
        #expect(listed == [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish])
        #expect(ModelCatalog.all.filter(LanguageScope.allLanguages.lists).count == ModelCatalog.all.count)
    }

    @Test func allLanguagesOffersEverything() {
        for language in SpokenLanguages.all.map(\.settingValue) + [SpokenLanguages.automatic] {
            #expect(LanguageScope.allLanguages.offers(language: language))
        }
    }

    @Test func theCloudScopeOffersEnglishAndTeluguOnly() {
        let scope = LanguageScope.englishWithCloud
        #expect(scope.offers(language: "en-US"))
        #expect(scope.offers(language: "te"))
        #expect(!scope.offers(language: "hi"))
        #expect(!scope.offers(language: SpokenLanguages.automatic))
        #expect(scope.speechOutputs == [.original])
        let listed = ModelCatalog.all.filter(scope.lists).map(\.id)
        #expect(listed == [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish], "no multilingual download")
    }
}
