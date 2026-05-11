import Foundation

struct SettingsHeaderPresentation: Equatable {
    var title: String
    var subtitle: String
    var refreshButtonTitle: String
    var refreshHelpText: String
}

struct SettingsSidebarItemPresentation: Identifiable, Equatable {
    var tab: SettingsTab
    var icon: String
    var title: String

    var id: String { tab.rawValue }
}

struct SettingsSidebarSectionPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var items: [SettingsSidebarItemPresentation]
}

struct SettingsWorkspaceSidebarPresentation: Equatable {
    var appTitle: String
    var appSubtitle: String
    var currentVersionTitle: String
    var checkUpdatesTitle: String
    var updateButtonTitle: String
    var lastRefreshTitle: String
    var githubTitle: String
    var sections: [SettingsSidebarSectionPresentation]
}

enum SettingsWorkspacePresenter {
    static func headerPresentation(
        selectedTab: SettingsTab,
        localizedText: (String, String) -> String,
        generalTabTitle: String
    ) -> SettingsHeaderPresentation {
        let title: String
        let subtitle: String

        switch selectedTab {
        case .overview:
            title = localizedText("设置概览", "Settings Overview")
            subtitle = localizedText(
                "把监控、权限和服务配置收拢成一个可快速扫描的工作台。",
                "A scannable workspace for monitoring, permissions, and service configuration."
            )
        case .general:
            title = generalTabTitle
            subtitle = localizedText(
                "管理应用语言、启动行为和基础偏好。",
                "Manage app language, launch behavior, and basic preferences."
            )
        case .menuBar:
            title = localizedText("菜单栏", "Menubar")
            subtitle = localizedText(
                "调整菜单栏里显示哪些模型、如何显示以及跟随哪种外观。",
                "Adjust which models appear in the menubar, how they render, and which appearance mode they use."
            )
        case .permissions:
            title = localizedText("权限", "Permissions")
            subtitle = localizedText(
                "检查授权状态，确保通知、钥匙串和本地读取能力可用。",
                "Review authorization status for notifications, keychain, and local file access."
            )
        case .localData:
            title = localizedText("本地数据", "Local Data")
            subtitle = localizedText(
                "发现本地 CLI 账号配置，或在需要时清理本地应用数据。",
                "Discover local CLI account config or clear local app data when needed."
            )
        case .officialProviders:
            title = localizedText("官方服务", "Official Services")
            subtitle = localizedText(
                "管理 Codex、Claude、Gemini、Cursor 等官方来源和账号。",
                "Manage official sources and accounts such as Codex, Claude, Gemini, and Cursor."
            )
        case .customProviders:
            title = localizedText("自定义接口", "Custom Endpoints")
            subtitle = localizedText(
                "配置 Relay、New API 和第三方余额接口。",
                "Configure Relay, New API, and third-party balance endpoints."
            )
        }

        return SettingsHeaderPresentation(
            title: title,
            subtitle: subtitle,
            refreshButtonTitle: localizedText("刷新全部", "Refresh All"),
            refreshHelpText: localizedText("立即刷新所有已启用服务", "Refresh all enabled services now")
        )
    }

    static func sidebarPresentation(
        localizedText: (String, String) -> String,
        generalTabTitle: String
    ) -> SettingsWorkspaceSidebarPresentation {
        SettingsWorkspaceSidebarPresentation(
            appTitle: "oh-myusage",
            appSubtitle: localizedText("监控与设置工作台", "Monitoring workspace"),
            currentVersionTitle: localizedText("版本", "Version"),
            checkUpdatesTitle: localizedText("检查更新", "Check Updates"),
            updateButtonTitle: localizedText("更新版本", "Update App"),
            lastRefreshTitle: localizedText("最近刷新", "Last refresh"),
            githubTitle: "GitHub",
            sections: [
                SettingsSidebarSectionPresentation(
                    id: "main",
                    title: "",
                    items: [
                        SettingsSidebarItemPresentation(
                            tab: .general,
                            icon: "settings_sidebar_general_icon",
                            title: generalTabTitle
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .menuBar,
                            icon: "settings_sidebar_menubar_icon",
                            title: localizedText("菜单栏", "Menubar")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .officialProviders,
                            icon: "settings_sidebar_official_icon",
                            title: localizedText("官方订阅", "Official")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .customProviders,
                            icon: "menu_relay_icon",
                            title: localizedText("中转代理", "Relay")
                        )
                    ]
                )
            ]
        )
    }
}
