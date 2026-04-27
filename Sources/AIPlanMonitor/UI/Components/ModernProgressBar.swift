import SwiftUI

/// 现代化进度条组件
struct ModernProgressBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景轨道
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                    )

                // 进度填充
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color,
                                color.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        // 光泽效果
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: max(4, geo.size.width * percent / 100))
                    .animation(
                        .spring(
                            response: ModernDesignTokens.springResponse * 2,
                            dampingFraction: ModernDesignTokens.springDamping + 0.1
                        ),
                        value: percent
                    )
            }
        }
        .frame(height: 6)  // 增加高度 4→6
    }
}
