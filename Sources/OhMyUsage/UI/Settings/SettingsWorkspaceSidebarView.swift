import SwiftUI

struct SettingsWorkspaceSidebarView<Identity: View>: View {
    private let sidebarWidth: CGFloat = 174
    private let footerHorizontalInset: CGFloat = 8
    private let footerContentWidth: CGFloat = 158
    private let footerRowHeight: CGFloat = 16

    var presentation: SettingsWorkspaceSidebarPresentation
    var selectedTab: SettingsTab
    var currentVersion: String
    var lastRefreshText: String
    var updateDisabled: Bool
    var showsUpdateButton: Bool
    var theme: SettingsTheme
    var onSelectTab: (SettingsTab) -> Void
    var onUpdateAction: () -> Void
    var onCheckUpdates: () -> Void
    var onOpenGitHub: () -> Void
    var identity: Identity

    init(
        presentation: SettingsWorkspaceSidebarPresentation,
        selectedTab: SettingsTab,
        currentVersion: String,
        lastRefreshText: String,
        updateDisabled: Bool,
        showsUpdateButton: Bool,
        theme: SettingsTheme,
        onSelectTab: @escaping (SettingsTab) -> Void,
        onUpdateAction: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        onOpenGitHub: @escaping () -> Void,
        @ViewBuilder identity: () -> Identity
    ) {
        self.presentation = presentation
        self.selectedTab = selectedTab
        self.currentVersion = currentVersion
        self.lastRefreshText = lastRefreshText
        self.updateDisabled = updateDisabled
        self.showsUpdateButton = showsUpdateButton
        self.theme = theme
        self.onSelectTab = onSelectTab
        self.onUpdateAction = onUpdateAction
        self.onCheckUpdates = onCheckUpdates
        self.onOpenGitHub = onOpenGitHub
        self.identity = identity()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(presentation.sections) { section in
                    ForEach(section.items) { item in
                        tabButton(item)
                    }
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tabButton(_ item: SettingsSidebarItemPresentation) -> some View {
        let isSelected = selectedTab == item.tab

        return Button {
            onSelectTab(item.tab)
        } label: {
            HStack(alignment: .center, spacing: 6) {
                sidebarIcon(named: item.iconName(isSelected: isSelected), opacity: isSelected ? 0.8 : 0.4)
                    .frame(width: 14, height: 14)

                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.titleColor.opacity(0.8) : theme.hintColor.opacity(0.4))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: sidebarWidth, height: 30, alignment: .leading)
            .background {
                if isSelected {
                    SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsUpdateButton {
                Button(action: onUpdateAction) {
                    HStack(spacing: 6) {
                        footerIcon(
                            named: "settings_download_icon",
                            opacity: updateDisabled ? 0.42 : 1,
                            contentWidth: 7,
                            contentHeight: 10.5,
                            frameSize: 14
                        )

                        Text(presentation.updateButtonTitle)
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(hex: 0x69BD64).opacity(updateDisabled ? 0.42 : 1))
                    .padding(.horizontal, 8)
                    .frame(width: footerContentWidth, height: 30, alignment: .leading)
                    .overlay(
                        SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: 0x69BD64).opacity(updateDisabled ? 0.42 : 1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(updateDisabled)
            }

            HStack(spacing: 4) {
                footerIcon(named: "settings_version_icon", opacity: 1)

                HStack(spacing: 0) {
                    Text("\(presentation.currentVersionTitle)：\(currentVersion)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.mutedHintColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: onCheckUpdates) {
                        Text(presentation.checkUpdatesTitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(theme.mutedHintColor.opacity(updateDisabled ? 0.6 : 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(updateDisabled)
                }
                .frame(width: 138, height: 12, alignment: .leading)
            }
            .frame(width: footerContentWidth, height: footerRowHeight, alignment: .leading)

            Button(action: onOpenGitHub) {
                HStack(spacing: 4) {
                    footerIcon(named: "settings_github_icon", opacity: 1)

                    Text(presentation.githubTitle)
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(theme.mutedHintColor)

                    Spacer(minLength: 0)
                }
                .frame(width: footerContentWidth, height: footerRowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: footerContentWidth, alignment: .leading)
        .padding(.horizontal, footerHorizontalInset)
        .frame(width: sidebarWidth, alignment: .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func sidebarIcon(named name: String, opacity: Double, preferSVG: Bool = false) -> some View {
        if let image = bundledImage(named: name, preferSVG: preferSVG) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .opacity(opacity)
        } else {
            Color.clear
        }
    }

    private func footerIcon(
        named name: String,
        opacity: Double,
        contentWidth: CGFloat = 12,
        contentHeight: CGFloat = 12,
        frameSize: CGFloat = 16,
        preferSVG: Bool = false
    ) -> some View {
        sidebarIcon(named: name, opacity: opacity, preferSVG: preferSVG)
            .frame(width: contentWidth, height: contentHeight)
            .frame(width: frameSize, height: frameSize)
    }

    private func bundledImage(named name: String, preferSVG: Bool = false) -> NSImage? {
        if preferSVG,
           let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }
}
