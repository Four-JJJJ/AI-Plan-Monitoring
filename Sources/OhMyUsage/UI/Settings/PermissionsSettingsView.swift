import SwiftUI

struct PermissionsSettingsView<Content: View>: View {
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
        SettingsScrollableCardView(
            title: title,
            subtitle: subtitle,
            cardBackground: cardBackground,
            strokeColor: strokeColor,
            shellCornerRadius: shellCornerRadius,
            sectionCornerRadius: sectionCornerRadius,
            sectionFillColor: sectionFillColor
        ) {
            content
        }
    }
}
