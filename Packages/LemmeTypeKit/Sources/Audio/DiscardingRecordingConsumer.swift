import Domain
import Foundation
import Support

/// Epic 1 placeholder for transcription: deletes the finished recording.
/// Epic 2 replaces it with a consumer that transcribes and inserts text.
public struct DiscardingRecordingConsumer: RecordingConsumer {
    public init() {}

    public func consume(_ recording: RecordedAudio, target: ActivationTarget?) async throws(AudioCaptureError) {
        do {
            try FileManager.default.removeItem(at: recording.fileURL)
        } catch {
            throw .storageFailure
        }
        Log.audio.info("Recording discarded (no transcription engine yet)")
    }
}
