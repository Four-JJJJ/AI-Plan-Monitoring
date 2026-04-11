import Foundation

enum L10nKey {
    case appTitle
    case overview
    case settings
    case settingsTitle
    case done
    case general
    case providers
    case relaySimpleMode
    case relaySimpleModeHint
    case enabled
    case toggleOn
    case toggleOff
    case noEnabledProviders
    case language
    case chinese
    case english
    case statusNormal
    case statusAlert
    case statusDisconnected
    case lastUpdate
    case lowThreshold
    case refreshNow
    case quit
    case error
    case pasteToken
    case save
    case tokenSaved
    case noToken
    case remaining
    case used
    case limit
    case resetsAt
    case unlimited
    case lowBalanceWarning
    case providerUnreachable
    case authError
    case tokenInvalidOrExpired
    case addRelayProvider
    case providerName
    case baseURL
    case addProvider
    case removeProvider
    case saveConfig
    case saveToken
    case enableTokenChannel
    case enableAccountChannel
    case pasteSystemToken
    case userID
    case userIDHeader
    case authHeader
    case authScheme
    case endpointPath
    case remainingPath
    case usedPath
    case limitPath
    case successPath
    case unit
    case relayRequiredFieldsHint
    case kimiAuthMode
    case kimiAuthManual
    case kimiAuthAuto
    case kimiManualToken
    case kimiAutoDetect
    case kimiAuthDetected
    case kimiAuthNotFound
    case kimiFdaHint
    case kimiOpenPrivacySettings
    case kimiBrowserOrder
    case kimiAutoCookie
    case kimiWeekly
    case kimiWindow5h
    case inSuffix
    case countdownTitle
    case quotaFiveHour
    case quotaWeekly
    case statusSufficient
    case statusQuotaTight
    case statusBalanceSufficient
    case statusBalanceTight
    case statusBalanceExhausted
    case statusTight
    case statusExhausted
    case statusActive
    case codexReadyToSwitch
    case updatedAgo
    case balanceLabel
    case thirdPartyRelay
    case officialProviders
    case thirdPartyProviders
    case officialTab
    case thirdPartyTab
    case selectProviderHint
    case sourceMode
    case webMode
    case webDisabled
    case webAutoImport
    case webManual
    case manualCookieHeader
    case officialAutoDiscoveryHint
    case matchedAdapter
    case relayTemplate
    case relayTemplatePresetHint
    case authSourceLabel
    case credentialMode
    case credentialModeManualPreferred
    case credentialModeBrowserPreferred
    case credentialModeBrowserOnly
    case credentialModeHint
    case testConnection
    case connectionSuccess
    case connectionFailed
    case advancedSettings
    case statusBarDisplayProvider
}

