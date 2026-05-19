import Foundation

public struct ProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var family: ProviderFamily
    public var type: ProviderType
    public var settings: ProviderSettings

    public init(
        id: String,
        name: String,
        family: ProviderFamily,
        type: ProviderType,
        settings: ProviderSettings
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.type = type
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case family
        case type
        case enabled
        case pollIntervalSec
        case threshold
        case auth
        case showInMenuBar
        case baseURL
        case officialConfig
        case relayConfig
        case openConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.family = try container.decode(ProviderFamily.self, forKey: .family)
        self.type = try container.decode(ProviderType.self, forKey: .type)
        self.settings = ProviderSettings(
            enabled: try container.decode(Bool.self, forKey: .enabled),
            pollIntervalSec: try container.decode(Int.self, forKey: .pollIntervalSec),
            threshold: try container.decode(AlertRule.self, forKey: .threshold),
            auth: try container.decode(AuthConfig.self, forKey: .auth),
            showInMenuBar: try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar),
            baseURL: try container.decodeIfPresent(String.self, forKey: .baseURL),
            officialConfig: try container.decodeIfPresent(OfficialProviderConfig.self, forKey: .officialConfig),
            relayConfig: try container.decodeIfPresent(RelayProviderConfig.self, forKey: .relayConfig),
            openConfig: try container.decodeIfPresent(OpenProviderConfig.self, forKey: .openConfig)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(family, forKey: .family)
        try container.encode(type, forKey: .type)
        try container.encode(settings.enabled, forKey: .enabled)
        try container.encode(settings.pollIntervalSec, forKey: .pollIntervalSec)
        try container.encode(settings.threshold, forKey: .threshold)
        try container.encode(settings.auth, forKey: .auth)
        try container.encodeIfPresent(settings.showInMenuBar, forKey: .showInMenuBar)
        try container.encodeIfPresent(settings.baseURL, forKey: .baseURL)
        try container.encodeIfPresent(settings.officialConfig, forKey: .officialConfig)
        try container.encodeIfPresent(settings.relayConfig, forKey: .relayConfig)
        try container.encodeIfPresent(settings.openConfig, forKey: .openConfig)
    }
}

public struct ProviderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var pollIntervalSec: Int
    public var threshold: AlertRule
    public var auth: AuthConfig
    public var showInMenuBar: Bool?
    public var baseURL: String?
    public var officialConfig: OfficialProviderConfig?
    public var relayConfig: RelayProviderConfig?
    public var openConfig: OpenProviderConfig?

    public init(
        enabled: Bool,
        pollIntervalSec: Int,
        threshold: AlertRule,
        auth: AuthConfig,
        showInMenuBar: Bool? = nil,
        baseURL: String? = nil,
        officialConfig: OfficialProviderConfig? = nil,
        relayConfig: RelayProviderConfig? = nil,
        openConfig: OpenProviderConfig? = nil
    ) {
        self.enabled = enabled
        self.pollIntervalSec = pollIntervalSec
        self.threshold = threshold
        self.auth = auth
        self.showInMenuBar = showInMenuBar
        self.baseURL = baseURL
        self.officialConfig = officialConfig
        self.relayConfig = relayConfig
        self.openConfig = openConfig
    }
}
