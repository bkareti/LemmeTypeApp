import Carbon.HIToolbox
import Domain
import Testing

@testable import Shortcuts

/// Domain cannot import Carbon, so it mirrors the key codes it needs.
struct CarbonConstantsTests {
    @Test func domainKeyCodesMatchCarbon() {
        #expect(Int(KeyCode.ansiQ) == kVK_ANSI_Q)
        #expect(Int(KeyCode.ansiW) == kVK_ANSI_W)
        #expect(Int(KeyCode.ansiH) == kVK_ANSI_H)
        #expect(Int(KeyCode.ansiM) == kVK_ANSI_M)
        #expect(Int(KeyCode.ansi3) == kVK_ANSI_3)
        #expect(Int(KeyCode.ansi4) == kVK_ANSI_4)
        #expect(Int(KeyCode.ansi5) == kVK_ANSI_5)
        #expect(Int(KeyCode.grave) == kVK_ANSI_Grave)
        #expect(Int(KeyCode.tab) == kVK_Tab)
        #expect(Int(KeyCode.space) == kVK_Space)
        #expect(Int(KeyCode.escape) == kVK_Escape)
        #expect(
            Set(KeyCode.modifierKeys.map(Int.init)) == [
                kVK_RightCommand, kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option,
                kVK_Control, kVK_RightShift, kVK_RightOption, kVK_RightControl, kVK_Function,
            ])
    }

    @Test func modifiersMapToCarbonMasks() {
        #expect(CarbonHotKeyRegistrar.carbonModifiers(.option) == UInt32(optionKey))
        #expect(
            CarbonHotKeyRegistrar.carbonModifiers([.command, .shift, .control, .option])
                == UInt32(cmdKey | shiftKey | controlKey | optionKey))
        #expect(CarbonHotKeyRegistrar.carbonModifiers([]) == 0)
    }
}
