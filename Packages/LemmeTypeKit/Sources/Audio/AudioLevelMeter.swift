import Foundation

/// Converts samples to a 0…1 meter value (RMS on a −60 dBFS…0 dBFS scale).
/// Only the resulting number leaves this function; samples are not retained.
enum AudioLevelMeter {
    static let floorDecibels: Float = -60

    static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        let rms = meanSquare.squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
