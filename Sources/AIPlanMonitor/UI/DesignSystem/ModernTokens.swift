import AppKit
import SwiftUI

/// 现代化设计系统 Token
enum ModernDesignTokens {
    // MARK: - 玻璃态材质
    static let glassMaterial: NSVisualEffectView.Material = .hudWindow
    static let glassOpacity: Double = 0.75
    static let glassBlurRadius: CGFloat = 40

    // MARK: - 圆角
    static let cardCornerRadius: CGFloat = 16  // 12→16
    static let panelCornerRadius: CGFloat = 20
    static let buttonCornerRadius: CGFloat = 8

    // MARK: - 间距
    static let cardPadding: CGFloat = 16  // 12→16
    static let cardSpacing: CGFloat = 8   // 6→8

    // MARK: - 阴影
    static let cardShadowRadius: CGFloat = 10
    static let cardShadowY: CGFloat = 4
    static let cardHoverShadowRadius: CGFloat = 20
    static let cardHoverShadowY: CGFloat = 8

    // MARK: - 动画
    static let springResponse: Double = 0.3
    static let springDamping: Double = 0.7
    static let hoverScale: CGFloat = 1.02
    static let pressScale: CGFloat = 0.9

    // MARK: - 颜色（保持现有）
    static func color(hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    static let sufficientColor = color(hex: 0x69BD64)
    static let warningColor = color(hex: 0xD87E3E)
    static let errorColor = color(hex: 0xD05757)
}
