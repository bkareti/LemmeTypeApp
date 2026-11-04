import Foundation

/// Public pages the app links to. Opening one is always the user's choice; the app
/// itself never fetches them.
public enum PublicLinks {
    /// The privacy policy App Review requires inside the app (Guideline 5.1.1). It is the
    /// same text as `docs/privacy-policy.md`.
    public static let privacyPolicy =
        URL(string: "https://github.com/bkareti/LemmeTypeApp/blob/main/docs/privacy-policy.md")
        ?? URL(fileURLWithPath: "/")
    /// Help and contact (`docs/support.md`).
    public static let support =
        URL(string: "https://github.com/bkareti/LemmeTypeApp/blob/main/docs/support.md")
        ?? URL(fileURLWithPath: "/")
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
