import Domain
import Foundation
import Testing

struct ModelCatalogTests {
    @Test func everyEntryIsPinnedAndTrusted() {
        #expect(!ModelCatalog.all.isEmpty)
        for asset in ModelCatalog.all {
            #expect(DiagnosticValue.isSafeIdentifier(asset.id.rawValue))
            #expect(!asset.files.isEmpty)
            #expect(!asset.license.isEmpty)
            for file in asset.files {
                #expect(ModelCatalog.isTrustedSource(file.url), "\(file.url)")
                #expect(file.bytes > 0)
                #expect(file.sha256.count == 64)
                #expect(file.sha256.allSatisfy { "0123456789abcdef".contains($0) })
            }
        }
    }

    @Test func whisperBaseEnglishMatchesItsEngine() {
        let asset = ModelCatalog.whisperBaseEnglish
        #expect(asset.engine == .whisper)
        #expect(asset.languages == ["en"])
        #expect(asset.downloadBytes > 100_000_000)
        #expect(asset.requiredFreeBytes > asset.downloadBytes)
        #expect(ModelCatalog.asset(.whisperBaseEnglish) == asset)
    }

    @Test func onlyHTTPSOnAllowlistedHostsIsTrusted() throws {
        #expect(ModelCatalog.isTrustedSource(try #require(URL(string: "https://huggingface.co/x"))))
        #expect(!ModelCatalog.isTrustedSource(try #require(URL(string: "http://huggingface.co/x"))))
        #expect(!ModelCatalog.isTrustedSource(try #require(URL(string: "https://evil.example/x"))))
        #expect(!ModelCatalog.isTrustedSource(URL(fileURLWithPath: "/tmp/model.bin")))
    }

    @Test func consentMustMatchTheCatalogSize() {
        let asset = ModelCatalog.whisperBaseEnglish
        #expect(ModelDownloadConsent(asset: asset).isValid(for: asset))
        #expect(!ModelDownloadConsent(asset: asset.id, acknowledgedBytes: 1).isValid(for: asset))
    }

    @Test func hardwareRequirementExplainsIncompatibility() {
        let requirement = HardwareRequirement(requiresAppleSilicon: true, minimumMemoryBytes: 8 << 30)
        #expect(
            requirement.unsupportedReason(for: .init(isAppleSilicon: false, physicalMemoryBytes: 16 << 30)) == .hardware
        )
        #expect(
            requirement.unsupportedReason(for: .init(isAppleSilicon: true, physicalMemoryBytes: 4 << 30))
                == .insufficientMemory)
        #expect(requirement.unsupportedReason(for: .init(isAppleSilicon: true, physicalMemoryBytes: 16 << 30)) == nil)
    }

    @Test func progressFractionIsBounded() {
        #expect(ModelInstallState.downloading(receivedBytes: 50, totalBytes: 100).fractionCompleted == 0.5)
        #expect(ModelInstallState.paused(receivedBytes: 200, totalBytes: 100).fractionCompleted == 1)
        #expect(ModelInstallState.installed.fractionCompleted == nil)
        #expect(ModelInstallState.verifying.isBusy)
    }
}

/// E5-S1: three Whisper sizes (each English-only and, since E9-S2,
/// multilingual), each described well enough to choose.
struct ModelFitTests {
    private static let gigabyte: UInt64 = 1 << 30

    @Test func catalogDescribesEveryWhisperSize() {
        let english = ModelCatalog.all.filter { $0.languages == ["en"] }
        let multilingual = ModelCatalog.all.filter { $0.languages != ["en"] }
        #expect(english.map(\.id) == [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish])
        #expect(multilingual.map(\.id) == [.whisperTiny, .whisperBase, .whisperSmall])
        #expect(english.map(\.tier) == [.fastest, .balanced, .mostAccurate])
        #expect(multilingual.map(\.tier) == [.fastest, .balanced, .mostAccurate])
        for asset in ModelCatalog.all {
            #expect(asset.engine == .whisper)
            #expect(asset.runtimeMemoryBytes > 0)
            #expect(asset.hardware.requiresAppleSilicon)
            #expect(asset.hardware.recommendedMemoryBytes >= asset.hardware.minimumMemoryBytes)
            #expect(asset.files.first?.url.host == "huggingface.co")
        }
        // Sizes and memory grow with accuracy, in each group.
        for group in [english, multilingual] {
            #expect(group.map(\.downloadBytes) == group.map(\.downloadBytes).sorted())
            #expect(group.map(\.runtimeMemoryBytes) == group.map(\.runtimeMemoryBytes).sorted())
        }
        // The existing Base install is untouched: same id, version folder, and file.
        #expect(ModelCatalog.whisperBaseEnglish.id.rawValue == "whisper-base-en")
        #expect(ModelCatalog.whisperBaseEnglish.version == "ggml-base.en")
        #expect(ModelCatalog.whisperBaseEnglish.files.first?.bytes == 147_964_211)
    }

