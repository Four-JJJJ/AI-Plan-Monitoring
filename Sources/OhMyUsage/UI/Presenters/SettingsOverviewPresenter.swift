import OhMyUsageApplication
import Foundation

enum SettingsOverviewAccent: Equatable {
    case blue
    case green
    case purple
    case cyan
}

struct SettingsOverviewCardPresentation: Identifiable, Equatable {
    var id: String
    var icon: String
    var title: String
    var value: String
    var detail: String
    var accent: SettingsOverviewAccent
}

enum SettingsOverviewPresenter {
    static func cards(
        providers: [ProviderDescriptor],
        statusBarMultiUsageEnabled: Bool,
        statusBarMultiProviderIDs: [String],
        statusBarProviderID: String?,
        statusBarAppearanceMode: StatusBarAppearanceMode,
        statusBarDisplayStyle: StatusBarDisplayStyle,
        hasNotificationPermission: Bool,
        secureStorageReady: Bool,
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool,
        fullDiskAccessGranted: Bool,
        localizedText: (String, String) -> String
    ) -> [SettingsOverviewCardPresentation] {
        let totalProviders = providers.count
        let enabledProviders = providers.filter(\.enabled).count
        let disabledProviders = totalProviders - enabledProviders
        let officialProviderCount = providers.filter { $0.family == .official }.count
        let thirdPartyProviderCount = providers.filter { $0.family == .thirdParty }.count
        let requiredPermissions = permissionCount(
            fullDiskAccessRelevant: fullDiskAccessRelevant,
            fullDiskAccessRequested: fullDiskAccessRequested
        )
        let grantedPermissions = grantedPermissionCount(
            hasNotificationPermission: hasNotificationPermission,
            secureStorageReady: secureStorageReady,
            fullDiskAccessRelevant: fullDiskAccessRelevant,
            fullDiskAccessRequested: fullDiskAccessRequested,
            fullDiskAccessGranted: fullDiskAccessGranted
        )
        return [
            SettingsOverviewCardPresentation(
                id: "providers",
                icon: "square.stack.3d.up",
                title: localizedText("已追踪服务", "Tracked Providers"),
                value: "\(totalProviders)",
                detail: localizedText(
                    "\(officialProviderCount) 个官方来源，\(thirdPartyProviderCount) 个自定义来源",
                    "\(officialProviderCount) official sources, \(thirdPartyProviderCount) custom sources"
                ),
                accent: .blue
            ),
            SettingsOverviewCardPresentation(
                id: "enabled",
                icon: "bolt.heart",
                title: localizedText("活跃监控", "Active Monitors"),
                value: "\(enabledProviders)",
                detail: disabledProviders > 0
                    ? localizedText("还有 \(disabledProviders) 个已停用", "\(disabledProviders) currently disabled")
                    : localizedText("全部服务都已启用", "All services enabled"),
                accent: .green
            ),
            SettingsOverviewCardPresentation(
                id: "permissions",
                icon: "lock.shield",
                title: localizedText("权限状态", "Permissions"),
                value: "\(grantedPermissions)/\(requiredPermissions)",
                detail: localizedText(
                    "通知、钥匙串与全盘访问统一收纳",
                    "Notifications, keychain, and full disk access in one place"
                ),
                accent: .purple
            ),
            SettingsOverviewCardPresentation(
                id: "menubar",
                icon: "menubar.rectangle",
                title: localizedText("界面与菜单栏", "Interface & Menubar"),
                value: statusBarMultiUsageEnabled
                    ? localizedText("多模型", "Multi")
                    : localizedText("单模型", "Single"),
                detail: localizedText(
                    "菜单栏外观 \(statusBarAppearanceModeSummary(statusBarAppearanceMode, localizedText: localizedText)) · 样式 \(statusBarDisplayStyleSummary(statusBarDisplayStyle, localizedText: localizedText))",
                    "Menubar appearance \(statusBarAppearanceModeSummary(statusBarAppearanceMode, localizedText: localizedText)) · Style \(statusBarDisplayStyleSummary(statusBarDisplayStyle, localizedText: localizedText))"
                ),
                accent: .cyan
            )
        ]
    }

    static func officialUsageTrendProviders(
        providers: [ProviderDescriptor],
        shouldShow: (ProviderDescriptor) -> Bool
    ) -> [ProviderDescriptor] {
        providers.filter { provider in
            provider.enabled && shouldShow(provider)
        }
    }

    static func officialUsageTrendTitle(
        displayName: String,
        language: AppLanguage
    ) -> String {
        if language == .zhHans {
            return "\(displayName) 使用趋势"
        }
        return "\(displayName) Usage Trend"
    }

    static func lastRefreshText(
        lastUpdatedAt: Date?,
        now: Date,
        language: AppLanguage,
        localizedText: (String, String) -> String
    ) -> String {
        guard let lastUpdatedAt else {
            return localizedText("尚未刷新", "Not refreshed yet")
        }
        return elapsedText(from: lastUpdatedAt, now: now, language: language)
    }

    static func elapsedText(
        from date: Date,
        now: Date,
        language: AppLanguage
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch language {
        case .zhHans:
            if seconds < 60 { return "\(seconds) 秒前" }
            if seconds < 3600 { return "\(seconds / 60) 分钟前" }
            if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
            return "\(seconds / 86_400) 天前"
        case .en:
            if seconds < 60 { return "\(seconds)s ago" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86_400 { return "\(seconds / 3600)h ago" }
            return "\(seconds / 86_400)d ago"
        }
    }

    private static func permissionCount(
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool
    ) -> Int {
        var count = 2
        if fullDiskAccessRelevant || fullDiskAccessRequested {
            count += 1
        }
        return count
    }

    private static func grantedPermissionCount(
        hasNotificationPermission: Bool,
        secureStorageReady: Bool,
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool,
        fullDiskAccessGranted: Bool
    ) -> Int {
        var count = 0
        if hasNotificationPermission {
            count += 1
        }
        if secureStorageReady {
            count += 1
        }
        if (fullDiskAccessRelevant || fullDiskAccessRequested) && fullDiskAccessGranted {
            count += 1
        }
        return count
    }

    private static func statusBarAppearanceModeSummary(
        _ mode: StatusBarAppearanceMode,
        localizedText: (String, String) -> String
    ) -> String {
        switch mode {
        case .followWallpaper:
            return localizedText("跟随壁纸", "Adaptive")
        case .dark:
            return localizedText("深色", "Dark")
        case .light:
            return localizedText("浅色", "Light")
        }
    }

    private static func statusBarDisplayStyleSummary(
        _ style: StatusBarDisplayStyle,
        localizedText: (String, String) -> String
    ) -> String {
        switch style {
        case .iconPercent:
            return localizedText("图标 + 百分比", "Icon + percent")
        case .barNamePercent:
            return localizedText("柱状 + 名称", "Bar + name")
        }
    }

}
