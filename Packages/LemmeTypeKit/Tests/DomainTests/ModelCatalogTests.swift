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

/// E5-S1: three Whisper sizes, each described well enough to choose.
struct ModelFitTests {
    private static let gigabyte: UInt64 = 1 << 30

    @Test func catalogDescribesEveryWhisperSize() {
        #expect(ModelCatalog.all.map(\.id) == [.whisperTinyEnglish, .whisperBaseEnglish, .whisperSmallEnglish])
        #expect(ModelCatalog.all.map(\.tier) == [.fastest, .balanced, .mostAccurate])
        for asset in ModelCatalog.all {
            #expect(asset.engine == .whisper)
            #expect(asset.languages == ["en"])
            #expect(asset.runtimeMemoryBytes > 0)
            #expect(asset.hardware.requiresAppleSilicon)
            #expect(asset.hardware.recommendedMemoryBytes >= asset.hardware.minimumMemoryBytes)
            #expect(asset.files.first?.url.host == "huggingface.co")
        }
        // Sizes and memory grow with accuracy.
        #expect(ModelCatalog.all.map(\.downloadBytes) == ModelCatalog.all.map(\.downloadBytes).sorted())
        #expect(ModelCatalog.all.map(\.runtimeMemoryBytes) == ModelCatalog.all.map(\.runtimeMemoryBytes).sorted())
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
}
