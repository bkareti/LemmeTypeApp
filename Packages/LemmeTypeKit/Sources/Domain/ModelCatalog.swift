import Foundation

/// Every model LemmeType can download. Changing an entry is a code change
/// reviewed like any other; see docs/decisions/0011-model-downloads.md.
public enum ModelCatalog {
    /// Hosts downloads may come from (redirects are followed by the system).
    public static let allowedHosts: Set<String> = ["huggingface.co"]

    /// whisper.cpp `base.en` (MIT), English only. The size and SHA-256 pin the
    /// exact file; it is verified before it is ever used.
    public static let whisperBaseEnglish = ModelAsset(
        id: .whisperBaseEnglish,
        displayName: "Whisper Base (English)",
        version: "ggml-base.en",
        engine: .whisper,
        files: [
            ModelFile(
                name: "ggml-base.en.bin",
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")
                    ?? URL(fileURLWithPath: "/"),
                sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
                bytes: 147_964_211
            )
        ],
        languages: ["en"],
        license: "MIT",
        licenseURL: URL(string: "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE")
            ?? URL(fileURLWithPath: "/"),
        hardware: HardwareRequirement(requiresAppleSilicon: true, minimumMemoryBytes: 8 * 1_073_741_824)
    )

    public static let all: [ModelAsset] = [whisperBaseEnglish]

    public static func asset(_ id: ModelAssetID) -> ModelAsset? {
        all.first { $0.id == id }
    }

    /// Whether `url` may be downloaded from: HTTPS on an allowlisted host.
    public static func isTrustedSource(_ url: URL) -> Bool {
        url.scheme == "https" && url.host.map(allowedHosts.contains) == true
    }
}
