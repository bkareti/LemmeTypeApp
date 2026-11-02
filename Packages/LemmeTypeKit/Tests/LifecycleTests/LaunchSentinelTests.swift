import Foundation
import Testing

@testable import Lifecycle

/// E7-S4: the marker tells the next launch how the last run ended.
struct LaunchSentinelTests {
    static func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LemmeTypeTests-Sentinel-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("State", isDirectory: true)
    }

    static func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    @Test func theFirstLaunchHasNothingToReport() {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let sentinel = LaunchSentinel(directory: directory, version: "0.1.0")
        #expect(sentinel.begin() == .endedNormally)
        #expect(FileManager.default.fileExists(atPath: sentinel.markerURL.path), "this run is marked as started")
    }

    @Test func aNormalQuitLeavesNoMarker() {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let sentinel = LaunchSentinel(directory: directory, version: "0.1.0")
        _ = sentinel.begin()
        sentinel.end()
        #expect(!FileManager.default.fileExists(atPath: sentinel.markerURL.path))
        #expect(LaunchSentinel(directory: directory, version: "0.1.0").begin() == .endedNormally)
    }

    @Test func aLeftoverMarkerMeansTheRunEndedUnexpectedly() {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        _ = LaunchSentinel(directory: directory, version: "0.1.0").begin()  // never ended: a crash or kill

        let next = LaunchSentinel(directory: directory, version: "0.2.0")

        #expect(next.begin() == .endedUnexpectedly(previousVersion: "0.1.0"))
        // After reporting once, this run is the one being tracked.
        next.end()
        #expect(LaunchSentinel(directory: directory, version: "0.2.0").begin() == .endedNormally)
    }

    @Test func anUnreadableMarkerCountsAsUnexpectedAndDoesNotCrash() throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let sentinel = LaunchSentinel(directory: directory, version: "0.1.0")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: sentinel.markerURL)

        #expect(sentinel.begin() == .endedUnexpectedly(previousVersion: nil))
        #expect(sentinel.begin() == .endedUnexpectedly(previousVersion: "0.1.0"), "now a valid marker")
    }

    @Test func endingWithNoMarkerIsHarmless() {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        LaunchSentinel(directory: directory, version: "0.1.0").end()
    }

    @Test func theMarkerIsPrivateAndHoldsOnlyVersionAndTime() throws {
        let directory = Self.makeDirectory()
        defer { Self.cleanUp(directory) }
        let sentinel = LaunchSentinel(directory: directory, version: "0.1.0")
        _ = sentinel.begin()

        let attributes = try FileManager.default.attributesOfItem(atPath: sentinel.markerURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: sentinel.markerURL)) as? [String: Any])
        #expect(Set(object.keys) == ["version", "startedAt"])
    }
}
