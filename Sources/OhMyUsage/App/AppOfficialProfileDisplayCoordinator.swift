import OhMyUsageDomain
import Foundation

struct ClaudeStatusBarDisplaySelectionOutcome: Equatable {
    var normalizedConfiguredSlotID: CodexSlotID?
    var resolvedDisplaySlotID: CodexSlotID?
    var previousResolvedDisplaySlotID: CodexSlotID?
    var shouldPersist: Bool
    var shouldNotify: Bool
}

enum ClaudeStatusBarDisplayPrefetchAction: Equatable {
    case none
    case notifyOnly
    case refresh(slotID: CodexSlotID)
}

@MainActor
final class AppOfficialProfileDisplayCoordinator {
    func updateClaudeStatusBarDisplaySelection(
        requestedSlotID: CodexSlotID?,
        configuredSlotID: CodexSlotID?,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot]
    ) -> ClaudeStatusBarDisplaySelectionOutcome {
        let normalizedRequestedSlotID = AppOfficialProfileStateCoordinator
            .normalizedClaudeStatusBarDisplaySlotID(
                requestedSlotID,
                profiles: profiles
            )
        let previousResolvedSlotID = AppOfficialProfileStateCoordinator
            .resolveClaudeStatusBarDisplaySlotID(
                configuredSlotID: configuredSlotID,
                profiles: profiles,
                slots: slots
            )
        let resolvedDisplaySlotID = AppOfficialProfileStateCoordinator
            .resolveClaudeStatusBarDisplaySlotID(
                configuredSlotID: normalizedRequestedSlotID,
                profiles: profiles,
                slots: slots
            )

        return ClaudeStatusBarDisplaySelectionOutcome(
            normalizedConfiguredSlotID: normalizedRequestedSlotID,
            resolvedDisplaySlotID: resolvedDisplaySlotID,
            previousResolvedDisplaySlotID: previousResolvedSlotID,
            shouldPersist: configuredSlotID != normalizedRequestedSlotID,
            shouldNotify: previousResolvedSlotID != resolvedDisplaySlotID
                || configuredSlotID != normalizedRequestedSlotID
        )
    }

    func claudeStatusBarDisplayPrefetchAction(
        slotID: CodexSlotID?,
        descriptor: ProviderDescriptor?,
        profiles: [ClaudeAccountProfile]
    ) -> ClaudeStatusBarDisplayPrefetchAction {
        guard let slotID,
              descriptor?.type == .claude,
              descriptor?.family == .official,
              let profile = profiles.first(where: { $0.slotID == slotID }),
              AppOfficialProfileStateCoordinator.canDisplayClaudeMonitoringProfile(profile) else {
            return .none
        }
        if profile.isCurrentSystemAccount {
            return .notifyOnly
        }
        return .refresh(slotID: slotID)
    }

    func claudeStatusBarDisplaySnapshot(
        resolvedSlotID: CodexSlotID?,
        slotViewModels: [ClaudeSlotViewModel],
        providerSnapshot: UsageSnapshot?
    ) -> UsageSnapshot? {
        if let resolvedSlotID,
           let slot = slotViewModels.first(where: { $0.slotID == resolvedSlotID }) {
            return slot.snapshot
        }
        return providerSnapshot
    }
}
