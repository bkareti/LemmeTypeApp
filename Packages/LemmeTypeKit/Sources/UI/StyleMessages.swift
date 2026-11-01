import Domain
import Foundation

/// User-facing words for tone, format, length, and rewrite reviews (E10-S2,
/// E10-S4). Never includes dictated text.
extension Tone {
    var displayName: String {
        switch self {
        case .neutral: String(localized: "Neutral", bundle: .module)
        case .professional: String(localized: "Professional", bundle: .module)
        case .friendly: String(localized: "Friendly", bundle: .module)
        case .casual: String(localized: "Casual", bundle: .module)
        }
    }
}

extension WritingFormat {
    var displayName: String {
        switch self {
        case .plainText: String(localized: "Plain text", bundle: .module)
        case .message: String(localized: "Message", bundle: .module)
        case .email: String(localized: "Email", bundle: .module)
        case .bulletList: String(localized: "Bullet list", bundle: .module)
        }
    }
}

extension LengthPreference {
    var displayName: String {
        switch self {
        case .original: String(localized: "Original", bundle: .module)
        case .concise: String(localized: "Concise", bundle: .module)
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
