import OhMyUsageApplication
import Foundation

@MainActor
final class CodexOfficialProfileRefreshRuntime {
    private let coordinator = AppOfficialProfileRefreshCoordinator()
    private var inFlightSlotIDs: Set<CodexSlotID> = []
    private var attemptedIdentity: [CodexSlotID: String] = [:]
    private var inactiveRefreshCursor = 0
    private var inactiveRefreshRetryState = InactiveProfileRefreshRetryState<CodexSlotID>()
    private var inactiveRefreshLastAttemptAtByProviderID: [String: Date] = [:]

    var attemptedIdentityCount: Int { attemptedIdentity.count }
    var inFlightCount: Int { inFlightSlotIDs.count }

    func beginRefreshing(slotID: CodexSlotID) -> Bool {
        guard !inFlightSlotIDs.contains(slotID) else { return false }
        inFlightSlotIDs.insert(slotID)
        return true
    }

    func finishRefreshing(slotID: CodexSlotID) {
        inFlightSlotIDs.remove(slotID)
    }

    func pruneRetryState(keeping slotIDs: Set<CodexSlotID>) {
        inactiveRefreshRetryState.prune(keeping: slotIDs)
    }

    func remove(slotID: CodexSlotID) {
        attemptedIdentity.removeValue(forKey: slotID)
        inFlightSlotIDs.remove(slotID)
        inactiveRefreshRetryState.remove(slotID: slotID)
    }

    func reset() {
        inFlightSlotIDs.removeAll()
        attemptedIdentity.removeAll()
        inactiveRefreshCursor = 0
        inactiveRefreshRetryState = InactiveProfileRefreshRetryState()
        inactiveRefreshLastAttemptAtByProviderID.removeAll()
    }

    func refreshInactiveProfileCardInBackgroundIfNeeded(
        descriptor: ProviderDescriptor,
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        let outcome = await coordinator.refreshCodexInactiveProfileCardInBackground(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            inFlightSlotIDs: inFlightSlotIDs,
            retryState: inactiveRefreshRetryState,
            cursor: inactiveRefreshCursor,
            lastAttemptAt: inactiveRefreshLastAttemptAtByProviderID[descriptor.id],
            refreshProfile: refreshProfile
        )
        inactiveRefreshCursor = outcome.cursor
        inactiveRefreshLastAttemptAtByProviderID[descriptor.id] = outcome.lastAttemptAt
        inactiveRefreshRetryState = outcome.retryState
    }

    func refreshProfilesAfterManualRefresh(
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        await coordinator.refreshCodexProfilesAfterManualRefresh(
            profiles: profiles,
            slots: slots
        ) { profile in
            await refreshProfile(profile)
        }
    }

    func schedulePrefetchIfNeeded(
        descriptor: ProviderDescriptor?,
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        refreshProfile: @escaping @MainActor (
            CodexAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) {
        guard let descriptor else { return }
        let candidates = coordinator.codexPrefetchCandidates(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            inFlightSlotIDs: inFlightSlotIDs,
            attemptedIdentity: attemptedIdentity
        )
        for candidate in candidates {
            attemptedIdentity[candidate.profile.slotID] = candidate.identityKey
            Task { @MainActor in
                _ = await refreshProfile(candidate.profile, descriptor)
            }
        }
    }
}

@MainActor
final class ClaudeOfficialProfileRefreshRuntime {
    private let coordinator = AppOfficialProfileRefreshCoordinator()
    private var inFlightSlotIDs: Set<CodexSlotID> = []
    private var attemptedIdentity: [CodexSlotID: String] = [:]
    private var inactiveRefreshCursor = 0
    private var inactiveRefreshRetryState = InactiveProfileRefreshRetryState<CodexSlotID>()
    private var inactiveRefreshLastAttemptAtByProviderID: [String: Date] = [:]

    var attemptedIdentityCount: Int { attemptedIdentity.count }
    var inFlightCount: Int { inFlightSlotIDs.count }

    func beginRefreshing(slotID: CodexSlotID) -> Bool {
        guard !inFlightSlotIDs.contains(slotID) else { return false }
        inFlightSlotIDs.insert(slotID)
        return true
    }

    func finishRefreshing(slotID: CodexSlotID) {
        inFlightSlotIDs.remove(slotID)
    }

    func pruneVisibleSlots(keeping slotIDs: Set<CodexSlotID>) {
        attemptedIdentity = attemptedIdentity.filter { slotIDs.contains($0.key) }
        inFlightSlotIDs = inFlightSlotIDs.intersection(slotIDs)
        inactiveRefreshRetryState.prune(keeping: slotIDs)
    }

    func remove(slotID: CodexSlotID) {
        attemptedIdentity.removeValue(forKey: slotID)
        inFlightSlotIDs.remove(slotID)
        inactiveRefreshRetryState.remove(slotID: slotID)
    }

    func reset() {
        inFlightSlotIDs.removeAll()
        attemptedIdentity.removeAll()
        inactiveRefreshCursor = 0
        inactiveRefreshRetryState = InactiveProfileRefreshRetryState()
        inactiveRefreshLastAttemptAtByProviderID.removeAll()
    }

    func refreshInactiveProfileCardInBackgroundIfNeeded(
        descriptor: ProviderDescriptor,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        let outcome = await coordinator.refreshClaudeInactiveProfileCardInBackground(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            inFlightSlotIDs: inFlightSlotIDs,
            retryState: inactiveRefreshRetryState,
            cursor: inactiveRefreshCursor,
            lastAttemptAt: inactiveRefreshLastAttemptAtByProviderID[descriptor.id],
            refreshProfile: refreshProfile
        )
        inactiveRefreshCursor = outcome.cursor
        inactiveRefreshLastAttemptAtByProviderID[descriptor.id] = outcome.lastAttemptAt
        inactiveRefreshRetryState = outcome.retryState
    }

    func refreshProfilesAfterManualRefresh(
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        await coordinator.refreshClaudeProfilesAfterManualRefresh(
            profiles: profiles,
            slots: slots
        ) { profile in
            await refreshProfile(profile)
        }
    }

    func schedulePrefetchIfNeeded(
        descriptor: ProviderDescriptor?,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        refreshProfile: @escaping @MainActor (
            ClaudeAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) {
        guard let descriptor else { return }
        let candidates = coordinator.claudePrefetchCandidates(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            inFlightSlotIDs: inFlightSlotIDs,
            attemptedIdentity: attemptedIdentity
        )
        for candidate in candidates {
            attemptedIdentity[candidate.profile.slotID] = candidate.identityKey
            Task { @MainActor in
                _ = await refreshProfile(candidate.profile, descriptor)
            }
        }
    }
}
