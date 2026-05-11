import SwiftUI

struct SettingsSidebarView<Header: View, BodyContent: View, Footer: View>: View {
    var cornerRadius: CGFloat
    var fillColor: Color
    var strokeColor: Color
    var header: Header
    var bodyContent: BodyContent
    var footer: Footer

    init(
        cornerRadius: CGFloat,
        fillColor: Color,
        strokeColor: Color,
        @ViewBuilder header: () -> Header,
        @ViewBuilder bodyContent: () -> BodyContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.header = header()
        self.bodyContent = bodyContent()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            bodyContent
            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(fillColor)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
}
