import Domain
import Foundation

/// The words for the device LemmeType runs on, so text written for the Mac does
/// not say "Mac" on an iPhone or iPad (ADR 0027). On the Mac the text is unchanged.
enum DeviceWords {
    private static let deviceClass = HardwareProfile.current.deviceClass

    static var isHandheld: Bool { deviceClass.isHandheld }

    /// "this Mac", "this iPhone", or "this iPad", for use after a preposition.
    static var thisDevice: String {
        switch deviceClass {
        case .mac: String(localized: "this Mac", bundle: .module, comment: "The computer, after a preposition")
        case .iPhone: String(localized: "this iPhone", bundle: .module, comment: "The phone, after a preposition")
        case .iPad: String(localized: "this iPad", bundle: .module, comment: "The tablet, after a preposition")
        }
    }

    /// "your Mac", "your iPhone", or "your iPad".
    static var yourDevice: String {
        switch deviceClass {
        case .mac: String(localized: "your Mac", bundle: .module, comment: "The user's computer")
        case .iPhone: String(localized: "your iPhone", bundle: .module, comment: "The user's phone")
        case .iPad: String(localized: "your iPad", bundle: .module, comment: "The user's tablet")
        }
    }
}
