import SwiftUI

/// 脉冲指示器，用于显示实时活动状态
struct PulseIndicator: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    let color: Color

    init(color: Color = .green) {
        self.color = color
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(scale)
                    .opacity(opacity)
            )
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    scale = 2.0
                    opacity = 0
                }
            }
    }
}
