import SwiftUI

struct RelayProviderSettingsView<Sidebar: View, Detail: View>: View {
    var cardBackground: Color
    var strokeColor: Color
    var shellCornerRadius: CGFloat
    var sidebar: Sidebar
    var detail: Detail

    init(
        cardBackground: Color,
        strokeColor: Color,
        shellCornerRadius: CGFloat,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.cardBackground = cardBackground
        self.strokeColor = strokeColor
        self.shellCornerRadius = shellCornerRadius
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        SettingsProviderDashboardContainerView(
            cardBackground: cardBackground,
            strokeColor: strokeColor,
            shellCornerRadius: shellCornerRadius,
            sidebar: {
                sidebar
            },
            detail: {
                detail
            }
        )
    }
}
