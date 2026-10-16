import AppKit
import Domain
import Support

/// Puts text on the general pasteboard when the user chooses Copy. The text
/// is never logged.
public struct PasteboardTextCopier: TextCopying {
    public init() {}

    public func copy(_ text: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        Log.delivery.info("Transcript copied to the clipboard")
    }
}
