import SwiftUI

/// 玻璃态背景组件
struct GlassmorphicBackground: View {
    let blurRadius: CGFloat = ModernDesignTokens.glassBlurRadius
    let opacity: Double = ModernDesignTokens.glassOpacity

    var body: some View {
        ZStack {
            // 背景模糊层
            VisualEffectBlur(
                material: ModernDesignTokens.glassMaterial,
                blendingMode: .behindWindow
            )

            // 半透明色彩层
            LinearGradient(
                colors: [
                    ModernDesignTokens.color(hex: 0x1A1A1A).opacity(opacity),
                    ModernDesignTokens.color(hex: 0x0F0F0F).opacity(opacity)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 噪点纹理（增加质感）
            NoiseTexture(opacity: 0.02)
        }
    }
}
