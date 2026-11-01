import Domain
import Foundation

/// What a permission is for, in four short parts (E6-S5). Used by onboarding,
/// Settings › Permissions, and Settings › Privacy so the three never disagree.
struct PermissionExplanation: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Why LemmeType asks.
    let why: String
    /// What it reads or uses.
    let reads: String
    /// What it never does.
    let never: String
    /// How to turn it off again.
    let turnOff: String

    /// The short text shown beside a permission row.
    var summary: String { "\(why) \(never)" }

    /// Every permission LemmeType can use, including Speech Recognition (which
    /// is not a ``PermissionKind``: only Apple Speech needs it).
    static var all: [PermissionExplanation] {
        PermissionKind.allCases.map { explanation(for: $0) } + [speechRecognition]
    }

    static func explanation(for permission: PermissionKind) -> PermissionExplanation {
        switch permission {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    static var microphone: PermissionExplanation {
        PermissionExplanation(
            id: "microphone", name: String(localized: "Microphone", bundle: .module),
            why: String(localized: "LemmeType needs the microphone to hear what you dictate.", bundle: .module),
            reads: String(
                localized: "It listens only while you hold or toggle the dictation shortcut.", bundle: .module),
            never: String(
                localized:
                    "It never listens in the background. Your voice is turned into text on this Mac, and the recording is deleted afterwards.",
                bundle: .module),
            turnOff: String(
                localized: "Turn it off in System Settings › Privacy & Security › Microphone.", bundle: .module))
    }

    static var accessibility: PermissionExplanation {
        PermissionExplanation(
            id: "accessibility", name: String(localized: "Accessibility", bundle: .module),
            why: String(
                localized: "LemmeType needs Accessibility to type your dictated text into the app you were using.",
                bundle: .module),
            reads: String(
                localized:
                    "It finds the text box you were in. If you turn on context, it also reads a few words around your cursor, once, when you start.",
                bundle: .module),
            never: String(
                localized:
                    "It never reads password fields, never watches what you type, and never saves what it reads.",
                bundle: .module),
            turnOff: String(
                localized: "Turn it off in System Settings › Privacy & Security › Accessibility.", bundle: .module))
    }

    static var speechRecognition: PermissionExplanation {
        PermissionExplanation(
            id: "speech", name: String(localized: "Speech Recognition", bundle: .module),
            why: String(
                localized: "Apple’s speech engine needs this permission. You only see it if you choose that engine.",
                bundle: .module),
            reads: String(
                localized: "It turns your recording into text, using the speech model built into your Mac.",
                bundle: .module),
            never: String(
                localized: "LemmeType only uses the on-device mode, so your audio is not sent to Apple.",
                bundle: .module),
            turnOff: String(
                localized: "Turn it off in System Settings › Privacy & Security › Speech Recognition.",
                bundle: .module))
    }
}

/// One kind of data: what it is, where it lives, how long, and how to remove it.
struct PrivacyDataItem: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let what: String
    let location: String
    let duration: String
    let removal: String
}

/// The plain-language page behind Settings › Privacy › Overview (E6-S5).
/// The facts come from ADR 0025; change them together.
enum PrivacyText {
    static var intro: String {
        String(
            localized:
                "LemmeType works on this Mac. This page says what it uses, what it keeps, and how to remove it.",
            bundle: .module)
    }

    static var contextExplanation: String {
        String(
            localized:
                "Context is off until you turn it on. When you start dictating, LemmeType reads up to 240 characters before the cursor and 40 after it, once. It uses them to fix spacing and capital letters. They stay on this Mac, are never saved, and are forgotten when the dictation ends. Password fields and password managers are always skipped, and you can skip other apps too.",
            bundle: .module)
    }

    static var network: String {
        String(
            localized:
                "Recording, speech recognition, cleanup, and rewriting never use the internet. LemmeType connects only to download a model you choose, after you confirm its size, and to look for a new version when you ask.",
            bundle: .module)
    }

