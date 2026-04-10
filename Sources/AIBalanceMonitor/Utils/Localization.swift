import Foundation

enum L10nKey {
    case appTitle
    case overview
    case settings
    case settingsTitle
    case done
    case general
    case providers
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
    case updatedAgo
    case balanceLabel
    case thirdPartyRelay
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
            case .updatedAgo: return "更新于"
            case .balanceLabel: return "余额"
            case .thirdPartyRelay: return "第三方中转"
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
            case .updatedAgo: return "Updated"
            case .balanceLabel: return "Balance"
            case .thirdPartyRelay: return "Relay Provider"
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
