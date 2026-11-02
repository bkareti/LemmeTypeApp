import SwiftUI

extension View {
    /// A short list of exclusive choices: radio buttons on the Mac, an inline
    /// list on iPhone and iPad, where the radio-group style does not exist.
    func exclusiveChoiceStyle() -> some View {
        #if os(macOS)
            pickerStyle(.radioGroup)
        #else
            pickerStyle(.inline)
        #endif
    }
}
