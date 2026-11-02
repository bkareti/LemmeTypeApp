import Domain
import Foundation
import Testing

@testable import UI

/// E6-S5: every permission and every kind of stored data is explained, and the
/// explanations stay plain. The reading check is a floor — short sentences and
/// no jargon — not proof that a person understands; MA-57 has a human read it.
struct PrivacyTextTests {
    static let bannedTerms = [
        "TCC", "AX", "API", "SHA", "plist", "entitlement", "entitlements", "sandbox", "daemon", "kernel", "keychain",
        "heuristic", "serialize", "payload", "binary",
    ]
    static let longestSentence = 25

    /// Sentences longer than the limit and banned terms found in `text`.
    static func problems(in text: String) -> [String] {
        var found: [String] = []
        let sentences = text.split { ".?!\n".contains($0) }
        for sentence in sentences {
            let words = sentence.split(whereSeparator: \.isWhitespace)
            if words.count > longestSentence { found.append("long sentence (\(words.count) words): \(sentence)") }
            for word in words {
                let bare = word.trimmingCharacters(in: .punctuationCharacters)
                if bannedTerms.contains(where: { $0.caseInsensitiveCompare(bare) == .orderedSame }) {
                    found.append("jargon “\(bare)” in: \(sentence)")
                }
            }
        }
        return found
    }

    // MARK: The checker itself

    @Test func theCheckerFlagsLongSentencesAndJargon() {
        let long = Array(repeating: "word", count: 30).joined(separator: " ") + "."
        #expect(!Self.problems(in: long).isEmpty)
        #expect(!Self.problems(in: "LemmeType asks TCC for the entitlement.").isEmpty)
        #expect(Self.problems(in: "LemmeType listens only while you hold the shortcut.").isEmpty)
    }

    // MARK: Permissions

    @Test func everyPermissionHasAllFourParts() {
        let kinds = Set(PermissionKind.allCases.map(\.rawValue))
        let explained = Set(PermissionExplanation.all.map(\.id))
        #expect(kinds.isSubset(of: explained), "every PermissionKind is explained")
        #expect(explained.contains("speech"), "Speech Recognition is explained")
        for explanation in PermissionExplanation.all {
            #expect(!explanation.name.isEmpty, "\(explanation.id) name")
            #expect(!explanation.why.isEmpty, "\(explanation.id) why")
            #expect(!explanation.reads.isEmpty, "\(explanation.id) reads")
            #expect(!explanation.never.isEmpty, "\(explanation.id) never")
            #expect(!explanation.turnOff.isEmpty, "\(explanation.id) turnOff")
        }
    }

    @Test func permissionIdsAreUnique() {
        let ids = PermissionExplanation.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func theRowTextIsTheSharedSummary() {
        for permission in PermissionKind.allCases {
            #expect(permission.explanation == PermissionExplanation.explanation(for: permission).summary)
        }
    }

    @Test func theMicrophoneAndAccessibilityTextsSayWhatTheyNeverDo() {
        #expect(PermissionExplanation.microphone.never.contains("never listens in the background"))
        #expect(PermissionExplanation.accessibility.never.contains("never reads password fields"))
        #expect(PermissionExplanation.speechRecognition.never.contains("not sent"))
    }

    // MARK: The data page

    @Test func theInventoryCoversEveryKindOfData() {
        let ids = Set(PrivacyText.dataItems.map(\.id))
        #expect(ids == ["audio", "text", "context", "history", "personalization", "diagnostics", "models"])
        for item in PrivacyText.dataItems {
            #expect(!item.what.isEmpty && !item.location.isEmpty && !item.duration.isEmpty && !item.removal.isEmpty)
        }
    }

    @Test func theHistoryRowSaysItIsOffUnlessTurnedOn() throws {
        let history = try #require(PrivacyText.dataItems.first { $0.id == "history" })
        #expect(history.what.contains("Off unless you turn it on"))
    }

    @Test func everyPrivacyTextIsPlainLanguage() {
        var texts = [
            PrivacyText.intro, PrivacyText.contextExplanation, PrivacyText.network, PrivacyText.analytics,
            PrivacyText.backups,
        ]
        for explanation in PermissionExplanation.all {
            texts += [explanation.why, explanation.reads, explanation.never, explanation.turnOff]
        }
        for item in PrivacyText.dataItems { texts += [item.what, item.location, item.duration, item.removal] }
        let problems = texts.flatMap(Self.problems(in:))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func theNetworkTextPromisesNoUseDuringDictationAndNoAnalytics() {
        #expect(PrivacyText.network.contains("never use the internet"))
        #expect(PrivacyText.analytics.contains("no analytics"))
    }
}
