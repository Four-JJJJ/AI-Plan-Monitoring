import SwiftUI

struct SettingsScrollableCardView<Content: View>: View {
    var title: String
    var subtitle: String
    var cardBackground: Color
    var strokeColor: Color
    var shellCornerRadius: CGFloat
    var sectionCornerRadius: CGFloat
    var sectionFillColor: Color
    var content: Content

    init(
        title: String,
        subtitle: String,
        cardBackground: Color,
        strokeColor: Color,
        shellCornerRadius: CGFloat,
        sectionCornerRadius: CGFloat,
        sectionFillColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.cardBackground = cardBackground
        self.strokeColor = strokeColor
        self.shellCornerRadius = shellCornerRadius
        self.sectionCornerRadius = sectionCornerRadius
        self.sectionFillColor = sectionFillColor
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsVisualTokens.Pane.cardContentSpacing) {
                VStack(alignment: .leading, spacing: SettingsVisualTokens.Pane.cardContentSpacing) {
                    VStack(alignment: .leading, spacing: SettingsVisualTokens.Pane.titleSpacing) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    content
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(SettingsVisualTokens.Pane.cardPadding)
                .background(
                    SettingsSmoothedRoundedRectangle(cornerRadius: sectionCornerRadius)
                        .fill(Color.clear)
                )
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: sectionCornerRadius)
                        .stroke(strokeColor, lineWidth: SettingsVisualTokens.Stroke.hairline)
                )
            }
            .padding(SettingsVisualTokens.Pane.cardOuterPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius)
                .fill(cardBackground)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius)
                .stroke(strokeColor, lineWidth: SettingsVisualTokens.Stroke.hairline)
        )
        .clipShape(SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius))
    }
}

struct SettingsProviderDashboardContainerView<Sidebar: View, Detail: View>: View {
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
        HStack(alignment: .top, spacing: SettingsVisualTokens.Pane.dashboardSpacing) {
            sidebar
                .frame(width: SettingsVisualTokens.Pane.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(SettingsVisualTokens.Pane.shellPadding)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius)
                .fill(cardBackground)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius)
                .stroke(strokeColor, lineWidth: SettingsVisualTokens.Stroke.hairline)
        )
        .clipShape(SettingsSmoothedRoundedRectangle(cornerRadius: shellCornerRadius))
    }
}
