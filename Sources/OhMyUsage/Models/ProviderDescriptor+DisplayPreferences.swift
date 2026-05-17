import Foundation

extension ProviderDescriptor {
    var displaysUsedQuota: Bool {
        switch family {
        case .official:
            return (officialConfig?.quotaDisplayMode ?? ProviderDescriptor.defaultOfficialConfig(type: type).quotaDisplayMode) == .used
        case .thirdParty:
            return (relayConfig?.quotaDisplayMode ?? .remaining) == .used
        }
    }

    var traeDisplaysAmount: Bool {
        family == .official
            && type == .trae
            && (officialConfig?.traeValueDisplayMode
                ?? ProviderDescriptor.defaultOfficialConfig(type: .trae).traeValueDisplayMode
                ?? .percent) == .amount
    }

    var supportedOfficialSourceModes: [OfficialSourceMode] {
        ProviderMetadataCatalog.supportedOfficialSourceModes(for: self)
    }

    var supportedOfficialWebModes: [OfficialWebMode] {
        ProviderMetadataCatalog.supportedOfficialWebModes(for: self)
    }

    var supportsOfficialManualCookieInput: Bool {
        family == .official
            && !(officialConfig?.manualCookieAccount?.isEmpty ?? true)
            && supportedOfficialWebModes.contains(.manual)
    }
}
