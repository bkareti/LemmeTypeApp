#if DEBUG
    import Domain
    import Foundation

    /// The choices of one corpus evaluation, read from text: the environment of the Mac's
    /// opt-in `CorpusEvaluationTests`, or the launch arguments of the iPhone and iPad app's
    /// on-device evaluation. One parser, so both name modes, styles, tasks, and languages alike.
    public enum EvaluationOptions {
        public enum Problem: Error, Equatable {
            case unknownMode(String)
            case unknownStyle(String)
            case unknownTask(String)
        }

        /// A built-in mode (`exact`, `clean`, `message`), or Clean Writing with a style written
        /// `tone-format-length`, such as `professional-email-concise`.
        public static func mode(_ builtIn: String = "clean", style: String? = nil) throws(Problem) -> DictationMode {
            guard let base = DictationMode.builtIns.first(where: { $0.id.rawValue == builtIn }) else {
                throw .unknownMode(builtIn)
            }
            guard let style else { return base }
            let parts = style.split(separator: "-").map(String.init)
            guard parts.count >= 3, let tone = Tone(rawValue: parts[0]),
                let format = WritingFormat(rawValue: parts[1..<(parts.count - 1)].joined(separator: "-")),
                let length = LengthPreference(rawValue: parts[parts.count - 1])
            else { throw .unknownStyle(style) }
            let options = StyleOptions(tone: tone, format: format, length: length)
            return DictationMode(
                id: DictationModeID(rawValue: "style-\(options.identifier)"), name: "Style \(options.identifier)",
                writingMode: .clean, style: options)
        }

        /// `transcribe` (the default) or `translate-to-english`.
        public static func task(_ text: String?) throws(Problem) -> RecognitionTask {
            let text = text ?? RecognitionTask.transcribe.rawValue
            guard let task = RecognitionTask(rawValue: text) else { throw .unknownTask(text) }
            return task
        }

        /// A comma-separated list such as `hi,te`; `nil` (every language) when absent or empty.
        public static func languages(_ text: String?) -> Set<String>? {
            let codes = Set(
                (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
                    !$0.isEmpty
                })
            return codes.isEmpty ? nil : codes
        }
    }
#endif