    static var updates: String {
        String(
            localized:
                "Looking for a new version sends your app’s version number and, like any web request, your IP address to GitHub. LemmeType never downloads or installs an update by itself. It opens the release page in your browser.",
            bundle: .module)
    }

    static var analytics: String {
        String(
            localized:
                "LemmeType has no analytics, no tracking, and no account. Nothing about how you use it is sent anywhere.",
            bundle: .module)
    }

    static var backups: String {
        String(
            localized:
                "Files LemmeType keeps live in your Mac’s Application Support folder, readable only by your account. Time Machine backs them up if you use it, and FileVault protects them when your Mac is locked.",
            bundle: .module)
    }

    static var dataItems: [PrivacyDataItem] {
        [
            PrivacyDataItem(
                id: "audio", name: String(localized: "Your recording", bundle: .module),
                what: String(localized: "The sound of your voice while you dictate.", bundle: .module),
                location: String(localized: "A private temporary file on this Mac.", bundle: .module),
                duration: String(
                    localized: "Deleted as soon as the text is delivered, cancelled, or fails.", bundle: .module),
                removal: String(
                    localized: "Automatic. Any leftovers are removed when LemmeType starts.", bundle: .module)),
            PrivacyDataItem(
                id: "text", name: String(localized: "Dictated text", bundle: .module),
                what: String(localized: "The words LemmeType writes for you.", bundle: .module),
                location: String(
                    localized: "Memory, then the app you chose, or the clipboard if you copy it.", bundle: .module),
                duration: String(
                    localized: "Not kept, unless you turn on history.", bundle: .module),
                removal: String(localized: "Nothing to remove.", bundle: .module)),
            PrivacyDataItem(
                id: "context", name: String(localized: "Text near your cursor", bundle: .module),
                what: String(localized: "A few words around the cursor, if you turn on context.", bundle: .module),
                location: String(localized: "Memory only.", bundle: .module),
                duration: String(localized: "Until the dictation ends.", bundle: .module),
                removal: String(localized: "Nothing to remove.", bundle: .module)),
            PrivacyDataItem(
                id: "history",
                name: String(
                    localized: "History", bundle: .module,
                    comment: "Noun: the list of dictations the user chose to keep"),
                what: String(
                    localized: "The text you inserted or copied, with the time. Off unless you turn it on.",
                    bundle: .module),
                location: String(localized: "A private file on this Mac.", bundle: .module),
                duration: String(localized: "As long as you choose, or until you delete it.", bundle: .module),
                removal: String(localized: "Privacy › History, or Delete All Local Data below.", bundle: .module)),
            PrivacyDataItem(
                id: "personalization", name: String(localized: "Your words and modes", bundle: .module),
                what: String(
                    localized: "Vocabulary, replacements, snippets, modes, and app rules you add.", bundle: .module),
                location: String(localized: "A private file on this Mac.", bundle: .module),
                duration: String(localized: "Until you delete it.", bundle: .module),
                removal: String(
                    localized: "Dictation › Delete All, or Delete All Local Data below.", bundle: .module)),
            PrivacyDataItem(
                id: "diagnostics", name: String(localized: "Diagnostics", bundle: .module),
                what: String(
                    localized: "A short list of recent events, such as “recording stopped”. It has no words or audio.",
                    bundle: .module),
                location: String(localized: "Memory only.", bundle: .module),
                duration: String(
                    localized: "Until you quit LemmeType. You can save a report to share.", bundle: .module),
                removal: String(localized: "Quit LemmeType, or Delete All Local Data below.", bundle: .module)),
            PrivacyDataItem(
                id: "models", name: String(localized: "Downloaded models", bundle: .module),
                what: String(localized: "Speech models you chose to download.", bundle: .module),
                location: String(localized: "A folder on this Mac.", bundle: .module),
                duration: String(localized: "Until you remove them.", bundle: .module),
                removal: String(
                    localized: "Dictation › Models, or Delete All Local Data below.", bundle: .module)),
        ]
    }
}
