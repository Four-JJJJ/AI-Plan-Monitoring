import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

enum OfficialProfileRefreshExecutionResult {
    case success
    case failed
    case skipped
}

struct OfficialInactiveRefreshOutcome<SlotID: Hashable & Sendable> {
    var cursor: Int
    var lastAttemptAt: Date?
    var retryState: InactiveProfileRefreshRetryState<SlotID>
}

@MainActor
final class AppOfficialProfileRefreshCoordinator {
    func refreshCodexProfileSlot(
        profile: CodexAccountProfile,
        descriptor: ProviderDescriptor,
        runtime: CodexOfficialProfileRefreshRuntime,
        allowSessionWindowStabilization: Bool = true,
        fetchSnapshot: @escaping @MainActor (
            CodexAccountProfile,
            ProviderDescriptor
        ) async throws -> CodexProfileSnapshotResult,
        persistRefreshedAuthJSON: @escaping @MainActor (CodexSlotID, String) -> Void,
        syncProfiles: @escaping @MainActor () -> Void,
        transformSnapshot: @escaping @MainActor (UsageSnapshot, CodexSlotID) -> UsageSnapshot,
        commitInactiveSnapshot: @escaping @MainActor (UsageSnapshot, CodexSlotID, Bool) -> Void
    ) async -> OfficialProfileRefreshExecutionResult {
        guard runtime.beginRefreshing(slotID: profile.slotID) else {
            return .skipped
        }
        defer { runtime.finishRefreshing(slotID: profile.slotID) }

        guard let result = try? await fetchSnapshot(profile, descriptor) else {
            return .failed
        }

        if let refreshedAuthJSON = result.refreshedAuthJSON, !refreshedAuthJSON.isEmpty {
            persistRefreshedAuthJSON(profile.slotID, refreshedAuthJSON)
            syncProfiles()
        }

        let snapshot = transformSnapshot(result.snapshot, profile.slotID)
        commitInactiveSnapshot(snapshot, profile.slotID, allowSessionWindowStabilization)
        return .success
    }

    func refreshClaudeProfileSlot(
        profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor,
        runtime: ClaudeOfficialProfileRefreshRuntime,
        shouldRefreshProfile: @escaping @MainActor (ClaudeAccountProfile) -> Bool,
        fetchSnapshot: @escaping @MainActor (
            ClaudeAccountProfile,
            ProviderDescriptor
        ) async throws -> ClaudeProfileSnapshotResult,
        persistRefreshedCredentialsJSON: @escaping @MainActor (CodexSlotID, String) -> Void,
        syncProfiles: @escaping @MainActor () -> Void,
        transformSnapshot: @escaping @MainActor (UsageSnapshot, CodexSlotID) -> UsageSnapshot,
        commitInactiveSnapshot: @escaping @MainActor (UsageSnapshot, CodexSlotID) -> Void
    ) async -> OfficialProfileRefreshExecutionResult {
        guard shouldRefreshProfile(profile) else {
            return .skipped
        }
        guard runtime.beginRefreshing(slotID: profile.slotID) else {
            return .skipped
        }
        defer { runtime.finishRefreshing(slotID: profile.slotID) }

        guard let result = try? await fetchSnapshot(profile, descriptor) else {
            return .failed
        }

        if let refreshedCredentialsJSON = result.refreshedCredentialsJSON,
           !refreshedCredentialsJSON.isEmpty {
            persistRefreshedCredentialsJSON(profile.slotID, refreshedCredentialsJSON)
            syncProfiles()
        }

        let snapshot = transformSnapshot(result.snapshot, profile.slotID)
        commitInactiveSnapshot(snapshot, profile.slotID)
        return .success
    }

    func refreshCodexInactiveProfileCardInBackground(
        descriptor: ProviderDescriptor,
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        inFlightSlotIDs: Set<CodexSlotID>,
        retryState: InactiveProfileRefreshRetryState<CodexSlotID>,
        cursor: Int,
        lastAttemptAt: Date?,
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async -> OfficialInactiveRefreshOutcome<CodexSlotID> {
        let orderedProfiles = profiles.sorted { $0.slotID < $1.slotID }
        let orderedSlotIDs = orderedProfiles.map(\.slotID)
        let visibleSlotIDs = Set(orderedSlotIDs)
        var updatedRetryState = retryState
        updatedRetryState.prune(keeping: visibleSlotIDs)
        guard !orderedSlotIDs.isEmpty else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let now = Date()
        guard InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
            lastAttemptAt: lastAttemptAt,
            minimumInterval: TimeInterval(descriptor.pollIntervalSec),
            now: now
        ) else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let activeSlotIDs = Set(slots.filter(\.isActive).map(\.slotID))
        guard let selection = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: orderedSlotIDs,
            activeSlotIDs: activeSlotIDs,
            inFlightSlotIDs: inFlightSlotIDs,
            retryNotBefore: updatedRetryState.retryNotBefore,
            cursor: cursor,
            now: now
        ),
        let profile = orderedProfiles.first(where: { $0.slotID == selection.slotID }) else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let result = await refreshProfile(profile)
        switch result {
        case .success:
            updatedRetryState.markSuccess(slotID: selection.slotID)
        case .failed:
            updatedRetryState.markFailure(
                slotID: selection.slotID,
                baseInterval: descriptor.pollIntervalSec,
                now: Date()
            )
        case .skipped:
            break
        }