    @Test func fitDependsOnChipAndMemory() {
        let small = ModelCatalog.whisperSmallEnglish.hardware
        #expect(
            small.fit(for: .init(isAppleSilicon: false, physicalMemoryBytes: 32 * Self.gigabyte))
                == .unsupported(.hardware))
        #expect(
            small.fit(for: .init(isAppleSilicon: true, physicalMemoryBytes: 4 * Self.gigabyte))
                == .unsupported(.insufficientMemory))
        #expect(small.fit(for: .init(isAppleSilicon: true, physicalMemoryBytes: 8 * Self.gigabyte)) == .supported)
        #expect(small.fit(for: .init(isAppleSilicon: true, physicalMemoryBytes: 16 * Self.gigabyte)) == .recommended)
        let base = ModelCatalog.whisperBaseEnglish.hardware
        #expect(base.fit(for: .init(isAppleSilicon: true, physicalMemoryBytes: 8 * Self.gigabyte)) == .recommended)
        #expect(ModelFit.unsupported(.hardware).identifier == "unsupported.hardware")
        #expect(!ModelFit.unsupported(.hardware).canRun && ModelFit.supported.canRun)
    }

    // MARK: E9-S2 — multilingual models

    @Test func multilingualModelsAreListedWithTheirTasksAndLanguages() {
        for id in [ModelAssetID.whisperTiny, .whisperBase, .whisperSmall] {
            let asset = ModelCatalog.asset(id)
            #expect(asset != nil, "\(id)")
            #expect(asset?.engine == .whisper)
            #expect(asset?.languages == ["en", "hi", "te"])
            #expect(asset?.tasks == [.transcribe, .translateToEnglish])
            #expect(asset?.detectsLanguage == true)
            #expect(
                asset?.files.first?.name == "ggml-\(id.rawValue.replacingOccurrences(of: "whisper-", with: "")).bin")
        }
    }

    @Test func englishOnlyModelsKeepTheirIdentityAndCannotTranslateOrDetect() {
        for id in [ModelAssetID.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish] {
            let asset = ModelCatalog.asset(id)
            #expect(asset?.languages == ["en"])
            #expect(asset?.tasks == [.transcribe])
            #expect(asset?.detectsLanguage == false)
            #expect(asset?.serves(language: "hi", task: .transcribe) == false)
            #expect(asset?.serves(language: "en-GB", task: .transcribe) == true)
            #expect(asset?.serves(language: SpokenLanguages.automatic, task: .transcribe) == false)
        }
        #expect(ModelCatalog.whisperBaseEnglish.files.first?.name == "ggml-base.en.bin")
        #expect(ModelCatalog.whisperBaseEnglish.files.first?.sha256.hasPrefix("a03779c8") == true)
    }

    @Test func everyEnglishModelHasAMultilingualCounterpartOfTheSameTier() throws {
        for english in ModelCatalog.whisperModels where english.languages == ["en"] {
            let counterpartID = try #require(ModelCatalog.multilingualCounterpart(of: english.id))
            let counterpart = try #require(ModelCatalog.asset(counterpartID))
            #expect(counterpart.tier == english.tier)
            #expect(counterpart.runtimeMemoryBytes == english.runtimeMemoryBytes)
            #expect(counterpart.hardware == english.hardware)
        }
        #expect(ModelCatalog.multilingualCounterpart(of: .whisperSmall) == nil)
    }

    @Test func catalogEntriesHaveUniqueIdentifiersAndFiles() {
        let ids = ModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let names = ModelCatalog.all.flatMap(\.files).map(\.name)
        #expect(Set(names).count == names.count)
    }
}
