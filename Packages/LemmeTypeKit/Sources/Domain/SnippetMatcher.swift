/// Whole-utterance snippet matching (E4-S3).
///
/// A snippet expands only when everything the user said is its trigger, so a
/// trigger inside a longer sentence never expands by accident. Letter case,
/// surrounding whitespace, and punctuation an engine adds at either end
/// ("Sign off.") are ignored.
public enum SnippetMatcher {
    /// The snippet whose trigger is the whole `transcript`, if any.
    public static func match(_ transcript: String, in snippets: [Snippet]) -> Snippet? {
        let spoken = key(transcript)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { key($0.trigger) == spoken }
    }

    /// The comparison key: lower-cased, whitespace collapsed, and edge
    /// punctuation removed.
    public static func key(_ text: String) -> String {
        let phrase = PersonalizationText.key(text)
        let trimmed = phrase.drop(while: isEdgePunctuation).reversed().drop(while: isEdgePunctuation).reversed()
        return PersonalizationText.normalizedPhrase(String(trimmed))
    }

    private static func isEdgePunctuation(_ character: Character) -> Bool {
        character.isWhitespace || (character.isPunctuation && character != "#" && character != "@")
    }
}
