import SwiftUI

struct QuotaBlockedStripePattern: Shape {
    var stripeWidth: CGFloat = 3
    var spacing: CGFloat = 8
    var slant: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for x in stride(from: rect.minX - slant, through: rect.maxX + slant, by: spacing) {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + stripeWidth + slant, y: rect.minY))
            path.addLine(to: CGPoint(x: x + slant, y: rect.minY))
            path.closeSubpath()
        }

        return path
    }
}
