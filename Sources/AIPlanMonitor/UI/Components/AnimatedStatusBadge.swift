import SwiftUI

/// 带动画的状态徽章组件
struct AnimatedStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.9))
                    .overlay(
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .animation(
                .spring(
                    response: ModernDesignTokens.springResponse + 0.1,
                    dampingFraction: ModernDesignTokens.springDamping
                ),
                value: color
            )
    }
}
