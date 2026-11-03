#if DEBUG
    import CryptoKit
    import Foundation

    /// A versioned list of evaluation cases (`docs/testing/corpus/*.json`): where
    /// each recording comes from and under what licence, its SHA-256, and its
    /// human references. Audio is never in the repository; `root` points at a
    /// local copy made by `scripts/corpus.py fetch`.
    ///
    /// Only human references are ground truth. A case marked ``Review/unverified``
    /// (for example, one whose reference came from a model) is skipped unless the
    /// caller asks for it, and is never scored against a release gate.
    public struct CorpusManifest: Codable, Equatable, Sendable {
        public static let schemaVersion = 1

        public struct Source: Codable, Equatable, Sendable {
            public let id: String
            public let title: String
            /// SPDX identifier, such as `CC-BY-4.0`.
            public let license: String
            public let licenseURL: String
            /// Where the files come from, pinned to a revision.
            public let url: String
            public let revision: String
            public let attribution: String

            public init(
                id: String, title: String, license: String, licenseURL: String, url: String, revision: String,
                attribution: String
            ) {
                self.id = id
                self.title = title
                self.license = license
                self.licenseURL = licenseURL
                self.url = url
                self.revision = revision
                self.attribution = attribution
            }
        }

        public enum Review: String, Codable, Equatable, Sendable {
            /// The dataset's own human transcript or translation.
            case datasetHuman = "dataset-human"
            /// Checked or corrected by a maintainer.
            case maintainerVerified = "maintainer-verified"
            /// Empty because the audio was generated without speech.
            case byConstruction = "by-construction"
            /// Not checked by a person. Never ground truth.
            case unverified

            public var isGroundTruth: Bool { self != .unverified }
        }

        public struct Audio: Codable, Equatable, Sendable {
            /// Relative to the corpus root.
            public let path: String
            public let sha256: String
            public let seconds: Double

            public init(path: String, sha256: String, seconds: Double) {
                self.path = path
                self.sha256 = sha256
                self.seconds = seconds
            }
        }

        /// A recording with its human references.
        public struct Case: Codable, Equatable, Sendable {
            public let id: String
            public let source: String
            /// BCP 47 language that is spoken.
            public let language: String
            public let audio: Audio
            public let reference: String
            /// Human English reference, for translation.
            public let englishReference: String?
            public let category: String
            public let tags: [String]
            public let review: Review

            public init(
                id: String, source: String, language: String, audio: Audio, reference: String,
                englishReference: String?, category: String, tags: [String], review: Review
            ) {
                self.id = id
                self.source = source
                self.language = language
                self.audio = audio
                self.reference = reference
                self.englishReference = englishReference
                self.category = category
                self.tags = tags
                self.review = review
            }
        }

        /// What a ``GeneratedCase`` sounds like.
        public enum GeneratedKind: String, Codable, Equatable, Sendable {
            case silence
            case noise
            case tone
        }

        /// A case synthesized at run time: audio without speech, so the reference is empty.
        public struct GeneratedCase: Codable, Equatable, Sendable {
            public let id: String
            public let kind: GeneratedKind
            public let seconds: Double
            /// Peak level for noise and tones.
            public let amplitude: Float?
            public let seed: UInt64?
            /// Languages to run it in: an engine must stay silent in each.
            public let languages: [String]
            public let category: String

            public init(
                id: String, kind: GeneratedKind, seconds: Double, amplitude: Float? = nil, seed: UInt64? = nil,
                languages: [String], category: String
            ) {
                self.id = id
                self.kind = kind
                self.seconds = seconds
                self.amplitude = amplitude
                self.seed = seed
                self.languages = languages
                self.category = category
            }

            var clip: AudioClip {
                switch kind {
                case .silence: .silence(seconds: seconds)
                case .noise: .whiteNoise(seconds: seconds, amplitude: amplitude ?? 0.05, seed: seed ?? 1)
                case .tone: .tone(seconds: seconds, amplitude: amplitude ?? 0.3)
                }
            }
        }

        public let schema: Int
        public let name: String
        public let sources: [Source]
        public let cases: [Case]
        public let generated: [GeneratedCase]
        public let variants: [CorpusVariant]

        public init(
            schema: Int = CorpusManifest.schemaVersion, name: String, sources: [Source] = [], cases: [Case] = [],
            generated: [GeneratedCase] = [], variants: [CorpusVariant] = []
        ) {
            self.schema = schema
            self.name = name
            self.sources = sources
            self.cases = cases
            self.generated = generated
            self.variants = variants
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema = try container.decode(Int.self, forKey: .schema)
            name = try container.decode(String.self, forKey: .name)
            sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
            cases = try container.decodeIfPresent([Case].self, forKey: .cases) ?? []
            generated = try container.decodeIfPresent([GeneratedCase].self, forKey: .generated) ?? []
            variants = try container.decodeIfPresent([CorpusVariant].self, forKey: .variants) ?? []
        }

        public static func load(from url: URL) throws -> CorpusManifest {
            try JSONDecoder().decode(CorpusManifest.self, from: Data(contentsOf: url))
        }

        // MARK: Validation

        /// Everything wrong with the manifest itself, without touching audio. Empty when it is usable.
        public func problems() -> [String] {
            var found: [String] = []
            if schema != Self.schemaVersion { found.append("schema \(schema) is not \(Self.schemaVersion)") }
            for source in sources where source.license.isEmpty || source.attribution.isEmpty {
                found.append("source \(source.id) has no licence or attribution")
            }
            let sourceIDs = Set(sources.map(\.id))
            var seen: Set<String> = []
            let ids = cases.map(\.id) + generated.map(\.id) + variants.map(\.id)
            for id in ids where !seen.insert(id).inserted { found.append("duplicate id \(id)") }
            for item in cases {
                if !sourceIDs.contains(item.source) { found.append("\(item.id): unknown source \(item.source)") }
                if !Self.isSHA256(item.audio.sha256) { found.append("\(item.id): sha256 is not 64 hex digits") }
                if item.audio.path.hasPrefix("/") || item.audio.path.split(separator: "/").contains("..") {
                    found.append("\(item.id): audio path must stay inside the corpus root")
                }
                if item.reference.isEmpty && item.review != .byConstruction {
                    found.append("\(item.id): a recording needs a human reference")
                }
            }
            for item in generated where item.languages.isEmpty { found.append("\(item.id): no languages") }
            for variant in variants { found += variant.problems().map { "\(variant.id): \($0)" } }
            return found
        }

        static func isSHA256(_ value: String) -> Bool {
            value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }

        // MARK: Items

        public enum CorpusError: Error, Equatable {
            case invalidManifest([String])
            case missingAudio(caseID: String)
            case checksumMismatch(caseID: String)
        }

        /// Every run this manifest asks for: each ground-truth recording, each
        /// generated case in each of its languages, and each variant on the
        /// recordings it samples. Recordings are checked against their SHA-256
        /// first, so a changed or truncated file is never scored.
        public func items(root: URL, includeUnverified: Bool = false) throws -> [CorpusItem] {
            let problems = problems()
            guard problems.isEmpty else { throw CorpusError.invalidManifest(problems) }
            let recordings = cases.filter { includeUnverified || $0.review.isGroundTruth }
            var items: [CorpusItem] = []
            for item in recordings {
                let url = root.appendingPathComponent(item.audio.path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw CorpusError.missingAudio(caseID: item.id)
                }
                guard try Self.sha256(of: url) == item.audio.sha256 else {
                    throw CorpusError.checksumMismatch(caseID: item.id)
                }
                items.append(CorpusItem(recording: item, url: url))
            }
            for item in generated {
                items += item.languages.map { CorpusItem(generated: item, language: $0) }
            }
            for variant in variants {
                for (index, item) in recordings.enumerated() where index % variant.samplingStride == 0 {
                    items.append(
                        CorpusItem(recording: item, url: root.appendingPathComponent(item.audio.path), variant: variant)
                    )
                }
            }
            return items
        }

        /// Streaming, so a long recording is never read into memory just to check it.
        public static func sha256(of url: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
