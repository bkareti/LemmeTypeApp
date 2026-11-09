import Foundation

/// Stable name of a cloud speech vendor, stored with the user's consent so a
/// different vendor has to ask again (docs/decisions/0031-cloud-speech-provider.md).
public struct CloudSpeechProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// One recording, or part of one, ready to send: 16-bit mono WAV. Contains the
/// user's voice, so it is held in memory for one request only and never logged.
public struct CloudAudioClip: Sendable {
    public let wav: Data
    public let seconds: Double

    public init(wav: Data, seconds: Double) {
        self.wav = wav
        self.seconds = seconds
    }
}

/// Everything that is specific to one cloud speech vendor, and nothing else.
///
/// Implementations are pure: they turn a clip into a request value and a
/// response value into text, so a new vendor is one small file that can be
/// tested without a network. Everything else (audio conversion, retries,
/// cancellation) belongs to the engine. `CloudSpeechProviderContract` in
/// TestSupport is the check every implementation must pass.
public protocol CloudSpeechProvider: Sendable {
    var id: CloudSpeechProviderID { get }
    /// The vendor's name, shown in the consent.
    var displayName: String { get }
    /// The only host that may receive audio: shown in the consent, enforced by the transport.
    var host: String { get }
    /// The longest clip one request accepts.
    var maximumClipSeconds: Double { get }
    /// BCP 47 identifiers such as `"te"`.
    var supportedLanguages: [String] { get }
    var tasks: Set<RecognitionTask> { get }

    /// The request for one clip. Sends audio only: never hints, context, or text.
    func request(
        for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential
    ) throws(RecognitionError) -> CloudHTTPRequest

    /// The text in a response, or the typed error it stands for. An empty
    /// string means the vendor heard no speech.
    func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String
}
