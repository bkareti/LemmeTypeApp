import Foundation

/// Public pages the app links to. Opening one is always the user's choice; the app
/// itself never fetches them.
public enum PublicLinks {
    /// The website that hosts the public pages (the `LemmeType-Web` repository, deployed on Vercel).
    static let website = "https://lemmetype.com"
    /// The privacy policy App Review requires inside the app (Guideline 5.1.1). It describes the same
    /// practices as `docs/privacy-policy.md`; change both together.
    public static let privacyPolicy = page("privacy")
    /// The terms of use the subscription paywall links to (Guideline 3.1.2), as in `docs/terms-of-use.md`.
    public static let termsOfUse = page("terms")
    /// Help and contact, as in `docs/support.md`.
    public static let support = page("support")
    /// Opens the Shortcuts app on a new shortcut, so a Back Tap shortcut can be made (Back Tap
    /// lists only the person's own shortcuts, not an app's built-in ones). Local only.
    public static let newShortcut = URL(string: "shortcuts://create-shortcut") ?? URL(fileURLWithPath: "/")
    /// The ready-made "Dictate Anywhere" shortcut (one action, `DictateAnywhereIntent`), shared from the
    /// maintainer's iCloud. Opening it shows Apple's Add Shortcut page, so Back Tap can list it after one tap.
    /// Apple's signature on it expires on 22 Dec 2027: share it again before then and replace this link.
    public static let backTapShortcut =
        URL(string: "https://www.icloud.com/shortcuts/1401a765eac547fc82021541697b2c0c") ?? URL(fileURLWithPath: "/")

    private static func page(_ path: String) -> URL {
        URL(string: "\(website)/\(path)") ?? URL(fileURLWithPath: "/")
    }
}

/// The open-source licences the app ships, read from the bundled `Acknowledgements.txt`.
/// MIT requires the notice in every copy, so the iPhone and iPad app shows it in
/// Settings › About (the Mac app shows `App/LemmeType/Credits.rtf`). Keep it in step
/// with `THIRD_PARTY_NOTICES.md`; `AcknowledgementsTests` checks that.
public enum Acknowledgements {
    public static var text: String {
        guard let url = Bundle.module.url(forResource: "Acknowledgements", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }
}
