import Foundation
import Testing

@testable import UI

/// The licence texts shipped in the app match THIRD_PARTY_NOTICES.md (MIT requires them).
struct AcknowledgementsTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func everyLicenceInTheNoticesFileShipsInTheApp() throws {
        let notices = try String(
            contentsOf: Self.repository.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        let blocks = notices.components(separatedBy: "```").enumerated()
            .filter { $0.offset % 2 == 1 }
            .map { $0.element.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(blocks.count >= 2)
        let shipped = Acknowledgements.text
        for block in blocks {
            #expect(shipped.contains(block), "a licence in THIRD_PARTY_NOTICES.md is missing from the app")
        }
        #expect(shipped.contains("whisper.cpp"))
    }

    @Test func thePublicLinksPointAtTheWebsitePages() {
        #expect(PublicLinks.privacyPolicy.absoluteString == "https://lemmetype.com/privacy")
        #expect(PublicLinks.termsOfUse.absoluteString == "https://lemmetype.com/terms")
        // The ready-made Back Tap shortcut is Apple's shared-shortcut page, opened only when tapped (E8-S10).
        #expect(PublicLinks.backTapShortcut.host == "www.icloud.com")
        #expect(PublicLinks.backTapShortcut.path.hasPrefix("/shortcuts/"))
        #expect(PublicLinks.support.absoluteString == "https://lemmetype.com/support")
    }
}
