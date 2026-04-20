import Foundation

struct ClaudePrefetchCandidate: Equatable {
    var slotID: CodexSlotID
    var identityKey: String
}

enum ClaudePrefetchPlanner {
    static func selectCandidates(
        profiles: [ClaudeAccountProfile],
        preferredActiveSlotID: CodexSlotID?,
        activeRuntimeSlotIDs: Set<CodexSlotID>,
        inFlightSlots: Set<CodexSlotID>,
        attemptedIdentity: [CodexSlotID: String],
        maxNewTasks: Int
    ) -> [ClaudePrefetchCandidate] {
        let budget = max(0, maxNewTasks)
        guard budget > 0 else { return [] }

        let sortedProfiles = profiles.sorted { lhs, rhs in
            if lhs.lastImportedAt != rhs.lastImportedAt {
                return lhs.lastImportedAt > rhs.lastImportedAt
            }
            return lhs.slotID < rhs.slotID
        }

        var output: [ClaudePrefetchCandidate] = []
        output.reserveCapacity(min(sortedProfiles.count, budget))

        for profile in sortedProfiles {
            if isActive(
                profile: profile,
                preferredActiveSlotID: preferredActiveSlotID,
                activeRuntimeSlotIDs: activeRuntimeSlotIDs
            ) {
                continue
            }
            if inFlightSlots.contains(profile.slotID) {
                continue
            }
            let identity = identityKey(for: profile)
            if attemptedIdentity[profile.slotID] == identity {
                continue
            }
            output.append(
                ClaudePrefetchCandidate(
                    slotID: profile.slotID,
                    identityKey: identity
                )
            )
            if output.count >= budget {
                break
            }
        }

        return output
    }

    static func identityKey(for profile: ClaudeAccountProfile) -> String {
        if let accountID = normalizedLowercasedToken(profile.accountId) {
            return "account:\(accountID)"
        }
        if let email = normalizedLowercasedToken(profile.accountEmail) {
            let configDir = normalizedConfigDirectoryToken(profile.configDir) ?? "default"
            return "email:\(email)|config:\(configDir)"
        }
        if let fingerprint = normalizedLowercasedToken(profile.credentialFingerprint) {
            return "fingerprint:\(fingerprint)"
        }
        return "slot:\(profile.slotID.rawValue.lowercased())"
    }

    private static func isActive(
        profile: ClaudeAccountProfile,
        preferredActiveSlotID: CodexSlotID?,
        activeRuntimeSlotIDs: Set<CodexSlotID>
    ) -> Bool {
        if let preferredActiveSlotID {
            return profile.slotID == preferredActiveSlotID
        }
        return activeRuntimeSlotIDs.contains(profile.slotID)
    }

    private static func normalizedLowercasedToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func normalizedConfigDirectoryToken(_ raw: String?) -> String? {
        guard let normalized = normalizedLowercasedToken(raw) else {
            return nil
        }
        return URL(fileURLWithPath: (normalized as NSString).expandingTildeInPath)
            .standardizedFileURL.path
            .lowercased()
    }
}
