import SwiftUI

struct PermissionTileHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DialogSmoothRoundedRectangle: InsettableShape {
    var cornerRadius: CGFloat
    var smoothing: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat, smoothing: CGFloat) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
        self.insetAmount = 0
    }

    private init(cornerRadius: CGFloat, smoothing: CGFloat, insetAmount: CGFloat) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
        self.insetAmount = insetAmount
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(min(rect.width, rect.height) / 2, cornerRadius))
        guard radius > 0 else { return Path(rect) }

        let s = max(0, min(1, smoothing))
        let circularK: CGFloat = 0.552_284_75
        let squircleK: CGFloat = 0.34
        let k = circularK - (circularK - squircleK) * s
        let cp = radius * k

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + radius),
            control1: CGPoint(x: maxX - cp, y: minY),
            control2: CGPoint(x: maxX, y: minY + cp)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - cp),
            control2: CGPoint(x: maxX - cp, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control1: CGPoint(x: minX + cp, y: maxY),
            control2: CGPoint(x: minX, y: maxY - cp)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addCurve(
            to: CGPoint(x: minX + radius, y: minY),
            control1: CGPoint(x: minX, y: minY + cp),
            control2: CGPoint(x: minX + cp, y: minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        DialogSmoothRoundedRectangle(
            cornerRadius: cornerRadius,
            smoothing: smoothing,
            insetAmount: insetAmount + amount
        )
    }
}
