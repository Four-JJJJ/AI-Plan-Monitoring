import OhMyUsageDomain
import Foundation

struct ClaudeProfileSyncEvaluation {
    var normalizedConfiguredDisplaySlotID: CodexSlotID?
    var resolvedDisplaySlotID: CodexSlotID?
    var didProfileIdentityChange: Bool
}

enum AppOfficialProfileStateCoordinator {
    static func hasPersistedOfficialMonitoringState(
        codexProfiles: [CodexAccountProfile],
        codexSlots: [CodexAccountSlot],
        claudeProfiles: [ClaudeAccountProfile],
        claudeSlots: [ClaudeAccountSlot]
    ) -> Bool {
        !codexProfiles.isEmpty
            || !claudeProfiles.isEmpty
            || !codexSlots.isEmpty
            || !claudeSlots.isEmpty
    }

    static func restorePersistedOfficialProvidersIfNeeded(
        config: inout AppConfig,
        codexProfiles: [CodexAccountProfile],
        codexSlots: [CodexAccountSlot],
        claudeProfiles: [ClaudeAccountProfile],
        claudeSlots: [ClaudeAccountSlot]
    ) -> Bool {
        guard !config.providers.contains(where: \.enabled) else { return false }

        let hasCodexState = !codexProfiles.isEmpty || !codexSlots.isEmpty
        let hasClaudeState = !claudeProfiles.isEmpty || !claudeSlots.isEmpty
        var changed = false

        if hasCodexState,
           let index = config.providers.firstIndex(where: { $0.type == .codex && $0.family == .official }),
           !config.providers[index].enabled {
            config.providers[index].enabled = true
            changed = true
        }

        if hasClaudeState,
           let index = config.providers.firstIndex(where: { $0.type == .claude && $0.family == .official }),
           !config.providers[index].enabled {
            config.providers[index].enabled = true
            changed = true
        }

        return changed
    }

