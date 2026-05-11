import Foundation

struct OAuthImportSaveOutcome: Equatable {
    var slotID: CodexSlotID
    var detail: String
}

@MainActor
final class AppOfficialAccountImportCoordinator {
    typealias ImportAction = @MainActor (
        OAuthImportProvider,
        CodexSlotID,
        OAuthImportOrchestrator.StateHandler?
    ) async -> Result<OAuthImportResult, OAuthImportError>

    func startCodexImport(
        slotID: CodexSlotID,
        currentTask: Task<Void, Never>?,
        currentState: @escaping @MainActor () -> OAuthImportState?,
        importAccount: @escaping ImportAction,
        matchingProfile: @escaping (String) -> CodexAccountProfile?,
        saveImportedProfile: @escaping @MainActor (
            OAuthImportResult,
            CodexSlotID,
            CodexAccountProfile?
        ) -> OAuthImportSaveOutcome,
        setState: @escaping @MainActor (OAuthImportState?) -> Void,
        clearTask: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard currentTask == nil else { return nil }

        return Task { @MainActor in
            let result = await importAccount(.codex, slotID) { state in
                setState(state)
            }

            switch result {
            case .success(let imported):
                let saveOutcome = saveImportedProfile(
                    imported,
                    slotID,
                    matchingProfile(imported.rawCredentialJSON)
                )
                setState(
                    succeededState(
                        provider: imported.provider,
                        slotID: saveOutcome.slotID,
                        mode: imported.mode,
                        detail: saveOutcome.detail,
                        startedAt: currentState()?.startedAt ?? Date()
                    )
                )
            case .failure(let error):
                setState(
                    failedState(
                        provider: .codex,
                        slotID: slotID,
                        currentState: currentState(),
                        error: error
                    )
                )
            }

            clearTask()
        }
    }

    func startClaudeImport(
        slotID: CodexSlotID,
        currentTask: Task<Void, Never>?,
        currentState: @escaping @MainActor () -> OAuthImportState?,
        importAccount: @escaping ImportAction,
        matchingProfile: @escaping (String) -> ClaudeAccountProfile?,
        saveImportedProfile: @escaping @MainActor (
            OAuthImportResult,
            CodexSlotID,
            ClaudeAccountProfile?
        ) -> OAuthImportSaveOutcome,
        setState: @escaping @MainActor (OAuthImportState?) -> Void,
        clearTask: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard currentTask == nil else { return nil }

        return Task { @MainActor in
            let result = await importAccount(.claude, slotID) { state in
                setState(state)
            }

            switch result {
            case .success(let imported):
                let saveOutcome = saveImportedProfile(
                    imported,
                    slotID,
                    matchingProfile(imported.rawCredentialJSON)
                )
                setState(
                    succeededState(
                        provider: imported.provider,
                        slotID: saveOutcome.slotID,
                        mode: imported.mode,
                        detail: saveOutcome.detail,
                        startedAt: currentState()?.startedAt ?? Date()
                    )
                )
            case .failure(let error):
                setState(
                    failedState(
                        provider: .claude,
                        slotID: slotID,
                        currentState: currentState(),
                        error: error
                    )
                )
            }

            clearTask()
        }
    }

    private func succeededState(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        mode: OAuthImportMode,
        detail: String,
        startedAt: Date
    ) -> OAuthImportState {
        OAuthImportState(
            provider: provider,
            slotID: slotID,
            mode: mode,
            phase: .succeeded,
            detail: detail,
            startedAt: startedAt,
            updatedAt: Date()
        )
    }

    private func failedState(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        currentState: OAuthImportState?,
        error: OAuthImportError
    ) -> OAuthImportState {
        OAuthImportState(
            provider: provider,
            slotID: slotID,
            mode: currentState?.mode ?? .browserCallback,
            phase: error == .cancelled ? .cancelled : .failed,
            detail: error.localizedDescription,
            startedAt: currentState?.startedAt ?? Date(),
            updatedAt: Date()
        )
    }
}
