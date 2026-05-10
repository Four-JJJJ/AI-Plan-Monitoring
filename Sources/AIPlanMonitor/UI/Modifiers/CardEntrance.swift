import SwiftUI

/// 卡片入场动画修饰器
struct CardEntranceModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(
                    .spring(
                        response: ModernDesignTokens.springResponse * 2,
                        dampingFraction: ModernDesignTokens.springDamping + 0.1
                    )
                    .delay(delay)
                ) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func cardEntrance(delay: Double = 0) -> some View {
        modifier(CardEntranceModifier(delay: delay))
    }
}
