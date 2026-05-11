import SwiftUI

struct SettingsRootView<Content: View, Overlay: View>: View {
    var colorScheme: ColorScheme
    var showsModalOverlay: Bool
    var content: Content
    var overlay: Overlay

    init(
        colorScheme: ColorScheme,
        showsModalOverlay: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.colorScheme = colorScheme
        self.showsModalOverlay = showsModalOverlay
        self.content = content()
        self.overlay = overlay()
    }

    var body: some View {
        SettingsDialogsHostView(showsModalOverlay: showsModalOverlay) {
            content
        } overlay: {
            overlay
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, colorScheme)
    }
}
