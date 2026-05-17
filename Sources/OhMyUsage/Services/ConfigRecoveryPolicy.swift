import Foundation

struct ConfigRecoveryPolicy {
    private enum PersistedOfficialState: CaseIterable {
        case codex
        case claude

        var providerID: String {
            switch self {
            case .codex:
                return "codex-official"
            case .claude:
                return "claude-official"
            }
        }
    }

    let directoryURL: URL
    let fileManager: FileManager

    func recoveredConfigFromPersistedOfficialState() -> AppConfig? {
        var recovered = AppConfig.default
        var restoredProviderIDs: [String] = []

        for state in PersistedOfficialState.allCases where hasPersistedState(for: state) {
            guard let index = recovered.providers.firstIndex(where: { $0.id == state.providerID }) else {
                continue
            }
            recovered.providers[index].enabled = true
            restoredProviderIDs.append(state.providerID)
        }

        guard !restoredProviderIDs.isEmpty else {
            return nil
        }

        return recovered.migratedWithSiteDefaults()
    }

    private func hasPersistedState(for state: PersistedOfficialState) -> Bool {
        switch state {
        case .codex:
            let profileStore = CodexAccountProfileStore(
                fileManager: fileManager,
                fileURL: directoryURL.appendingPathComponent("codex_profiles.json")
            )
            if !profileStore.profiles().isEmpty {
                return true
            }
            let slotStore = CodexAccountSlotStore(
                fileManager: fileManager,
                staleInterval: .greatestFiniteMagnitude,
                fileURL: directoryURL.appendingPathComponent("codex_slots.json")
            )
            return !slotStore.visibleSlots().isEmpty
        case .claude:
            let profileStore = ClaudeAccountProfileStore(
                fileManager: fileManager,
                fileURL: directoryURL.appendingPathComponent("claude_profiles.json")
            )
            if !profileStore.profiles().isEmpty {
                return true
            }
            let slotStore = ClaudeAccountSlotStore(
                fileManager: fileManager,
                staleInterval: .greatestFiniteMagnitude,
                fileURL: directoryURL.appendingPathComponent("claude_slots.json")
            )
            return !slotStore.visibleSlots().isEmpty
        }
    }
}
