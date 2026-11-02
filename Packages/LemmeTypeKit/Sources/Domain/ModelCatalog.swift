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

    /// whisper.cpp `tiny` (MIT), multilingual (E9-S2). Runs English too, and
    /// can translate to English. Pinned from the same repository as the others.
    public static let whisperTiny = whisper(
        WhisperSpec(
            id: .whisperTiny, name: "Whisper Tiny (Multilingual)", file: "ggml-tiny.bin",
            sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21", bytes: 77_691_713,
            tier: .fastest, memory: 273_000_000, recommendedGigabytes: 8, multilingual: true))

    /// whisper.cpp `base` (MIT), multilingual.
    public static let whisperBase = whisper(
        WhisperSpec(
            id: .whisperBase, name: "Whisper Base (Multilingual)", file: "ggml-base.bin",
            sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe", bytes: 147_951_465,
            tier: .balanced, memory: 388_000_000, recommendedGigabytes: 8, multilingual: true))

    /// whisper.cpp `small` (MIT), multilingual: the smallest model proposed for
    /// evaluating Hindi and Telugu.
    public static let whisperSmall = whisper(
        WhisperSpec(
            id: .whisperSmall, name: "Whisper Small (Multilingual)", file: "ggml-small.bin",
            sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b", bytes: 487_601_967,
            tier: .mostAccurate, memory: 852_000_000, recommendedGigabytes: 16, multilingual: true))

    /// Every Whisper model: English-only first, each fastest first.
    public static let whisperModels: [ModelAsset] = [
        whisperTinyEnglish, whisperBaseEnglish, whisperSmallEnglish, whisperTiny, whisperBase, whisperSmall,
    ]

    /// The multilingual model of the same size as an English-only one (E9-S2).
    public static func multilingualCounterpart(of id: ModelAssetID) -> ModelAssetID? {
        switch id {
        case .whisperTinyEnglish: .whisperTiny
        case .whisperBaseEnglish: .whisperBase
        case .whisperSmallEnglish: .whisperSmall
        default: nil
        }
    }

    /// The languages a multilingual model is listed for: the evaluation set,
    /// not every language Whisper can attempt.
    public static var multilingualLanguages: [String] { SpokenLanguages.all.map(\.code) }

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
        var multilingual = false
    }

    /// iPhone and iPad (E8-S5, Proposed until measured on devices): Tiny and Base on
    /// 6 GB and up, Small only on iPads with 8 GB and up.
    private static func handheldRequirements(for tier: ModelTier) -> [DeviceClass: HandheldRequirement] {
        switch tier {
        case .fastest, .balanced:
            let need = HandheldRequirement(minimumGigabytes: 6, recommendedGigabytes: 8)
            return [.iPhone: need, .iPad: need]
        case .mostAccurate:
            return [.iPad: HandheldRequirement(minimumGigabytes: 8, recommendedGigabytes: 16)]
        }
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
            languages: spec.multilingual ? multilingualLanguages : ["en"],
            license: "MIT",
            licenseURL: URL(string: "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE")
                ?? URL(fileURLWithPath: "/"),
            hardware: HardwareRequirement(
                requiresAppleSilicon: true, minimumMemoryBytes: 8 * 1_073_741_824,
                recommendedMemoryBytes: recommendedGigabytes * 1_073_741_824,
                handheld: handheldRequirements(for: tier)),
            tasks: spec.multilingual ? [.transcribe, .translateToEnglish] : [.transcribe],
            tier: tier,
            runtimeMemoryBytes: memory
        )
    }
}
