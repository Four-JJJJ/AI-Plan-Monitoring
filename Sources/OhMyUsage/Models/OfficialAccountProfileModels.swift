import OhMyUsageDomain
import Foundation

struct CodexSlotViewModel: Identifiable, Equatable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var title: String
    var snapshot: UsageSnapshot
    var isActive: Bool
    var lastSeenAt: Date
    var displayName: String
    var note: String?
    var isSwitching: Bool = false
    var canSwitch: Bool = false
    var isCurrentSystemAccount: Bool = false
    var profileDisplayName: String?
    var switchMessage: String?
    var switchMessageIsError: Bool = false
}

struct CodexAccountProfile: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var displayName: String
    var note: String?
    var authJSON: String
    var accountId: String?
    var accountEmail: String?
    var accountSubject: String? = nil
    var tenantKey: String? = nil
    var identityKey: String? = nil
    var credentialFingerprint: String?
    var lastImportedAt: Date
    var isCurrentSystemAccount: Bool
}

struct CodexSwitchFeedback: Equatable {
    var message: String
    var isError: Bool
}

enum ClaudeProfileSource: String, Codable, CaseIterable, Identifiable {
    case configDir
    case manualCredentials

    var id: String { rawValue }
}

struct ClaudeSlotViewModel: Identifiable, Equatable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var title: String
    var snapshot: UsageSnapshot
    var isActive: Bool
    var lastSeenAt: Date
    var displayName: String
    var note: String?
    var source: ClaudeProfileSource?
    var isSwitching: Bool = false
    var canSwitch: Bool = false
    var isCurrentSystemAccount: Bool = false
    var profileDisplayName: String?
    var switchMessage: String?
    var switchMessageIsError: Bool = false
}

struct ClaudeAccountProfile: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var displayName: String
    var note: String?
    var source: ClaudeProfileSource
    var configDir: String?
    var credentialsJSON: String?
    var accountId: String?
    var accountEmail: String?
    var credentialFingerprint: String?
    var lastImportedAt: Date
    var isCurrentSystemAccount: Bool
}

struct ClaudeSwitchFeedback: Equatable {
    var message: String
    var isError: Bool
}
