import Domain
import Foundation

/// What the add/edit sheet in Settings › Personalization is editing (E4-S4).
/// Two text fields cover every kind; the sheet labels them per kind.
struct PersonalizationDraft: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case vocabulary
        case replacement
        case snippet

        var id: String { rawValue }
    }

    let id: UUID
    let kind: Kind
    let isNew: Bool
    /// Term, spoken phrase, or trigger.
    var primary: String
    /// Comma-separated "sounds like" spellings, written text, or snippet text.
    var secondary: String

    static func new(_ kind: Kind) -> PersonalizationDraft {
        PersonalizationDraft(id: UUID(), kind: kind, isNew: true, primary: "", secondary: "")
    }

    init(id: UUID, kind: Kind, isNew: Bool, primary: String, secondary: String) {
        self.id = id
        self.kind = kind
        self.isNew = isNew
        self.primary = primary
        self.secondary = secondary
    }

    init(_ entry: VocabularyEntry) {
        self.init(
            id: entry.id, kind: .vocabulary, isNew: false, primary: entry.term,
            secondary: entry.soundsLike.joined(separator: ", "))
    }

    init(_ replacement: Replacement) {
        self.init(
            id: replacement.id, kind: .replacement, isNew: false, primary: replacement.spoken,
            secondary: replacement.written)
    }

    init(_ snippet: Snippet) {
        self.init(id: snippet.id, kind: .snippet, isNew: false, primary: snippet.trigger, secondary: snippet.expansion)
    }

    /// Validates and saves through `model`; the error to show, if any.
    @MainActor
    func save(in model: PersonalizationModel) -> PersonalizationError? {
        switch kind {
        case .vocabulary:
            let spellings = secondary.split(separator: ",").map(String.init)
            return model.save(VocabularyEntry(id: id, term: primary, soundsLike: spellings))
        case .replacement:
            return model.save(Replacement(id: id, spoken: primary, written: secondary))
        case .snippet:
            return model.save(Snippet(id: id, trigger: primary, expansion: secondary))
        }
    }
}
