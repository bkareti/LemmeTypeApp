import Domain
import Foundation

/// Turns speech-format samples into a 16-bit mono WAV in memory, so no extra
/// copy of the user's voice is written to disk.
enum WAVEncoder {
    static func encode(_ samples: [Float], sampleRate: Double = AudioCaptureFormat.speech.sampleRate) -> Data {
        let bytesPerSample = 2
        let payload = samples.count * bytesPerSample
        var data = Data(capacity: 44 + payload)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + payload), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)  // integer PCM
        append(UInt16(1), to: &data)  // mono
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate) * UInt32(bytesPerSample), to: &data)
        append(UInt16(bytesPerSample), to: &data)
        append(UInt16(bytesPerSample * 8), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(payload), to: &data)
        for sample in samples {
            let clamped = min(1, max(-1, sample.isFinite ? sample : 0))
            append(Int16((clamped * Float(Int16.max)).rounded()), to: &data)
        }
        return data
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
