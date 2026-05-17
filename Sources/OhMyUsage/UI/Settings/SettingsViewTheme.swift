import SwiftUI

extension SettingsView {
    // MARK: - 设置页视觉 Token（改这里可全局影响样式）
    // 整个设置页外层背景。
    var panelBackground: Color {
        settingsUsesLightAppearance ? Color(hex: 0xF3F4F6) : Color(hex: 0x232323)
    }

    // “通用设置”主内容滚动区域底色。
    var cardBackground: Color {
        settingsUsesLightAppearance ? Color(hex: 0xFFFFFF) : Color.black
    }

    // 通用描边色：用于模型面板、卡片边框等。
    var outlineColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.12)
    }

    // 内层卡片/黑色内容容器圆角。
    var cardCornerRadius: CGFloat { 12 }
    var settingsShellCornerRadius: CGFloat { 20 }
    var settingsSidebarCornerRadius: CGFloat { 20 }
    var settingsSectionCornerRadius: CGFloat { 12 }

    var settingsShellStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    var settingsSidebarFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.78) : Color.white.opacity(0.03)
    }

    var settingsSectionFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.035) : Color.black.opacity(0.22)
    }

    var settingsAccentBlue: Color { Color(hex: 0x168DFF) }
    var settingsAccentGreen: Color { Color(hex: 0x31D158) }
    var settingsAccentPurple: Color { Color(hex: 0xC93BFF) }
    var settingsAccentCyan: Color { Color(hex: 0x12D6F3) }

    // 分割线颜色。
    var dividerColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.15)
    }

    // 模型设置详情项垂直间距（设计稿统一 24px）。
    var modelSettingsItemSpacing: CGFloat { 24 }
    // 本地扫描区内部内容项间距（设计稿统一 12px）。
    var localDiscoveryItemSpacing: CGFloat { 12 }

    // 主要标题字号（例如“关于”页标题）。
    var settingsTitleFont: Font { .system(size: 16, weight: .semibold) }
    // 正文描述字号（12 Regular）。
    var settingsBodyFont: Font { .system(size: 12, weight: .regular) }
    // 标签标题字号（12 Semibold）。
    var settingsLabelFont: Font { .system(size: 12, weight: .semibold) }
    // 提示文字字号（10 Regular）。
    var settingsHintFont: Font { .system(size: 10, weight: .regular) }
    // 多行正文目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    var settingsBodyMultilineSpacing: CGFloat { 4 }
    // 多行提示文字目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    var settingsHintMultilineSpacing: CGFloat { 3 }

    // 标题文字颜色。
    var settingsTitleColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.80)
    }

    // 常规正文颜色。
    var settingsBodyColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.78) : Color.white.opacity(0.80)
    }

    // 次级提示色。
    var settingsHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.56) : Color.white.opacity(0.55)
    }

    // 更弱提示色，用于“检查失败”等弱错误提示。
    var settingsMutedHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.40) : Color.white.opacity(0.40)
    }

    // 输入框填充色。
    var settingsInputFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.06) : Color.white.opacity(0.15)
    }

    // 输入框占位色。
    var settingsInputPlaceholderColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.35) : Color.white.opacity(0.30)
    }

    var settingsSubtlePanelFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.035) : Color.white.opacity(0.03)
    }

    var settingsSubtlePanelStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.06)
    }

    var settingsSelectedRowFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.30)
    }

    var settingsSelectedRowStrokeColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.52) : Color.white.opacity(0.80)
    }

    var settingsRowStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.30)
    }

    var settingsDropIndicatorColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.90) : Color.white.opacity(0.90)
    }

    var settingsControlFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.05) : Color(hex: 0x2A2B2F)
    }

    var settingsControlStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    var settingsPopoverFillColor: Color {
        settingsUsesLightAppearance ? Color.white : Color(hex: 0x1F2024)
    }

    var settingsPopoverSelectedFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.12)
    }

    var settingsQuotaTrackColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.30)
    }

    var settingsTrendPrimaryColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.78) : Color.white.opacity(0.62)
    }

    var settingsTrendMutedColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.22)
    }

    var settingsSliderTintColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue : Color.white.opacity(0.80)
    }

    // API 余额页右侧配置项统一标签列宽与控件间距。
    var thirdPartyConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 56 : 112
    }

    var settingsNestedConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 24 : 56
    }

    var thirdPartyConfigLabelSpacing: CGFloat { 16 }

    var thirdPartyConfigControlWidth: CGFloat {
        534 - thirdPartyConfigLabelWidth - thirdPartyConfigLabelSpacing
    }

    var thirdPartyConfigSliderWidth: CGFloat {
        max(280, thirdPartyConfigControlWidth - 96)
    }

    var officialConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 60 : 112
    }

    var settingsGeneralLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 48 : 124
    }

    var settingsGeneralHintLeadingPadding: CGFloat {
        settingsGeneralLabelWidth + 16
    }

    var settingsMenuBarLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 60 : 160
    }

    var settingsMenuBarHintLeadingPadding: CGFloat {
        settingsMenuBarLabelWidth + 16
    }

    var settingsDetailLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 80 : 160
    }

    var theme: SettingsTheme {
        SettingsTheme(
            panelBackground: panelBackground,
            cardBackground: cardBackground,
            shellStrokeColor: settingsShellStrokeColor,
            sidebarFillColor: settingsSidebarFillColor,
            sectionFillColor: settingsSectionFillColor,
            subtlePanelFillColor: settingsSubtlePanelFillColor,
            subtlePanelStrokeColor: settingsSubtlePanelStrokeColor,
            sectionCornerRadius: settingsSectionCornerRadius,
            shellCornerRadius: settingsShellCornerRadius,
            sidebarCornerRadius: settingsSidebarCornerRadius,
            accentColor: settingsAccentBlue,
            dividerColor: dividerColor,
            titleColor: settingsTitleColor,
            hintColor: settingsHintColor,
            mutedHintColor: settingsMutedHintColor
        )
    }

    var settingsColorScheme: ColorScheme {
        .dark
    }

    var settingsUsesLightAppearance: Bool {
        false
    }

    func settingsSectionPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
    }

    func overviewAccentColor(_ accent: SettingsOverviewAccent) -> Color {
        switch accent {
        case .blue:
            return settingsAccentBlue
        case .green:
            return settingsAccentGreen
        case .purple:
            return settingsAccentPurple
        case .cyan:
            return settingsAccentCyan
        }
    }
}
