import Support
import Testing

struct BuildInfoTests {
    @Test func readsVersionAndBuildFromInfoDictionary() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
        ])

        #expect(info == BuildInfo(version: "1.2.3", build: "42"))
        #expect(info.displayString == "1.2.3 (42)")
    }

    @Test func fallsBackToUnknownForMissingOrMalformedValues() {
        let info = BuildInfo(infoDictionary: ["CFBundleVersion": 42])

        #expect(info == BuildInfo(version: "unknown", build: "unknown"))
        #expect(BuildInfo(infoDictionary: nil) == BuildInfo(version: "unknown", build: "unknown"))
    }
}
