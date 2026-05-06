import Foundation

struct RelaySettingsDraft: Equatable {
    var providerID: String
    var name: String
    var baseURL: String
    var preferredAdapterID: String
    var balanceCredentialMode: RelayCredentialMode
    var tokenUsageEnabled: Bool
    var accountEnabled: Bool
    var authHeader: String
    var authScheme: String
    var userID: String
    var userIDHeader: String
    var endpointPath: String
    var remainingJSONPath: String
    var usedJSONPath: String
    var limitJSONPath: String
    var successJSONPath: String
    var unit: String
    var quotaDisplayMode: OfficialQuotaDisplayMode

    init(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String,
        balanceCredentialMode: RelayCredentialMode,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        self.providerID = providerID
        self.name = name
        self.baseURL = baseURL
        self.preferredAdapterID = preferredAdapterID
        self.balanceCredentialMode = balanceCredentialMode
        self.tokenUsageEnabled = tokenUsageEnabled
        self.accountEnabled = accountEnabled
        self.authHeader = authHeader
        self.authScheme = authScheme
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.endpointPath = endpointPath
        self.remainingJSONPath = remainingJSONPath
        self.usedJSONPath = usedJSONPath
        self.limitJSONPath = limitJSONPath
        self.successJSONPath = successJSONPath
        self.unit = unit
        self.quotaDisplayMode = quotaDisplayMode
    }

    init(provider: ProviderDescriptor, preferredAdapterID: String? = nil) {
        let selectedAdapterID = preferredAdapterID
            ?? provider.relayConfig?.adapterID
            ?? provider.relayManifest?.id
            ?? "generic-newapi"
        let manifest = RelayAdapterRegistry.shared.manifest(
            for: provider.baseURL ?? provider.relayConfig?.baseURL ?? "",
            preferredID: selectedAdapterID
        )
        let relayViewConfig = provider.relayViewConfig
        let account = relayViewConfig?.accountBalance

        self.init(
            providerID: provider.id,
            name: provider.name,
            baseURL: provider.baseURL ?? provider.relayConfig?.baseURL ?? "",
            preferredAdapterID: selectedAdapterID,
            balanceCredentialMode: provider.relayConfig?.balanceCredentialMode ?? .manualPreferred,
            tokenUsageEnabled: relayViewConfig?.tokenUsageEnabled ?? manifest.match.defaultTokenChannelEnabled,
            accountEnabled: account?.enabled ?? manifest.match.defaultBalanceChannelEnabled,
            authHeader: account?.authHeader ?? manifest.balanceRequest.authHeader ?? "Authorization",
            authScheme: account?.authScheme ?? manifest.balanceRequest.authScheme ?? "Bearer",
            userID: account?.userID ?? manifest.balanceRequest.userID ?? "",
            userIDHeader: account?.userIDHeader ?? manifest.balanceRequest.userIDHeader ?? "New-Api-User",
            endpointPath: account?.endpointPath ?? manifest.balanceRequest.path,
            remainingJSONPath: account?.remainingJSONPath ?? manifest.extract.remaining,
            usedJSONPath: account?.usedJSONPath ?? manifest.extract.used ?? "",
            limitJSONPath: account?.limitJSONPath ?? manifest.extract.limit ?? "",
            successJSONPath: account?.successJSONPath ?? manifest.extract.success ?? "",
            unit: account?.unit ?? manifest.extract.unit ?? "quota",
            quotaDisplayMode: provider.relayConfig?.quotaDisplayMode ?? .remaining
        )
    }
}

struct OfficialSettingsDraft: Equatable {
    var providerID: String
    var sourceMode: OfficialSourceMode
    var webMode: OfficialWebMode
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var traeValueDisplayMode: OfficialTraeValueDisplayMode
    var credentialInput: String
    var secondaryCredentialInput: String

    init(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode,
        credentialInput: String = "",
        secondaryCredentialInput: String = ""
    ) {
        self.providerID = providerID
        self.sourceMode = sourceMode
        self.webMode = webMode
        self.quotaDisplayMode = quotaDisplayMode
        self.traeValueDisplayMode = traeValueDisplayMode
        self.credentialInput = credentialInput
        self.secondaryCredentialInput = secondaryCredentialInput
    }

    init(provider: ProviderDescriptor) {
        let defaults = ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        let config = provider.officialConfig ?? defaults
        let supportedSourceModes = provider.supportedOfficialSourceModes
        let supportedWebModes = provider.supportedOfficialWebModes
        let sourceMode = supportedSourceModes.contains(config.sourceMode)
            ? config.sourceMode
            : (supportedSourceModes.first ?? .auto)
        let webMode = supportedWebModes.contains(config.webMode)
            ? config.webMode
            : (supportedWebModes.first ?? .disabled)
        self.init(
            providerID: provider.id,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: config.quotaDisplayMode,
            traeValueDisplayMode: config.traeValueDisplayMode ?? defaults.traeValueDisplayMode ?? .percent
        )
    }
}
