import CoreGraphics

enum MenuPanelGeometryResolver {
    static func fallbackStatusIconRect(
        buttonBounds: CGRect,
        statusIconSize: CGFloat
    ) -> CGRect {
        CGRect(
            x: buttonBounds.minX,
            y: (buttonBounds.height - statusIconSize) / 2,
            width: statusIconSize,
            height: statusIconSize
        )
    }

    static func alignedPanelFrame(
        panelFrame: CGRect,
        iconRectOnScreen: CGRect,
        visibleFrame: CGRect?,
        gapBelowStatusIcon: CGFloat
    ) -> CGRect {
        var frame = panelFrame
        frame.origin.x = round(iconRectOnScreen.midX - (frame.width / 2))
        frame.origin.y = round(iconRectOnScreen.minY - gapBelowStatusIcon - frame.height)

        if let visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        }

        return frame
    }

    static func horizontalCenterRatio(
        rectOnScreen: CGRect,
        screenFrame: CGRect
    ) -> Double {
        guard screenFrame.width > 0 else {
            return 0.5
        }
        let normalized = (rectOnScreen.midX - screenFrame.minX) / screenFrame.width
        return min(max(Double(normalized), 0), 1)
    }
}
