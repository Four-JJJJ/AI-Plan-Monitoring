import SwiftUI

struct SettingsShellView<Sidebar: View, Header: View, Content: View>: View {
    var background: Color
    var detailFillColor: Color
    var detailStrokeColor: Color
    var sidebarWidth: CGFloat
    var spacing: CGFloat
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var topPadding: CGFloat
    var detailCornerRadius: CGFloat
    var sidebar: Sidebar
    var header: Header
    var content: Content

    init(
        background: Color,
        detailFillColor: Color,
        detailStrokeColor: Color,
        sidebarWidth: CGFloat = 174,
        spacing: CGFloat = 12,
        horizontalPadding: CGFloat = 12,
        bottomPadding: CGFloat = 20,
        topPadding: CGFloat = 44,
        detailCornerRadius: CGFloat = 16,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.background = background
        self.detailFillColor = detailFillColor
        self.detailStrokeColor = detailStrokeColor
        self.sidebarWidth = sidebarWidth
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.bottomPadding = bottomPadding
        self.topPadding = topPadding
        self.detailCornerRadius = detailCornerRadius
        self.sidebar = sidebar()
        self.header = header()
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                SettingsSmoothedRoundedRectangle(cornerRadius: 20, smoothing: 0.6)
                    .fill(background)
                    .ignoresSafeArea()

                content
                    .frame(
                        width: max(0, proxy.size.width - sidebarWidth - spacing - horizontalPadding),
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
                    .background(
                        SettingsSmoothedRoundedRectangle(cornerRadius: detailCornerRadius, smoothing: 0.6)
                            .fill(detailFillColor)
                    )
                    .overlay(
                        SettingsSmoothedRoundedRectangle(cornerRadius: detailCornerRadius, smoothing: 0.6)
                            .stroke(detailStrokeColor, lineWidth: 1)
                    )
                    .clipShape(
                        SettingsSmoothedRoundedRectangle(cornerRadius: detailCornerRadius, smoothing: 0.6)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                sidebar
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.leading, horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
            }
        }
    }
}
