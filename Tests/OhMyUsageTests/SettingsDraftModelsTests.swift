import XCTest
@testable import OhMyUsage

final class SettingsDraftModelsTests: XCTestCase {
    func testSettingsNavigationStateKeepsProviderSelectionInSync() {
        var state = SettingsNavigationState()

        state.selectTab(.customProviders)
        XCTAssertEqual(state.selectedSettingsTab, .customProviders)
        XCTAssertEqual(state.selectedGroup, .thirdParty)

        state.selectGroup(.official)
        XCTAssertEqual(state.selectedGroup, .official)
        XCTAssertEqual(state.selectedSettingsTab, .officialProviders)

        state.draggingProviderID = "relay.demo"
        state.reorderPreviewProviderIDs = ["relay.demo"]
        state.dropTargetProviderID = "relay.demo"
        state.dropTargetInsertAfter = true
        state.clearProviderReorderingState()

        XCTAssertNil(state.draggingProviderID)
        XCTAssertNil(state.reorderPreviewProviderIDs)
        XCTAssertNil(state.dropTargetProviderID)
        XCTAssertFalse(state.dropTargetInsertAfter)
    }

    func testSettingsDialogStateClearsProfileEditors() {
        var state = SettingsDialogState(
            codexProfilePendingDelete: nil,
            codexProfileEditor: CodexProfileEditorState(slotID: .a, title: "Codex A", isNewSlot: false),
            codexProfileEditorJSON: "{\"token\":\"demo\"}",
            codexProfileEditorNote: "work",
            claudeProfilePendingDelete: nil,
            claudeProfileEditor: ClaudeProfileEditorState(slotID: .b, title: "Claude B", isNewSlot: true),
            claudeProfileEditorSource: .manualCredentials,
            claudeProfileEditorConfigDir: "~/.claude-work",
            claudeProfileEditorJSON: "{\"email\":\"demo@example.com\"}",
            claudeProfileEditorNote: "personal",
            permissionPrompt: nil,
            permissionResultMessage: [:],
            permissionResultIsError: [:],
            isNewAPISiteDialogPresented: false
        )

        state.clearCodexProfileEditor()
        XCTAssertNil(state.codexProfileEditor)
        XCTAssertEqual(state.codexProfileEditorJSON, "")
        XCTAssertEqual(state.codexProfileEditorNote, "")

        state.clearClaudeProfileEditor()
        XCTAssertNil(state.claudeProfileEditor)
        XCTAssertEqual(state.claudeProfileEditorConfigDir, "")
        XCTAssertEqual(state.claudeProfileEditorJSON, "")
        XCTAssertEqual(state.claudeProfileEditorNote, "")
        XCTAssertEqual(state.claudeProfileEditorSource, .configDir)
    }

    func testSettingsProfileDraftStateClearHelpersRemoveStoredInputs() {
        var state = SettingsProfileDraftState(
            codexProfileJSONInputs: ["A": "{}"],
            codexProfileNoteInputs: ["A": "work"],
            codexProfileResult: ["A": "saved"],
            claudeProfileJSONInputs: ["B": "{}"],
            claudeProfileConfigDirInputs: ["B": "~/.claude"],
            claudeProfileNoteInputs: ["B": "personal"],
            claudeProfileResult: ["B": "saved"]
        )

        state.clearCodexState(forKey: "A")
        XCTAssertTrue(state.codexProfileJSONInputs.isEmpty)
        XCTAssertTrue(state.codexProfileNoteInputs.isEmpty)
        XCTAssertTrue(state.codexProfileResult.isEmpty)

        state.clearClaudeState(forKey: "B")
        XCTAssertTrue(state.claudeProfileJSONInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileConfigDirInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileNoteInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileResult.isEmpty)
    }

    func testNewRelaySiteDraftStateResetPreservesTemplateAndClearsTransientSelection() {
        var state = NewRelaySiteDraftState(
            providerName: "Demo",
            baseURL: "https://relay.example.com",
            templateID: "moonshot",
            selectedPresetID: "moonshot"
        )

        state.reset(using: "generic-newapi")

        XCTAssertEqual(state.providerName, "")
        XCTAssertEqual(state.baseURL, "")
        XCTAssertEqual(state.templateID, "generic-newapi")
        XCTAssertNil(state.selectedPresetID)
    }

    func testRelayDraftSeedsGenericNewAPIDefaults() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        let draft = RelaySettingsDraft(provider: provider)

        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.name, "Demo Relay")
        XCTAssertEqual(draft.baseURL, "https://relay.example.com")
        XCTAssertEqual(draft.preferredAdapterID, "generic-newapi")
        XCTAssertFalse(draft.tokenUsageEnabled)
        XCTAssertTrue(draft.accountEnabled)
        XCTAssertEqual(draft.authHeader, "Authorization")
        XCTAssertEqual(draft.authScheme, "Bearer")
        XCTAssertEqual(draft.userIDHeader, "New-Api-User")
        XCTAssertEqual(draft.endpointPath, "/api/user/self")
        XCTAssertEqual(draft.remainingJSONPath, "div(data.quota,50000)")
        XCTAssertEqual(draft.unit, "USD")
    }

    func testRelayProviderEditorDraftSeedsExistingProviderState() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        var state = RelayProviderEditorDraft()
        state.seed(from: provider)

        XCTAssertEqual(state.selectedRelayTemplateInputs[provider.id], "generic-newapi")
        XCTAssertEqual(state.providerNameInputs[provider.id], "Demo Relay")
        XCTAssertEqual(state.baseURLInputs[provider.id], "https://relay.example.com")
        XCTAssertEqual(state.relayCredentialModeInputs[provider.id], .manualPreferred)
        XCTAssertEqual(state.thirdPartyQuotaDisplayModeInputs[provider.id], .remaining)
    }

    func testOfficialDraftNormalizesUnsupportedModes() {
        var provider = ProviderDescriptor.defaultOfficialKiro()
        provider.officialConfig = OfficialProviderConfig(sourceMode: .web, webMode: .manual)

        let draft = OfficialSettingsDraft(provider: provider)

        XCTAssertEqual(draft.sourceMode, .auto)
        XCTAssertEqual(draft.webMode, .disabled)
        XCTAssertEqual(draft.quotaDisplayMode, .remaining)
    }

    func testOfficialProviderEditorDraftSeedsThresholdAndModes() {
        let provider = ProviderDescriptor.defaultOfficialCodex()

        var state = OfficialProviderEditorDraft()
        state.seed(from: provider)

        XCTAssertEqual(state.thresholdDraftValues[provider.id], provider.threshold.lowRemaining)
        XCTAssertEqual(state.officialThresholdInputs[provider.id], String(format: "%.2f", provider.threshold.lowRemaining))
        XCTAssertEqual(state.officialSourceModeInputs[provider.id], provider.officialConfig?.sourceMode ?? .auto)
        XCTAssertEqual(state.officialWebModeInputs[provider.id], provider.officialConfig?.webMode ?? .disabled)
    }
}
