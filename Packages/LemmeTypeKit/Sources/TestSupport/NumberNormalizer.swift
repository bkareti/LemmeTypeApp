import Foundation

/// Makes numbers comparable before scoring: FLEURS references write "1911" and
/// "12" while speakers say words, and engines write either. Applied to both
/// reference and hypothesis, so it never favours one side.
///
/// - Decimal digits of any script (Devanagari १२, Telugu ౧౨, …) become ASCII.
/// - Thousands separators between digits are dropped: "1,000" → "1000".
/// - Runs of English number words become digits, case and the rest of the text
///   untouched: "twenty-three" → "23", "one hundred and five" → "105",
///   "two thousand" → "2000", and year-style pairs "nineteen eleven" → "1911".
///
/// Not handled: Hindi, Telugu, Kannada, and Tamil number words, ordinals,
/// decimals ("three point five"), and percent signs. Reports show WER with and
/// without this normalization so its effect is visible.
public enum NumberNormalizer {
    public static func normalize(_ text: String) -> String {
        let folded = foldingDigits(text)
            .replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        return spokenNumbersToDigits(folded)
    }

    /// Any decimal digit becomes its ASCII digit.
    static func foldingDigits(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue,
                (0...9).contains(Int(value))
            {
                scalars.append(Unicode.Scalar(UInt8(48 + Int(value))))
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // MARK: Number words

    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90,
    ]
    static let scales: [String: Int] = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]

    static func isNumberWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        return units[lower] != nil || tens[lower] != nil || scales[lower] != nil || lower == "hundred"
    }

    /// Replaces each maximal run of number words (joined by spaces, hyphens, or
    /// "and" before a smaller part) with its value.
    static func spokenNumbersToDigits(_ text: String) -> String {
        let pattern = #"[A-Za-z]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        let words = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range)
        var output = ""
        var cursor = 0
        var index = 0
        while index < words.count {
            let start = index
            var run: [String] = []
            var end = index
            while end < words.count {
                let word = source.substring(with: words[end])
                let gap =
                    end == start
                    ? ""
                    : source.substring(
                        with: NSRange(
                            location: NSMaxRange(words[end - 1]),
                            length: words[end].location - NSMaxRange(words[end - 1])))
                guard end == start || gap == " " || gap == "-" else { break }
                if isNumberWord(word) {
                    run.append(word.lowercased())
                    end += 1
                } else if word.lowercased() == "and", !run.isEmpty, end + 1 < words.count,
                    isNumberWord(source.substring(with: words[end + 1])),
                    run.last == "hundred" || scales[run.last ?? ""] != nil
                {
                    end += 1
                } else {
                    break
                }
            }
            guard !run.isEmpty, let value = value(of: run) else {
                // A run that is not one number stays words, all of it.
                index = max(index + 1, end)
                continue
            }
            let first = words[start]
            let last = words[end - 1]
            output += source.substring(with: NSRange(location: cursor, length: first.location - cursor))
            output += value
            cursor = NSMaxRange(last)
            index = end
        }
        output += source.substring(from: cursor)
        return output
    }

    /// The digits for a run of number words, or `nil` when it does not form one number
    /// ("five six" stays words: it could be a phone number or a list).
    static func value(of run: [String]) -> String? {
        if let year = yearStyle(run) { return year }
        if run == ["zero"] { return "0" }
        var number = SpokenNumber()
        for word in run where !number.add(word) { return nil }
        return String(number.value)
    }

    /// What the previous number word was.
    private enum SpokenPart { case start, unit, ten, hundred, scale }

    /// Reads one number word at a time: [units hundred] [tens] [units], each group times a scale.
    private struct SpokenNumber {
        var total = 0
        var group = 0
        var last = SpokenPart.start

        var value: Int { total + group }

        /// `false` when the word cannot continue this number.
        mutating func add(_ word: String) -> Bool {
            if let unit = NumberNormalizer.units[word], unit > 0 { return addUnit(unit) }
            if let ten = NumberNormalizer.tens[word] { return addTen(ten) }
            if word == "hundred" { return addHundred() }
            if let scale = NumberNormalizer.scales[word] { return addScale(scale) }
            return false
        }

        private mutating func addUnit(_ unit: Int) -> Bool {
            let fits =
                switch last {
                case .start, .hundred, .scale: group % 100 == 0
                case .ten: unit < 10
                case .unit: false
                }
            guard fits else { return false }
            group += unit
            last = .unit
            return true
        }

        private mutating func addTen(_ ten: Int) -> Bool {
            guard last == .start || last == .hundred || last == .scale, group % 100 == 0 else { return false }
            group += ten
            last = .ten
            return true
        }

        private mutating func addHundred() -> Bool {
            guard last == .unit || last == .ten, (1...99).contains(group) else { return false }
            group *= 100
            last = .hundred
            return true
        }

        private mutating func addScale(_ scale: Int) -> Bool {
            guard group > 0, last != .scale else { return false }
            total += group * scale
            group = 0
            last = .scale
            return true
        }
    }

    /// "nineteen eleven" → 1911, "twenty twenty-four" → 2024: two parts of 10…99 with no scale word.
    static func yearStyle(_ run: [String]) -> String? {
        guard run.count >= 2, run.count <= 4, !run.contains("hundred"), !run.contains(where: { scales[$0] != nil })
        else { return nil }
        for split in 1..<run.count {
            guard let first = value(ofSmall: Array(run[..<split])), let second = value(ofSmall: Array(run[split...])),
                (10...99).contains(first), (10...99).contains(second), first != 10
            else { continue }
            return String(first * 100 + second)
        }
        return nil
    }

    /// 0…99 from one or two words ("twenty", "twenty four", "eleven").
    static func value(ofSmall words: [String]) -> Int? {
        switch words.count {
        case 1: return units[words[0]] ?? tens[words[0]]
        case 2:
            guard let ten = tens[words[0]], let unit = units[words[1]], (1...9).contains(unit) else { return nil }
            return ten + unit
        default: return nil
        }
    }
}
