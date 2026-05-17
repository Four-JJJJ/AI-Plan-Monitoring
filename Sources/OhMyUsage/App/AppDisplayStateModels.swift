import Foundation

enum UpdateDisplayTone: Equatable {
    case neutral
    case positive
    case negative
}

struct SettingsUpdateDisplayState: Equatable {
    enum Kind: Equatable {
        case idle
        case checkFailed
        case upToDate
        case updateAvailable(version: String)
        case downloading
        case installBuffering
        case failed
    }

    var kind: Kind
    var statusText: String?
    var tone: UpdateDisplayTone
    var retryTitle: String?
    var isRetryEnabled: Bool
}

struct MenuUpdateDisplayState: Equatable {
    enum Kind: Equatable {
        case idle
        case updateAvailable(version: String)
        case downloading
        case installBuffering
        case failed
    }

    var kind: Kind
    var statusText: String?
    var tone: UpdateDisplayTone
    var retryTitle: String?
    var isRetryEnabled: Bool
}

struct SettingsPersistenceDisplayState: Equatable {
    enum Kind: Equatable {
        case idle
        case saved
        case failed
    }

    var kind: Kind
    var statusText: String?
    var tone: UpdateDisplayTone
}
