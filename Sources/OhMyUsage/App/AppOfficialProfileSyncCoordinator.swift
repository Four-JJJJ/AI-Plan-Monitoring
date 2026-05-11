import Foundation

struct CodexProfileSyncResult {
    var profiles: [CodexAccountProfile]
    var visibleSlotIDs: Set<CodexSlotID>
}

struct ClaudeProfileBootstrapResult {
    var profiles: [ClaudeAccountProfile]
    var removedSlotIDs: [CodexSlotID]
    var didRunAutoCaptureCompaction: Bool
}

struct ClaudeProfileSyncResult {
    var profiles: [ClaudeAccountProfile]
    var visibleSlotIDs: Set<CodexSlotID>
    var syncEvaluation: ClaudeProfileSyncEvaluation
}

@MainActor
final class AppOfficialProfileSyncCoordinator {
    func syncCodexProfiles(
        profileStore: CodexAccountProfileStore,
        desktopAuthService: CodexDesktopAuthService
    ) -> CodexProfileSyncResult {
        let profiles = profileStore.captureCurrentAuthIfNeeded(
            authJSON: desktopAuthService.currentAuthJSON()
        )
        return CodexProfileSyncResult(
            profiles: profiles,
            visibleSlotIDs: Set(profiles.map(\.slotID))
        )
    }

    func bootstrapClaudeProfilesIfNeeded(
        currentProfiles: [ClaudeAccountProfile],
        didRunAutoCaptureCompaction: Bool,
        profileStore: ClaudeAccountProfileStore,
        desktopAuthService: ClaudeDesktopAuthService
    ) -> ClaudeProfileBootstrapResult {
        guard !didRunAutoCaptureCompaction else {
            return ClaudeProfileBootstrapResult(
                profiles: currentProfiles,
                removedSlotIDs: [],
                didRunAutoCaptureCompaction: true
            )
        }

        let compactionResult = profileStore.compactAutoCapturedProfiles(
            defaultConfigDir: desktopAuthService.currentSystemConfigDirectory(),
            currentFingerprint: desktopAuthService.currentCredentialFingerprint()
        )
        return ClaudeProfileBootstrapResult(
            profiles: compactionResult.profiles,
            removedSlotIDs: compactionResult.removedSlotIDs,
            didRunAutoCaptureCompaction: true
        )
    }

    func syncClaudeProfiles(
        currentProfiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        configuredDisplaySlotID: CodexSlotID?,
        profileStore: ClaudeAccountProfileStore,
        desktopAuthService: ClaudeDesktopAuthService
    ) -> ClaudeProfileSyncResult {
        let latestProfiles = profileStore.captureCurrentCredentialsIfNeeded(
            credentialsJSON: desktopAuthService.currentCredentialsJSON(),
            defaultConfigDir: desktopAuthService.currentSystemConfigDirectory()
        )
        let syncEvaluation = AppOfficialProfileStateCoordinator.evaluateClaudeProfileSync(
            previousProfiles: currentProfiles,
            latestProfiles: latestProfiles,
            slots: slots,
            configuredDisplaySlotID: configuredDisplaySlotID
        )
        return ClaudeProfileSyncResult(
            profiles: latestProfiles,
            visibleSlotIDs: Set(latestProfiles.map(\.slotID)),
            syncEvaluation: syncEvaluation
        )
    }
}
