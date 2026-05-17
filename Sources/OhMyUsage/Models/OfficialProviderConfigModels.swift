import Foundation

enum OfficialSourceMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case api
    case cli
    case web

    var id: String { rawValue }
}

enum OfficialWebMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case autoImport
    case manual

    var id: String { rawValue }
}

enum OfficialQuotaDisplayMode: String, Codable, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
}

enum OfficialTraeValueDisplayMode: String, Codable, CaseIterable, Identifiable {
    case percent
    case amount

    var id: String { rawValue }
}

struct OfficialProviderConfig: Codable, Equatable {
    var sourceMode: OfficialSourceMode
    var webMode: OfficialWebMode
    var manualCookieAccount: String?
    var oauthAccountImportEnabled: Bool?
    var autoDiscoveryEnabled: Bool
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var traeValueDisplayMode: OfficialTraeValueDisplayMode?
    var showPlanTypeInMenuBar: Bool

    init(
        sourceMode: OfficialSourceMode = .auto,
        webMode: OfficialWebMode = .disabled,
        manualCookieAccount: String? = nil,
        oauthAccountImportEnabled: Bool? = nil,
        autoDiscoveryEnabled: Bool = true,
        quotaDisplayMode: OfficialQuotaDisplayMode = .remaining,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil,
        showPlanTypeInMenuBar: Bool = true
    ) {
        self.sourceMode = sourceMode
        self.webMode = webMode
        self.manualCookieAccount = manualCookieAccount
        self.oauthAccountImportEnabled = oauthAccountImportEnabled
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.quotaDisplayMode = quotaDisplayMode
        self.traeValueDisplayMode = traeValueDisplayMode
        self.showPlanTypeInMenuBar = showPlanTypeInMenuBar
    }

    private enum CodingKeys: String, CodingKey {
        case sourceMode
        case webMode
        case manualCookieAccount
        case oauthAccountImportEnabled
        case autoDiscoveryEnabled
        case quotaDisplayMode
        case traeValueDisplayMode
        case showPlanTypeInMenuBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceMode = try container.decodeIfPresent(OfficialSourceMode.self, forKey: .sourceMode) ?? .auto
        self.webMode = try container.decodeIfPresent(OfficialWebMode.self, forKey: .webMode) ?? .disabled
        self.manualCookieAccount = try container.decodeIfPresent(String.self, forKey: .manualCookieAccount)
        self.oauthAccountImportEnabled = try container.decodeIfPresent(Bool.self, forKey: .oauthAccountImportEnabled)
        self.autoDiscoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoDiscoveryEnabled) ?? true
        self.quotaDisplayMode = try container.decodeIfPresent(OfficialQuotaDisplayMode.self, forKey: .quotaDisplayMode) ?? .remaining
        self.traeValueDisplayMode = try container.decodeIfPresent(OfficialTraeValueDisplayMode.self, forKey: .traeValueDisplayMode)
        self.showPlanTypeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showPlanTypeInMenuBar) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceMode, forKey: .sourceMode)
        try container.encode(webMode, forKey: .webMode)
        try container.encodeIfPresent(manualCookieAccount, forKey: .manualCookieAccount)
        try container.encodeIfPresent(oauthAccountImportEnabled, forKey: .oauthAccountImportEnabled)
        try container.encode(autoDiscoveryEnabled, forKey: .autoDiscoveryEnabled)
        try container.encode(quotaDisplayMode, forKey: .quotaDisplayMode)
        try container.encodeIfPresent(traeValueDisplayMode, forKey: .traeValueDisplayMode)
        try container.encode(showPlanTypeInMenuBar, forKey: .showPlanTypeInMenuBar)
    }
}
