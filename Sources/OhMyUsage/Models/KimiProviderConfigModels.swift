import Foundation

enum KimiAuthMode: String, Codable, CaseIterable {
    case manual
    case auto
}

enum KimiBrowserKind: String, Codable, CaseIterable, Identifiable {
    case arc
    case chrome
    case safari
    case edge
    case brave
    case chromium
    case firefox
    case opera
    case operaGX
    case vivaldi

    var id: String { rawValue }
}

struct KimiProviderConfig: Codable, Equatable {
    var authMode: KimiAuthMode
    var manualTokenAccount: String
    var autoCookieEnabled: Bool
    var browserOrder: [KimiBrowserKind]
}
