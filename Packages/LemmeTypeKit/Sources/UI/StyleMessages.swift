import Domain
import Foundation

/// User-facing words for tone, format, length, and rewrite reviews (E10-S2,
/// E10-S4). Never includes dictated text.
extension Tone {
    var displayName: String {
        switch self {
        case .neutral: String(localized: "Neutral", bundle: .module, comment: "Adjective: no change of tone")
        case .professional:
            String(localized: "Professional", bundle: .module, comment: "Adjective: a formal tone for rewritten text")
        case .friendly:
            String(localized: "Friendly", bundle: .module, comment: "Adjective: a warm tone for rewritten text")
        case .casual:
            String(localized: "Casual", bundle: .module, comment: "Adjective: a relaxed tone for rewritten text")
        }
    }
}

extension WritingFormat {
    var displayName: String {
        switch self {
        case .plainText:
            String(localized: "Plain text", bundle: .module, comment: "Noun: text without any special shape")
        case .message:
            String(
                localized: "Message", bundle: .module,
                comment: "Noun: a short chat-style message format and a built-in mode name")
        case .email: String(localized: "Email", bundle: .module, comment: "Noun: an email-shaped text format")
        case .bulletList:
            String(localized: "Bullet list", bundle: .module, comment: "Noun: text turned into a bulleted list")
        }
    }
}

extension LengthPreference {
    var displayName: String {
        switch self {
        case .original:
            String(
                localized: "Original", bundle: .module,
                comment: "Adjective: the text exactly as recognised, before any rewrite")
        case .concise: String(localized: "Concise", bundle: .module, comment: "Adjective: shorter rewritten text")
        }
    }
}

extension StyleOptions {
    /// "Professional · Email · Concise": the choices that change the text.
    var summary: String {
        var parts: [String] = []
        if tone != .neutral { parts.append(tone.displayName) }
        if format != .plainText { parts.append(format.displayName) }
        if length != .original { parts.append(length.displayName) }
        return parts.joined(separator: " · ")
    }
}

extension RewriteNotice {
    /// Why the original is offered instead of a rewrite.
    var userMessage: String {
        switch self {
        case .unavailable(let availability):
            String(
                localized:
                    "Not rewritten: \(availability.rewriteReason) Your original text is shown; nothing was lost.",
                bundle: .module)
        case .refused:
            String(
                localized: "Not rewritten: the on-device model declined. Your original text is shown.",
                bundle: .module)
        case .tooLong:
            String(
                localized: "Not rewritten: the text is too long for the on-device model. Your original text is shown.",
                bundle: .module)
        case .failed:
            String(
                localized: "Not rewritten: the rewrite didn’t work. Your original text is shown.", bundle: .module)
        case .meaningChanged:
            String(
                localized:
                    "Not rewritten: the rewrite changed a name, number, date, or commitment, so it was not used. Your original text is shown.",
                bundle: .module)
        }
    }
}

extension RewriterAvailability {
    /// A short reason, ending in a full stop, for the rewrite notice.
    var rewriteReason: String {
        switch self {
        case .ready: String(localized: "it is ready.", bundle: .module)
        case .notEnabled: String(localized: "Apple Intelligence is turned off.", bundle: .module)
        case .deviceNotEligible: String(localized: "this Mac can’t run Apple’s on-device model.", bundle: .module)
        case .modelNotReady: String(localized: "Apple’s on-device model is still getting ready.", bundle: .module)
        case .unsupportedLanguage:
            String(localized: "the on-device model doesn’t support this language.", bundle: .module)
        case .unavailable: String(localized: "the on-device model isn’t available.", bundle: .module)
        }
    }
}
