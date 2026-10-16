import Domain
import Observation
import Support

/// The Audio pane: input selection and a live level test. The test session is
/// always cancelled, so nothing it captures is kept.
@MainActor
@Observable
public final class AudioSettingsModel {
    public private(set) var devices: [AudioInputDevice] = []
    public private(set) var selection: AudioInputSelection
    public private(set) var isTesting = false
    /// Current meter value only; samples are never held here.
    public private(set) var level: Float = 0
    public private(set) var notice: String?

    private let capture: any AudioCapturing
    private let deviceLister: any AudioDeviceListing
    private let preferences: any AppPreferences
    private var testTask: Task<Void, Never>?

    public init(capture: any AudioCapturing, deviceLister: any AudioDeviceListing, preferences: any AppPreferences) {
        self.capture = capture
        self.deviceLister = deviceLister
        self.preferences = preferences
        self.selection = preferences.audioInput
        refreshDevices()
    }

    /// Whether the saved device is missing, so recording will use the default.
    public var isSelectedDeviceMissing: Bool {
        guard case .device(let id) = selection else { return false }
        return !devices.contains { $0.id == id }
    }

    public func refreshDevices() {
        devices = deviceLister.availableInputDevices()
        if !isTesting {
            notice =
                isSelectedDeviceMissing
                ? String(
                    localized: "The selected microphone isn’t connected. LemmeType will use the system default.",
                    bundle: .module)
                : nil
        }
    }

    public func select(_ newSelection: AudioInputSelection) {
        selection = newSelection
        preferences.audioInput = newSelection
        refreshDevices()
        if isTesting {
            Task { await restartTest() }
        }
    }

    public func startTest() async {
        guard !isTesting else { return }
        do {
            let events = try await capture.start(input: selection)
            isTesting = true
            notice = nil
            testTask = Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
                self?.isTesting = false
                self?.level = 0
            }
        } catch {
            notice = Self.message(for: error)
        }
    }

    public func stopTest() async {
        guard isTesting else { return }
        await capture.cancel()
        await testTask?.value
        testTask = nil
    }

    private func restartTest() async {
        await stopTest()
        await startTest()
    }

    private func handle(_ event: AudioCaptureEvent) {
        switch event {
        case .level(let value):
            level = value
        case .fellBackToSystemDefault:
            notice = String(
                localized: "The selected microphone isn’t available. Using the system default.", bundle: .module)
        case .failed(let error):
            notice = Self.message(for: error)
        case .audio:
            break
        }
    }

    static func message(for error: AudioCaptureError) -> String {
        error.userMessage
    }
}
