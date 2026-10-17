import Foundation

/// Every model LemmeType can download. Changing an entry is a code change
/// reviewed like any other; see docs/decisions/0011-model-downloads.md and
/// docs/decisions/0022-model-management.md.
public enum ModelCatalog {
    /// Hosts downloads may come from (redirects are followed by the system).
    public static let allowedHosts: Set<String> = ["huggingface.co"]

    /// whisper.cpp `tiny.en` (MIT), English only: fastest, least accurate.
    public static let whisperTinyEnglish = whisper(
        WhisperSpec(
            id: .whisperTinyEnglish, name: "Whisper Tiny (English)", file: "ggml-tiny.en.bin",
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f", bytes: 77_704_715,
            tier: .fastest, memory: 273_000_000, recommendedGigabytes: 8))

    /// whisper.cpp `base.en` (MIT), English only. The size and SHA-256 pin the
    /// exact file; it is verified before it is ever used.
    public static let whisperBaseEnglish = whisper(
        WhisperSpec(
            id: .whisperBaseEnglish, name: "Whisper Base (English)", file: "ggml-base.en.bin",
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002", bytes: 147_964_211,
            tier: .balanced, memory: 388_000_000, recommendedGigabytes: 8))

    /// whisper.cpp `small.en` (MIT), English only: most accurate, about three
    /// times slower than Base.
    public static let whisperSmallEnglish = whisper(
        WhisperSpec(
            id: .whisperSmallEnglish, name: "Whisper Small (English)", file: "ggml-small.en.bin",
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d", bytes: 487_614_201,
            tier: .mostAccurate, memory: 852_000_000, recommendedGigabytes: 16))

    /// Every Whisper model, fastest first.
    public static let whisperModels: [ModelAsset] = [whisperTinyEnglish, whisperBaseEnglish, whisperSmallEnglish]

    public static let all: [ModelAsset] = whisperModels

    public static func asset(_ id: ModelAssetID) -> ModelAsset? {
        all.first { $0.id == id }
    }

    /// Whether `url` may be downloaded from: HTTPS on an allowlisted host.
    public static func isTrustedSource(_ url: URL) -> Bool {
        url.scheme == "https" && url.host.map(allowedHosts.contains) == true
    }

    /// The ggerganov/whisper.cpp repository on Hugging Face; one recipe for every size.
    private struct WhisperSpec {
        let id: ModelAssetID
        let name: String
        let file: String
        let sha256: String
        let bytes: Int64
        let tier: ModelTier
        let memory: UInt64
        let recommendedGigabytes: UInt64
    }

    private static func whisper(_ spec: WhisperSpec) -> ModelAsset {
        let (id, name, file, sha256, bytes) = (spec.id, spec.name, spec.file, spec.sha256, spec.bytes)
        let (tier, memory, recommendedGigabytes) = (spec.tier, spec.memory, spec.recommendedGigabytes)
        return ModelAsset(
            id: id,
            displayName: name,
            version: file.replacingOccurrences(of: ".bin", with: ""),
            engine: .whisper,
            files: [
                ModelFile(
                    name: file,
                    url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")
                        ?? URL(fileURLWithPath: "/"),
                    sha256: sha256,
                    bytes: bytes
                )
            ],
            languages: ["en"],
            license: "MIT",
            licenseURL: URL(string: "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE")
                ?? URL(fileURLWithPath: "/"),
            hardware: HardwareRequirement(
                requiresAppleSilicon: true, minimumMemoryBytes: 8 * 1_073_741_824,
                recommendedMemoryBytes: recommendedGigabytes * 1_073_741_824),
            tier: tier,
            runtimeMemoryBytes: memory
        )
    }
}