    static func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true,
        profiles: [CodexAccountProfile]
    ) -> UsageSnapshot {
        var copy = snapshot
        if let teamID = CodexIdentity.teamID(from: copy) {
            copy.rawMeta["codex.accountId"] = teamID
            copy.rawMeta["codex.teamId"] = teamID
        }
        let identity = CodexIdentity.from(snapshot: copy)
        let resolvedSlotID = preferredSlotID ?? matchedCodexProfile(for: copy, profiles: profiles)?.slotID
        let accountKey = CodexAccountSlotStore.accountKey(from: copy)
        let label = CodexAccountSlotStore.accountLabel(from: copy)
        if let resolvedSlotID {
            copy.rawMeta["codex.slotID"] = resolvedSlotID.rawValue
        }
        copy.rawMeta["codex.tenantKey"] = identity.tenantKey
        copy.rawMeta["codex.principalKey"] = identity.principalKey
        copy.rawMeta["codex.identityKey"] = identity.identityKey
        copy.rawMeta["codex.accountKey"] = accountKey
        copy.rawMeta["codex.accountLabel"] = label
        copy.rawMeta["codex.lastSeenAt"] = ISO8601DateFormatter().string(from: Date())
        copy.rawMeta["codex.isActive"] = isActive ? "true" : "false"
        if copy.accountLabel == nil || copy.accountLabel?.isEmpty == true {
            copy.accountLabel = label == "Unknown" ? nil : label
        }
        return copy
    }

    static func mergedCodexSlotsForMenu(
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot]
    ) -> [CodexAccountSlot] {
        let profileSlotIDs = Set(profiles.map(\.slotID))
        let visibleRuntimeSlots = slots.filter { $0.isActive || profileSlotIDs.contains($0.slotID) }
        var mergedBySlotID = Dictionary(uniqueKeysWithValues: visibleRuntimeSlots.map { ($0.slotID, $0) })

        for profile in profiles where mergedBySlotID[profile.slotID] == nil {
            mergedBySlotID[profile.slotID] = placeholderCodexSlot(for: profile)
        }

        let preferredActiveSlotID = preferredCurrentSlotID(
            profiles: profiles,
            isCurrentSystemAccount: \.isCurrentSystemAccount,
            importedAt: \.lastImportedAt,
            slotID: \.slotID
        )

        var merged = mergedBySlotID.values.map { slot -> CodexAccountSlot in
            var updated = slot
            if let preferredActiveSlotID {
                updated.isActive = updated.slotID == preferredActiveSlotID
            }
            return updated
        }

        if preferredActiveSlotID == nil {
            let activeSlots = merged.filter(\.isActive)
            if activeSlots.count > 1 {
                let keep = activeSlots
                    .sorted { lhs, rhs in
                        if lhs.lastSeenAt != rhs.lastSeenAt {
                            return lhs.lastSeenAt > rhs.lastSeenAt
                        }
                        return lhs.slotID < rhs.slotID
                    }
                    .first?.slotID
                merged = merged.map { slot in
                    var updated = slot
                    updated.isActive = updated.slotID == keep
                    return updated
                }
            }
        }

        return merged
    }

    static func placeholderCodexSlot(for profile: CodexAccountProfile) -> CodexAccountSlot {
        let identity = CodexIdentity.from(profile: profile)
        return CodexAccountSlot(
            slotID: profile.slotID,
            accountKey: identity.identityKey,
            displayName: profile.displayName,
            lastSnapshot: placeholderCodexSnapshot(for: profile),
            lastSeenAt: profile.lastImportedAt,
            isActive: profile.isCurrentSystemAccount
        )
    }

    static func placeholderCodexSnapshot(for profile: CodexAccountProfile) -> UsageSnapshot {
        let identity = CodexIdentity.from(profile: profile)
        var rawMeta: [String: String] = [
            "codex.slotID": profile.slotID.rawValue,
            "codex.menuPlaceholder": "true",
            "codex.tenantKey": identity.tenantKey,
            "codex.principalKey": identity.principalKey,
            "codex.identityKey": identity.identityKey
        ]
        if let accountId = profile.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            rawMeta["codex.accountId"] = accountId
            rawMeta["codex.teamId"] = accountId
        }
        if let subject = profile.accountSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            rawMeta["codex.subject"] = subject
        }
        if let fingerprint = profile.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty {
            rawMeta["codex.credentialFingerprint"] = fingerprint
        }

        return UsageSnapshot(
            source: "codex-placeholder-\(profile.slotID.rawValue.lowercased())",
            status: .disabled,
            fetchHealth: .ok,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: profile.lastImportedAt,
            note: "",
            quotaWindows: [],
            sourceLabel: "Codex",
            accountLabel: profile.accountEmail,
            authSourceLabel: nil,
            diagnosticCode: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    static func canDisplayClaudeMonitoringProfile(_ profile: ClaudeAccountProfile) -> Bool {
        ClaudeAccountProfileStore.supportsQuotaMonitoring(profile: profile)
    }

    static func displayableClaudeProfiles(
        _ profiles: [ClaudeAccountProfile]
    ) -> [ClaudeAccountProfile] {
        profiles
            .filter(canDisplayClaudeMonitoringProfile(_:))
            .sorted { $0.slotID < $1.slotID }
    }

    static func visibleClaudeMonitoringSlotIDs(profiles: [ClaudeAccountProfile]) -> Set<CodexSlotID> {
        Set(
            profiles
                .filter(canDisplayClaudeMonitoringProfile(_:))
                .map(\.slotID)
        )
    }

    static func normalizedClaudeStatusBarDisplaySlotID(
        _ slotID: CodexSlotID?,
        profiles: [ClaudeAccountProfile]
    ) -> CodexSlotID? {
        guard let slotID else { return nil }
        let visibleSlotIDs = visibleClaudeMonitoringSlotIDs(profiles: profiles)
        guard visibleSlotIDs.contains(slotID) else { return nil }
        return slotID
    }

    static func resolveClaudeStatusBarDisplaySlotID(
        configuredSlotID: CodexSlotID?,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot]
    ) -> CodexSlotID? {
        let monitorableProfiles = profiles.filter(canDisplayClaudeMonitoringProfile(_:))
        let monitorableSlotIDs = Set(monitorableProfiles.map(\.slotID))
        if let configuredSlotID, monitorableSlotIDs.contains(configuredSlotID) {
            return configuredSlotID
        }

        let currentProfiles = monitorableProfiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
        if let slotID = currentProfiles.first?.slotID {
            return slotID
        }

        let lastSeenBySlotID = Dictionary(uniqueKeysWithValues: slots.map { ($0.slotID, $0.lastSeenAt) })
        return monitorableProfiles
            .sorted { lhs, rhs in
                let leftSeenAt = lastSeenBySlotID[lhs.slotID] ?? lhs.lastImportedAt
                let rightSeenAt = lastSeenBySlotID[rhs.slotID] ?? rhs.lastImportedAt
                if leftSeenAt != rightSeenAt {
                    return leftSeenAt > rightSeenAt
                }
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID
    }

    static func evaluateClaudeProfileSync(
        previousProfiles: [ClaudeAccountProfile],
        latestProfiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        configuredDisplaySlotID: CodexSlotID?
    ) -> ClaudeProfileSyncEvaluation {
        let visibleSlotIDs = visibleClaudeMonitoringSlotIDs(profiles: latestProfiles)
        let normalizedConfiguredDisplaySlotID: CodexSlotID?
        if let configuredDisplaySlotID, visibleSlotIDs.contains(configuredDisplaySlotID) {
            normalizedConfiguredDisplaySlotID = configuredDisplaySlotID
        } else {
            normalizedConfiguredDisplaySlotID = nil
        }

        return ClaudeProfileSyncEvaluation(
            normalizedConfiguredDisplaySlotID: normalizedConfiguredDisplaySlotID,
            resolvedDisplaySlotID: resolveClaudeStatusBarDisplaySlotID(
                configuredSlotID: normalizedConfiguredDisplaySlotID,
                profiles: latestProfiles,
                slots: slots
            ),
            didProfileIdentityChange: claudeProfileSetIdentity(previousProfiles) != claudeProfileSetIdentity(latestProfiles)
        )
    }

    static func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true,
        profiles: [ClaudeAccountProfile]
    ) -> UsageSnapshot {
        var copy = snapshot
        let fallbackProfile = profiles.first(where: { $0.isCurrentSystemAccount })
        let matchedProfile = matchedClaudeProfile(for: copy, profiles: profiles) ?? fallbackProfile

        if let accountId = matchedProfile?.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            copy.rawMeta["claude.accountId"] = accountId
        }
        if let fingerprint = matchedProfile?.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty,
           (copy.rawMeta["claude.credentialFingerprint"]?.isEmpty ?? true) {
            copy.rawMeta["claude.credentialFingerprint"] = fingerprint
        }
        if let configDir = matchedProfile?.configDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            copy.rawMeta["claude.configDir"] = configDir
        }
        if (copy.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let email = matchedProfile?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            copy.accountLabel = email
            copy.rawMeta["claude.accountLabel"] = email
        }

        let resolvedSlotID = preferredSlotID
            ?? matchedProfile?.slotID
            ?? preferredCurrentSlotID(
                profiles: profiles,
                isCurrentSystemAccount: \.isCurrentSystemAccount,
                importedAt: \.lastImportedAt,
                slotID: \.slotID
            )

        let accountKey = ClaudeAccountSlotStore.accountKey(from: copy)
        let label = ClaudeAccountSlotStore.accountLabel(from: copy)
        if let resolvedSlotID {
            copy.rawMeta["claude.slotID"] = resolvedSlotID.rawValue
        }
        copy.rawMeta["claude.accountKey"] = accountKey
        copy.rawMeta["claude.accountLabel"] = label
        copy.rawMeta["claude.lastSeenAt"] = ISO8601DateFormatter().string(from: Date())
        copy.rawMeta["claude.isActive"] = isActive ? "true" : "false"
        if copy.accountLabel == nil || copy.accountLabel?.isEmpty == true {
            copy.accountLabel = label == "Unknown" ? nil : label
        }
        return copy
    }

    static func claudeProfileSetIdentity(_ profiles: [ClaudeAccountProfile]) -> [String] {
        profiles
            .map { profile in
                "\(profile.slotID.rawValue)|\(ClaudePrefetchPlanner.identityKey(for: profile))"
            }
            .sorted()
    }

    static func mergedClaudeSlotsForMenu(
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot]
    ) -> [ClaudeAccountSlot] {
        let profileSlotIDs = Set(profiles.map(\.slotID))
        let visibleRuntimeSlots = slots.filter { $0.isActive || profileSlotIDs.contains($0.slotID) }
        var mergedBySlotID = Dictionary(uniqueKeysWithValues: visibleRuntimeSlots.map { ($0.slotID, $0) })

        for profile in profiles where mergedBySlotID[profile.slotID] == nil {
            mergedBySlotID[profile.slotID] = placeholderClaudeSlot(for: profile)
        }

        let preferredActiveSlotID = preferredCurrentSlotID(
            profiles: profiles,
            isCurrentSystemAccount: \.isCurrentSystemAccount,
            importedAt: \.lastImportedAt,
            slotID: \.slotID
        )

        var merged = mergedBySlotID.values.map { slot -> ClaudeAccountSlot in
            var updated = slot
            if let preferredActiveSlotID {
                updated.isActive = updated.slotID == preferredActiveSlotID
            }
            return updated
        }

        if preferredActiveSlotID == nil {
            let activeSlots = merged.filter(\.isActive)
            if activeSlots.count > 1 {
                let keep = activeSlots
                    .sorted { lhs, rhs in
                        if lhs.lastSeenAt != rhs.lastSeenAt {
                            return lhs.lastSeenAt > rhs.lastSeenAt
                        }
                        return lhs.slotID < rhs.slotID
                    }
                    .first?.slotID
                merged = merged.map { slot in
                    var updated = slot
                    updated.isActive = updated.slotID == keep
                    return updated
                }
            }
        }

        return merged
    }

    static func placeholderClaudeSlot(for profile: ClaudeAccountProfile) -> ClaudeAccountSlot {
        ClaudeAccountSlot(
            slotID: profile.slotID,
            accountKey: profile.credentialFingerprint
                .map { "fingerprint:\($0.lowercased())" }
                ?? profile.accountEmail
                .map { "email:\($0.lowercased())" }
                ?? "profile:\(profile.slotID.rawValue.lowercased())",
            displayName: profile.displayName,
            lastSnapshot: placeholderClaudeSnapshot(for: profile),
            lastSeenAt: profile.lastImportedAt,
            isActive: profile.isCurrentSystemAccount
        )
    }

    static func placeholderClaudeSnapshot(for profile: ClaudeAccountProfile) -> UsageSnapshot {
        var rawMeta: [String: String] = [
            "claude.slotID": profile.slotID.rawValue,
            "claude.menuPlaceholder": "true"
        ]
        if let accountId = profile.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            rawMeta["claude.accountId"] = accountId
        }
        if let fingerprint = profile.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty {
            rawMeta["claude.credentialFingerprint"] = fingerprint
        }
        if let configDir = profile.configDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            rawMeta["claude.configDir"] = configDir
        }

        return UsageSnapshot(
            source: "claude-placeholder-\(profile.slotID.rawValue.lowercased())",
            status: .disabled,
            fetchHealth: .ok,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: profile.lastImportedAt,
            note: "",
            quotaWindows: [],
            sourceLabel: "Claude",
            accountLabel: profile.accountEmail,
            authSourceLabel: nil,
            diagnosticCode: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    private static func matchedCodexProfile(
        for snapshot: UsageSnapshot,
        profiles: [CodexAccountProfile]
    ) -> CodexAccountProfile? {
        guard let index = CodexAccountProfileStore.matchingIndex(for: snapshot, in: profiles) else {
            return nil
        }
        return profiles[index]
    }

    private static func matchedClaudeProfile(
        for snapshot: UsageSnapshot,
        profiles: [ClaudeAccountProfile]
    ) -> ClaudeAccountProfile? {
        guard let index = ClaudeAccountProfileStore.matchingIndex(for: snapshot, in: profiles) else {
            return nil
        }
        return profiles[index]
    }

    private static func preferredCurrentSlotID<Profile>(
        profiles: [Profile],
        isCurrentSystemAccount: KeyPath<Profile, Bool>,
        importedAt: KeyPath<Profile, Date>,
        slotID: KeyPath<Profile, CodexSlotID>
    ) -> CodexSlotID? {
        profiles
            .filter { $0[keyPath: isCurrentSystemAccount] }
            .sorted { lhs, rhs in
                if lhs[keyPath: importedAt] != rhs[keyPath: importedAt] {
                    return lhs[keyPath: importedAt] > rhs[keyPath: importedAt]
                }
                return lhs[keyPath: slotID] < rhs[keyPath: slotID]
            }
            .first?[keyPath: slotID]
    }
}
