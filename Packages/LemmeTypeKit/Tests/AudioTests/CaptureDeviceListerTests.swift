import Domain
import Testing

@testable import Audio

struct CaptureDeviceListerTests {
    @Test func systemDefaultIsMarkedAndListedFirst() {
        let devices = CaptureDeviceLister.makeDevices(
            [(id: "b", name: "USB Mic"), (id: "a", name: "MacBook Pro Microphone"), (id: "c", name: "AirPods")],
            defaultID: "b"
        )

        #expect(devices.map(\.id) == ["b", "c", "a"])
        #expect(devices.filter(\.isSystemDefault).map(\.id) == ["b"])
    }

    @Test func noDefaultWhenSystemReportsNone() {
        let devices = CaptureDeviceLister.makeDevices([(id: "a", name: "Mic")], defaultID: nil)

        #expect(devices.allSatisfy { !$0.isSystemDefault })
    }
}
