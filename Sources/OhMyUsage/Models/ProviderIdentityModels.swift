import Foundation

enum ProviderFamily: String, Codable, CaseIterable {
    case official
    case thirdParty
}

enum ProviderType: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case gemini
    case copilot
    case microsoftCopilot
    case zai
    case amp
    case cursor
    case jetbrains
    case kiro
    case windsurf
    case trae
    case openrouterCredits
    case openrouterAPI
    case ollamaCloud
    case opencodeGo
    case relay
    case open
    case dragon
    case kimi
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
}

enum ResourceMode: String, CaseIterable, Identifiable, Codable {
    case background3Minutes = "background3m"
    case background5Minutes = "background5m"
    case background10Minutes = "background10m"
    case background15Minutes = "background15m"

    var id: String { rawValue }

    var intervalSeconds: Int {
        switch self {
        case .background3Minutes:
            return 3 * 60
        case .background5Minutes:
            return 5 * 60
        case .background10Minutes:
            return 10 * 60
        case .background15Minutes:
            return 15 * 60
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.background3Minutes.rawValue, "responsive":
            self = .background3Minutes
        case Self.background5Minutes.rawValue, "balanced":
            self = .background5Minutes
        case Self.background10Minutes.rawValue:
            self = .background10Minutes
        case Self.background15Minutes.rawValue, "lowPower":
            self = .background15Minutes
        default:
            self = .background5Minutes
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StatusBarDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case iconPercent
    case barNamePercent

    var id: String { rawValue }
}

enum StatusBarAppearanceMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case followWallpaper
    case dark
    case light

    var id: String { rawValue }
}