enum Localizer {
    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            switch key {
            case .appTitle: return "AI Plan 监控"
            case .overview: return "总览"
            case .settings: return "设置..."
            case .settingsTitle: return "设置"
            case .done: return "完成"
            case .general: return "通用"
            case .providers: return "数据源"
            case .relaySimpleMode: return "第三方极简配置（推荐）"
            case .relaySimpleModeHint: return "开启后仅保留核心项，接口路径与字段解析自动使用站点模板。"
            case .enabled: return "启用"
            case .toggleOn: return "开启"
            case .toggleOff: return "关闭"
            case .noEnabledProviders: return "暂无启用的数据源，请在设置中开启"
            case .language: return "语言"
            case .chinese: return "中文"
            case .english: return "English"
            case .statusNormal: return "正常"
            case .statusAlert: return "告警"
            case .statusDisconnected: return "失联"
            case .lastUpdate: return "最近更新"
            case .lowThreshold: return "低余额阈值"
            case .refreshNow: return "立即刷新"
            case .quit: return "退出"
            case .error: return "错误"
            case .pasteToken: return "粘贴 Token"
            case .save: return "保存"
            case .tokenSaved: return "已保存"
            case .noToken: return "未配置"
            case .remaining: return "剩余"
            case .used: return "已用"
            case .limit: return "上限"
            case .resetsAt: return "重置于"
            case .unlimited: return "不限额"
            case .lowBalanceWarning: return "低余额告警"
            case .providerUnreachable: return "服务不可用"
            case .authError: return "认证错误"
            case .tokenInvalidOrExpired: return "Token 无效或已过期"
            case .addRelayProvider: return "新增第三方中转"
            case .providerName: return "名称"
            case .baseURL: return "Base URL"
            case .addProvider: return "添加"
            case .removeProvider: return "移除"
            case .saveConfig: return "保存配置"
            case .saveToken: return "保存 Token"
            case .enableTokenChannel: return "启用 Token 配额通道"
            case .enableAccountChannel: return "启用账户余额通道"
            case .pasteSystemToken: return "粘贴系统访问令牌"
            case .userID: return "用户 ID"
            case .userIDHeader: return "用户 Header"
            case .authHeader: return "认证 Header"
            case .authScheme: return "认证前缀"
            case .endpointPath: return "余额接口路径"
            case .remainingPath: return "剩余字段路径"
            case .usedPath: return "已用字段路径"
            case .limitPath: return "上限字段路径"
            case .successPath: return "成功字段路径"
            case .unit: return "单位"
            case .relayRequiredFieldsHint: return "必填：名称、Base URL、Token。若需账户余额，再填系统令牌、用户ID和字段路径。"
            case .kimiAuthMode: return "认证模式"
            case .kimiAuthManual: return "手动"
            case .kimiAuthAuto: return "自动"
            case .kimiManualToken: return "粘贴 kimi-auth Token"
            case .kimiAutoDetect: return "自动检测 Token"
            case .kimiAuthDetected: return "已检测到"
            case .kimiAuthNotFound: return "未找到可用的 Kimi 登录 Cookie"
            case .kimiFdaHint: return "自动读取浏览器 Cookie 需要 Full Disk Access 权限。"
            case .kimiOpenPrivacySettings: return "打开隐私设置"
            case .kimiBrowserOrder: return "浏览器顺序"
            case .kimiAutoCookie: return "启用自动读取浏览器 Cookie"
            case .kimiWeekly: return "周配额"
            case .kimiWindow5h: return "5小时限额"
            case .inSuffix: return "后"
            case .countdownTitle: return "倒计时"
            case .quotaFiveHour: return "5h限额"
            case .quotaWeekly: return "周限额"
            case .statusSufficient: return "充足"
            case .statusQuotaTight: return "限额紧张"
            case .statusBalanceSufficient: return "余额充足"
            case .statusBalanceTight: return "余额紧张"
            case .statusBalanceExhausted: return "余额耗尽"
            case .statusTight: return "紧张"
            case .statusExhausted: return "耗尽"
            case .statusActive: return "激活中"
            case .codexReadyToSwitch: return "已重置，可切换"
            case .updatedAgo: return "更新于"
            case .balanceLabel: return "余额"
            case .thirdPartyRelay: return "第三方中转"
            case .officialProviders: return "官方订阅来源"
            case .thirdPartyProviders: return "第三方来源"
            case .officialTab: return "官方订阅"
            case .thirdPartyTab: return "第三方中转"
            case .selectProviderHint: return "请先在左侧选择模型"
            case .sourceMode: return "来源模式"
            case .webMode: return "网页来源"
            case .webDisabled: return "关闭"
            case .webAutoImport: return "自动导入"
            case .webManual: return "手动"
            case .manualCookieHeader: return "手动 Cookie/Header"
            case .officialAutoDiscoveryHint: return "默认会自动发现本地 CLI 登录态；手动 Cookie 仅作为网页来源修复入口。"
            case .matchedAdapter: return "匹配模板"
            case .relayTemplate: return "站点模板"
            case .relayTemplatePresetHint: return "优先选择已验证过的站点模板；只在站点接口不一致时再改 Base URL 或展开高级设置。"
            case .authSourceLabel: return "认证来源"
            case .credentialMode: return "凭证模式"
            case .credentialModeManualPreferred: return "手动优先"
            case .credentialModeBrowserPreferred: return "浏览器优先"
            case .credentialModeBrowserOnly: return "仅浏览器"
            case .credentialModeHint: return "浏览器优先会在手动凭证过期或失效时自动尝试读取浏览器登录态；仅浏览器模式不会使用你手动保存的 Cookie 或 Token。"
            case .testConnection: return "测试连接"
            case .connectionSuccess: return "连接成功"
            case .connectionFailed: return "连接失败"
            case .advancedSettings: return "高级设置"
            case .statusBarDisplayProvider: return "在状态栏展示该模型"
            }
        case .en:
            switch key {
            case .appTitle: return "AI Plan Monitor"
            case .overview: return "Overview"
            case .settings: return "Settings..."
            case .settingsTitle: return "Settings"
            case .done: return "Done"
            case .general: return "General"
            case .providers: return "Providers"
            case .relaySimpleMode: return "Minimal third-party setup (Recommended)"
            case .relaySimpleModeHint: return "When enabled, only core fields are shown and endpoint/JSON paths follow site templates."
            case .enabled: return "Enabled"
            case .toggleOn: return "On"
            case .toggleOff: return "Off"
            case .noEnabledProviders: return "No enabled providers. Enable them in Settings."
            case .language: return "Language"
            case .chinese: return "中文"
            case .english: return "English"
            case .statusNormal: return "Normal"
            case .statusAlert: return "Alert"
            case .statusDisconnected: return "Disconnected"
            case .lastUpdate: return "Last update"
            case .lowThreshold: return "Low threshold"
            case .refreshNow: return "Refresh Now"
            case .quit: return "Quit"
            case .error: return "Error"
            case .pasteToken: return "Paste token"
            case .save: return "Save"
            case .tokenSaved: return "Token saved"
            case .noToken: return "No token"
            case .remaining: return "Remaining"
            case .used: return "Used"
            case .limit: return "Limit"
            case .resetsAt: return "Resets"
            case .unlimited: return "Unlimited"
            case .lowBalanceWarning: return "Low Balance Warning"
            case .providerUnreachable: return "Provider Unreachable"
            case .authError: return "Auth Error"
            case .tokenInvalidOrExpired: return "Token invalid or expired"
            case .addRelayProvider: return "Add Relay Provider"
            case .providerName: return "Name"
            case .baseURL: return "Base URL"
            case .addProvider: return "Add"
            case .removeProvider: return "Remove"
            case .saveConfig: return "Save Config"
            case .saveToken: return "Save Token"
            case .enableTokenChannel: return "Enable token quota channel"
            case .enableAccountChannel: return "Enable account balance channel"
            case .pasteSystemToken: return "Paste system access token"
            case .userID: return "User ID"
            case .userIDHeader: return "User header"
            case .authHeader: return "Auth header"
            case .authScheme: return "Auth scheme"
            case .endpointPath: return "Balance endpoint path"
            case .remainingPath: return "Remaining JSON path"
            case .usedPath: return "Used JSON path"
            case .limitPath: return "Limit JSON path"
            case .successPath: return "Success JSON path"
            case .unit: return "Unit"
            case .relayRequiredFieldsHint: return "Required: Name, Base URL, token. For account balance also provide system token, user ID, and JSON paths."
            case .kimiAuthMode: return "Auth mode"
            case .kimiAuthManual: return "Manual"
            case .kimiAuthAuto: return "Auto"
            case .kimiManualToken: return "Paste kimi-auth token"
            case .kimiAutoDetect: return "Auto detect token"
            case .kimiAuthDetected: return "Detected"
            case .kimiAuthNotFound: return "No usable Kimi session cookie found"
            case .kimiFdaHint: return "Automatic browser cookie import requires Full Disk Access."
            case .kimiOpenPrivacySettings: return "Open Privacy Settings"
            case .kimiBrowserOrder: return "Browser order"
            case .kimiAutoCookie: return "Enable browser cookie auto import"
            case .kimiWeekly: return "Weekly quota"
            case .kimiWindow5h: return "5-hour window"
            case .inSuffix: return ""
            case .countdownTitle: return "Countdown"
            case .quotaFiveHour: return "5h window"
            case .quotaWeekly: return "Weekly quota"
            case .statusSufficient: return "Healthy"
            case .statusQuotaTight: return "Quota tight"
            case .statusBalanceSufficient: return "Balance healthy"
            case .statusBalanceTight: return "Balance low"
            case .statusBalanceExhausted: return "Balance exhausted"
            case .statusTight: return "Tight"
            case .statusExhausted: return "Exhausted"
            case .statusActive: return "Active"
            case .codexReadyToSwitch: return "Reset, ready to switch"
            case .updatedAgo: return "Updated"
            case .balanceLabel: return "Balance"
            case .thirdPartyRelay: return "Relay Provider"
            case .officialProviders: return "Official Providers"
            case .thirdPartyProviders: return "Third-Party Providers"
            case .officialTab: return "Official"
            case .thirdPartyTab: return "Relay"
            case .selectProviderHint: return "Select a provider from the left"
            case .sourceMode: return "Source mode"
            case .webMode: return "Web mode"
            case .webDisabled: return "Disabled"
            case .webAutoImport: return "Auto Import"
            case .webManual: return "Manual"
            case .manualCookieHeader: return "Manual Cookie/Header"
            case .officialAutoDiscoveryHint: return "Local CLI credentials are auto-discovered by default; manual cookie input is only for web-source repair."
            case .matchedAdapter: return "Matched adapter"
            case .relayTemplate: return "Site template"
            case .relayTemplatePresetHint: return "Prefer a verified site template first. Only change Base URL or open Advanced settings when the site behaves differently."
            case .authSourceLabel: return "Auth source"
            case .credentialMode: return "Credential mode"
            case .credentialModeManualPreferred: return "Manual First"
            case .credentialModeBrowserPreferred: return "Browser First"
            case .credentialModeBrowserOnly: return "Browser Only"
            case .credentialModeHint: return "Browser-first mode automatically retries with live browser credentials when saved tokens expire. Browser-only mode ignores manually saved cookies or tokens."
            case .testConnection: return "Test connection"
            case .connectionSuccess: return "Connection successful"
            case .connectionFailed: return "Connection failed"
            case .advancedSettings: return "Advanced settings"
            case .statusBarDisplayProvider: return "Show this provider in menu bar"
            }
        }
    }

    static func lowBalanceBody(providerName: String, remaining: String, unit: String, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "\(providerName) 剩余 \(remaining) \(unit)"
        case .en:
            return "\(providerName) remaining \(remaining) \(unit)"
        }
    }

    static func providerFailedBody(providerName: String, failures: Int, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "\(providerName) 连续失败 \(failures) 次"
        case .en:
            return "\(providerName) failed \(failures) times"
        }
    }

    static func authErrorBody(providerName: String, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "\(providerName) Token 无效或已过期"
        case .en:
            return "\(providerName) token invalid or expired"
        }
    }
}
