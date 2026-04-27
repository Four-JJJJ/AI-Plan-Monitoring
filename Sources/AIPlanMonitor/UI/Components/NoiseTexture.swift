import SwiftUI

/// 噪点纹理组件，为玻璃态背景增加质感
struct NoiseTexture: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            // 生成随机噪点
            for _ in 0..<Int(size.width * size.height / 100) {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }
}
