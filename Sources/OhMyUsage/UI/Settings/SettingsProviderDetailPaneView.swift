import SwiftUI

struct SettingsProviderDetailPaneView<Content: View, EmptyState: View>: View {
    var hasSelection: Bool
    var content: Content
    var emptyState: EmptyState

    init(
        hasSelection: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder emptyState: () -> EmptyState
    ) {
        self.hasSelection = hasSelection
        self.content = content()
        self.emptyState = emptyState()
    }

    var body: some View {
        if hasSelection {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.never)
        } else {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
