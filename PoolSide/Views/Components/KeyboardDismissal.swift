import SwiftUI

extension View {
    func dismissesKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}
