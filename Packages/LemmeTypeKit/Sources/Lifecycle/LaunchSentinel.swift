import Domain
import Foundation
import Support

/// Tells the next launch whether the previous run ended normally (E7-S4).
///
/// A small marker file is written when the app starts and removed on a normal
/// quit. If it is still there at the next launch, the app was force-quit, crashed,
/// or lost power. The marker holds only the app version and a start time, never
/// text, audio, or a stack trace; crash reports stay in macOS's own log folder.
public struct LaunchSentinel: Sendable {
    public enum PreviousRun: Equatable, Sendable {
        /// First launch, or the previous run quit normally.
        case endedNormally
        /// The marker was left behind. `previousVersion` is nil if it could not be read.
        case endedUnexpectedly(previousVersion: String?)
    }

    private struct Marker: Codable {
        let version: String
        let startedAt: Date
    }

    public let directory: URL
    private let version: String
    private let now: @Sendable () -> Date

    public init(directory: URL, version: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.version = version
        self.now = now
    }

    /// Application Support/LemmeType/State.
    public static func makeDefault(version: String) -> LaunchSentinel {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LaunchSentinel(
            directory: support.appendingPathComponent("LemmeType/State", isDirectory: true), version: version)
    }

    public var markerURL: URL { directory.appendingPathComponent("running.marker") }

    /// Reads how the last run ended, then marks this run as started. Call once,
    /// in the instance that keeps running (not in a second launch that hands off).
    public func begin() -> PreviousRun {
        let previous = readPrevious()
        write()
        return previous
    }

    /// Marks a normal quit. Safe to call when no marker exists.
    public func end() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    private func readPrevious() -> PreviousRun {
        guard let data = FileManager.default.contents(atPath: markerURL.path) else { return .endedNormally }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try? decoder.decode(Marker.self, from: data)
        return .endedUnexpectedly(previousVersion: marker?.version)
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Marker(version: version, startedAt: now())) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: markerURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        } catch {
            Log.lifecycle.error("Could not write the launch marker")
        }
    }
}
