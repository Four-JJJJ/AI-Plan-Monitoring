import Foundation

struct CodexIdentity: Equatable {
    let tenantKey: String
    let principalKey: String
    let identityKey: String

    static func from(payload: CodexParsedAuthPayload) -> CodexIdentity {
        let tenant = normalizedTenantKey(payload.tenantKey) ?? tenantKey(accountID: payload.accountId)
        let principal = principalKey(
            subject: payload.accountSubject,
            email: payload.accountEmail,
            fingerprint: payload.credentialFingerprint
        )
        let identity = normalizedIdentityKey(payload.identityKey)
            ?? identityKey(tenantKey: tenant, principalKey: principal)
        return CodexIdentity(tenantKey: tenant, principalKey: principal, identityKey: identity)
    }

    static func from(profile: CodexAccountProfile) -> CodexIdentity {
        let tenant = normalizedTenantKey(profile.tenantKey) ?? tenantKey(accountID: profile.accountId)
        let principal = principalKey(
            subject: profile.accountSubject,
            email: profile.accountEmail,
            fingerprint: profile.credentialFingerprint
        )
        let identity = normalizedIdentityKey(profile.identityKey)
            ?? identityKey(tenantKey: tenant, principalKey: principal)
        return CodexIdentity(tenantKey: tenant, principalKey: principal, identityKey: identity)
    }

    static func from(snapshot: UsageSnapshot) -> CodexIdentity {
        let tenant = normalizedTenantKey(snapshot.rawMeta["codex.tenantKey"])
            ?? tenantKey(accountID: teamID(from: snapshot.rawMeta))
        let principal = normalizedPrincipalKey(snapshot.rawMeta["codex.principalKey"])
            ?? principalKey(
                subject: snapshot.rawMeta["codex.subject"],
                email: snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"],
                fingerprint: snapshot.rawMeta["codex.credentialFingerprint"]
            )
        let identity = normalizedIdentityKey(snapshot.rawMeta["codex.identityKey"])
            ?? identityKey(tenantKey: tenant, principalKey: principal)
        return CodexIdentity(tenantKey: tenant, principalKey: principal, identityKey: identity)
    }

    static func teamID(from rawMeta: [String: String]) -> String? {
        trimmed(rawMeta["codex.teamId"]) ?? trimmed(rawMeta["codex.accountId"])
    }

    static func teamID(from snapshot: UsageSnapshot) -> String? {
        teamID(from: snapshot.rawMeta)
    }

    static func shortTeamID(_ raw: String, prefix: Int = 4, suffix: Int = 4) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return raw }
        let total = prefix + suffix
        guard value.count > total else { return value }
        let start = value.prefix(prefix)
        let end = value.suffix(suffix)
        return "\(start)…\(end)"
    }

    static func tenantKey(accountID: String?) -> String {
        if let accountID = normalizedAccountID(accountID) {
            return "account:\(accountID)"
        }
        return "default"
    }

    static func principalKey(subject: String?, email: String?, fingerprint: String?) -> String {
        if let subject = normalizedSubject(subject) {
            return "subject:\(subject)"
        }
        if let email = normalizedEmail(email) {
            return "email:\(email)"
        }
        if let fingerprint = normalizedFingerprint(fingerprint) {
            return "fingerprint:\(fingerprint)"
        }
        return "unknown"
    }

    static func identityKey(tenantKey: String, principalKey: String) -> String {
        if tenantKey == "default", principalKey == "unknown" {
            return "unknown"
        }
        return "tenant:\(tenantKey)|principal:\(principalKey)"
    }

    static func hasConflictingAccountID(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedAccountID(lhs),
              let rhs = normalizedAccountID(rhs) else {
            return false
        }
        return lhs != rhs
    }

    static func normalizedAccountID(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedSubject(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedEmail(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedFingerprint(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedTenantKey(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedPrincipalKey(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedIdentityKey(_ raw: String?) -> String? {
        normalizedLower(raw)
    }

    static func normalizedLower(_ raw: String?) -> String? {
        guard let value = trimmed(raw) else { return nil }
        return value.lowercased()
    }

    static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
