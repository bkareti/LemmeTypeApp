import Domain
import Testing

/// E9-S1: the published matrix is consistent with the catalog and engines, and
/// never claims more than has been measured.
struct LanguageSupportMatrixTests {
    @Test func theSelectableLanguagesAreTheEvaluationSet() {
        #expect(SpokenLanguages.all.map(\.code) == ["en", "hi", "te"])
        for notYet in ["ta", "ml", "kn"] {
            #expect(SpokenLanguages.language(for: notYet) == nil)
            #expect(LanguageSupportMatrix.status(of: notYet) == nil)
        }
    }

    @Test func englishIsValidatedAndTheIndianLanguagesAreOnlyUnderEvaluation() {
        #expect(LanguageSupportMatrix.status(of: "en-GB") == .validated)
        #expect(LanguageSupportMatrix.status(of: "hi") == .evaluation)
        #expect(LanguageSupportMatrix.status(of: "te") == .evaluation)
    }

    @Test func noRowIsValidatedWithoutAMeasurementRecord() {
        for row in LanguageSupportMatrix.rows {
            switch row.status {
            case .validated: #expect(row.measurement?.isEmpty == false, "\(row.language) \(row.task)")
            case .evaluation: #expect(row.measurement == nil, "\(row.language) is evaluation but has a record")
            }
        }
    }

    @Test func everyRowHasACatalogModelThatServesIt() {
        for row in LanguageSupportMatrix.rows where row.engine == .whisper {
            let models = ModelCatalog.whisperModels.filter { $0.serves(language: row.language, task: row.task) }
            #expect(!models.isEmpty, "no catalog model serves \(row.language) \(row.task)")
            #expect(
                models.contains { $0.tier == row.recommendedTier },
                "recommended tier \(row.recommendedTier) has no model for \(row.language) \(row.task)")
        }
    }

    @Test func everyListedLanguageHasAtLeastOneRow() {
        for language in SpokenLanguages.all {
            #expect(LanguageSupportMatrix.status(of: language.code) != nil, "\(language.code)")
        }
    }

    @Test func translationRowsExistOnlyForNonEnglishLanguages() {
        for row in LanguageSupportMatrix.rows where row.task == .translateToEnglish {
            #expect(row.language != "en")
        }
        #expect(LanguageSupportMatrix.row(language: "hi", task: .translateToEnglish) != nil)
        #expect(LanguageSupportMatrix.row(language: "en", task: .translateToEnglish) == nil)
    }

    @Test func languageIdentifiersResolveToTheirBaseCode() {
        #expect(SpokenLanguages.code(of: "en-US") == "en")
        #expect(SpokenLanguages.code(of: "HI") == "hi")
        #expect(SpokenLanguages.isEnglish("en-IN"))
        #expect(!SpokenLanguages.isEnglish("hi"))
        #expect(SpokenLanguages.isAutomatic("auto"))
        #expect(SpokenLanguages.language(for: "te")?.nativeName == "తెలుగు")
    }
}