        return OfficialInactiveRefreshOutcome(
            cursor: selection.nextCursor,
            lastAttemptAt: now,
            retryState: updatedRetryState
        )
    }

    func refreshClaudeInactiveProfileCardInBackground(
        descriptor: ProviderDescriptor,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        inFlightSlotIDs: Set<CodexSlotID>,
        retryState: InactiveProfileRefreshRetryState<CodexSlotID>,
        cursor: Int,
        lastAttemptAt: Date?,
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async -> OfficialInactiveRefreshOutcome<CodexSlotID> {
        let orderedProfiles = profiles.sorted { $0.slotID < $1.slotID }
        let orderedSlotIDs = orderedProfiles.map(\.slotID)
        let visibleSlotIDs = Set(orderedSlotIDs)
        var updatedRetryState = retryState
        updatedRetryState.prune(keeping: visibleSlotIDs)
        guard !orderedSlotIDs.isEmpty else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let now = Date()
        guard InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
            lastAttemptAt: lastAttemptAt,
            minimumInterval: TimeInterval(descriptor.pollIntervalSec),
            now: now
        ) else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let activeSlotIDs = Set(slots.filter(\.isActive).map(\.slotID))
        guard let selection = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: orderedSlotIDs,
            activeSlotIDs: activeSlotIDs,
            inFlightSlotIDs: inFlightSlotIDs,
            retryNotBefore: updatedRetryState.retryNotBefore,
            cursor: cursor,
            now: now
        ),
        let profile = orderedProfiles.first(where: { $0.slotID == selection.slotID }) else {
            return OfficialInactiveRefreshOutcome(
                cursor: cursor,
                lastAttemptAt: lastAttemptAt,
                retryState: updatedRetryState
            )
        }

        let result = await refreshProfile(profile)
        switch result {
        case .success:
            updatedRetryState.markSuccess(slotID: selection.slotID)
        case .failed:
            updatedRetryState.markFailure(
                slotID: selection.slotID,
                baseInterval: descriptor.pollIntervalSec,
                now: Date()
            )
        case .skipped:
            break
        }

        return OfficialInactiveRefreshOutcome(
            cursor: selection.nextCursor,
            lastAttemptAt: now,
            retryState: updatedRetryState
        )
    }

    func refreshCodexProfilesAfterManualRefresh(
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        let activeSlotIDs = Set(slots.filter(\.isActive).map(\.slotID))
        for profile in profiles.sorted(by: { $0.slotID < $1.slotID }) where !activeSlotIDs.contains(profile.slotID) {
            _ = await refreshProfile(profile)
        }
    }

    func refreshClaudeProfilesAfterManualRefresh(
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        let activeSlotIDs = Set(slots.filter(\.isActive).map(\.slotID))
        for profile in profiles.sorted(by: { $0.slotID < $1.slotID }) where !activeSlotIDs.contains(profile.slotID) {
            _ = await refreshProfile(profile)
        }
    }

    func codexPrefetchCandidates(
        descriptor: ProviderDescriptor?,
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        inFlightSlotIDs: Set<CodexSlotID>,
        attemptedIdentity: [CodexSlotID: String]
    ) -> [(profile: CodexAccountProfile, identityKey: String)] {
        guard let descriptor, descriptor.type == .codex, descriptor.family == .official else {
            return []
        }

        let existingSlotIDs = Set(slots.map(\.slotID))
        return profiles.compactMap { profile in
            guard !existingSlotIDs.contains(profile.slotID) else { return nil }
            guard !inFlightSlotIDs.contains(profile.slotID) else { return nil }
            let identityKey = CodexIdentity.from(profile: profile).identityKey
            guard attemptedIdentity[profile.slotID] != identityKey else { return nil }
            return (profile, identityKey)
        }
    }

    func claudePrefetchCandidates(
        descriptor: ProviderDescriptor?,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        inFlightSlotIDs: Set<CodexSlotID>,
        attemptedIdentity: [CodexSlotID: String]
    ) -> [(profile: ClaudeAccountProfile, identityKey: String)] {
        guard let descriptor, descriptor.type == .claude, descriptor.family == .official else {
            return []
        }
        guard !profiles.isEmpty else { return [] }

        let preferredActiveSlotID = profiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID
        let activeRuntimeSlotIDs = Set(slots.filter(\.isActive).map(\.slotID))
        let schedulingBudget = max(
            0,
            RuntimeDiagnosticsLimits.claudePrefetchMaxConcurrent - inFlightSlotIDs.count
        )
        let candidates = ClaudePrefetchPlanner.selectCandidates(
            profiles: profiles,
            preferredActiveSlotID: preferredActiveSlotID,
            activeRuntimeSlotIDs: activeRuntimeSlotIDs,
            inFlightSlots: inFlightSlotIDs,
            attemptedIdentity: attemptedIdentity,
            maxNewTasks: schedulingBudget
        )
        guard !candidates.isEmpty else { return [] }

        let profilesBySlotID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.slotID, $0) })
        return candidates.compactMap { candidate in
            guard let profile = profilesBySlotID[candidate.slotID] else { return nil }
            return (profile, candidate.identityKey)
        }
    }
}
