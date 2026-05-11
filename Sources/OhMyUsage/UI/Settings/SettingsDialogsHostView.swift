import SwiftUI

enum SettingsModalOverlayKind: Equatable {
    case resetData
    case codexProfileEditor
    case claudeProfileEditor
    case oauthImport
    case newAPISite

    static func resolve(
        showsResetDataDialog: Bool,
        showsCodexProfileEditorDialog: Bool,
        showsClaudeProfileEditorDialog: Bool,
        showsOAuthImportDialog: Bool,
        showsNewAPISiteDialog: Bool
    ) -> SettingsModalOverlayKind? {
        if showsResetDataDialog { return .resetData }
        if showsCodexProfileEditorDialog { return .codexProfileEditor }
        if showsClaudeProfileEditorDialog { return .claudeProfileEditor }
        if showsOAuthImportDialog { return .oauthImport }
        if showsNewAPISiteDialog { return .newAPISite }
        return nil
    }
}

struct SettingsDialogsHostView<Content: View, Overlay: View>: View {
    var showsModalOverlay: Bool
    var content: Content
    var overlay: Overlay

    init(
        showsModalOverlay: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.showsModalOverlay = showsModalOverlay
        self.content = content()
        self.overlay = overlay()
    }

    var body: some View {
        ZStack {
            content
                .animation(.easeInOut(duration: 0.16), value: showsModalOverlay)

            if showsModalOverlay {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                overlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
    }
}
