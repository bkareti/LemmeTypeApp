import Domain
import Testing

/// E7-S3: version ordering for the update check.
struct SemanticVersionTests {
    struct ParseCase: Sendable {
        let text: String
        let expected: SemanticVersion
    }

    @Test(arguments: [
        ParseCase(text: "1.2.3", expected: .init(major: 1, minor: 2, patch: 3)),
        ParseCase(text: "v1.2.3", expected: .init(major: 1, minor: 2, patch: 3)),
        ParseCase(text: "V0.1.0", expected: .init(major: 0, minor: 1, patch: 0)),
        ParseCase(text: "1.2", expected: .init(major: 1, minor: 2, patch: 0)),
        ParseCase(text: "1.2.3+45", expected: .init(major: 1, minor: 2, patch: 3)),
        ParseCase(text: "1.0.0-beta.2", expected: .init(major: 1, minor: 0, patch: 0, prerelease: ["beta", "2"])),
        ParseCase(text: "v2.0.0-rc.1+7", expected: .init(major: 2, minor: 0, patch: 0, prerelease: ["rc", "1"])),
        ParseCase(text: "0.0.1-alpha", expected: .init(major: 0, minor: 0, patch: 1, prerelease: ["alpha"])),
    ])
    func parses(_ testCase: ParseCase) {
        #expect(SemanticVersion(testCase.text) == testCase.expected)
    }

    @Test(arguments: [
        "", "v", "1", "1.2.3.4", "a.b.c", "1.-2.3", "1.2.3-", "1.2.3-beta..1", "1.2.3-é", "unknown", "1.2.x",
    ])
    func rejects(text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test(arguments: [
        ("0.1.0", "0.2.0"), ("0.9.9", "1.0.0"), ("1.2.3", "1.2.4"), ("1.0.0-alpha", "1.0.0"),
        ("1.0.0-alpha", "1.0.0-alpha.1"), ("1.0.0-alpha.1", "1.0.0-alpha.beta"), ("1.0.0-alpha.beta", "1.0.0-beta"),
        ("1.0.0-beta", "1.0.0-beta.2"), ("1.0.0-beta.2", "1.0.0-beta.11"), ("1.0.0-beta.11", "1.0.0-rc.1"),
        ("1.0.0-rc.1", "1.0.0"), ("1.9.0", "1.10.0"),
    ])
    func orders(lower: String, higher: String) throws {
        let low = try #require(SemanticVersion(lower))
        let high = try #require(SemanticVersion(higher))
        #expect(low < high)
        #expect(!(high < low))
        #expect(high > low)
    }

    @Test func buildMetadataDoesNotChangeEquality() throws {
        #expect(SemanticVersion("1.2.3+1") == SemanticVersion("1.2.3+2"))
        #expect(!(try #require(SemanticVersion("1.2.3+1")) < #require(SemanticVersion("1.2.3+2"))))
    }

    @Test func preReleaseFlagAndDescription() throws {
        #expect(try #require(SemanticVersion("1.0.0-beta.1")).isPrerelease)
        #expect(try !#require(SemanticVersion("1.0.0")).isPrerelease)
        #expect(SemanticVersion("v1.2.3-rc.1+9")?.description == "1.2.3-rc.1")
    }
}
