import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)? = nil

    @State private var tokenInputs: [String: String] = [:]
    @State private var systemTokenInputs: [String: String] = [:]

    @State private var providerNameInputs: [String: String] = [:]
    @State private var baseURLInputs: [String: String] = [:]
    @State private var tokenUsageEnabledInputs: [String: Bool] = [:]
    @State private var accountEnabledInputs: [String: Bool] = [:]
    @State private var authHeaderInputs: [String: String] = [:]
    @State private var authSchemeInputs: [String: String] = [:]
    @State private var userIDInputs: [String: String] = [:]
    @State private var userHeaderInputs: [String: String] = [:]
    @State private var endpointPathInputs: [String: String] = [:]
    @State private var remainingPathInputs: [String: String] = [:]
    @State private var usedPathInputs: [String: String] = [:]
    @State private var limitPathInputs: [String: String] = [:]
    @State private var successPathInputs: [String: String] = [:]
    @State private var unitInputs: [String: String] = [:]
    @State private var officialSourceModeInputs: [String: OfficialSourceMode] = [:]
    @State private var officialWebModeInputs: [String: OfficialWebMode] = [:]
    @State private var officialQuotaDisplayModeInputs: [String: OfficialQuotaDisplayMode] = [:]
    @State private var officialCookieInputs: [String: String] = [:]
    @State private var codexProfileJSONInputs: [String: String] = [:]
    @State private var codexProfileResult: [String: String] = [:]
    @State private var codexProfileExpanded: Set<String> = []
    @State private var codexProfilePendingDelete: CodexSlotID?
    @State private var permissionPrompt: PermissionPrompt?
    @State private var permissionResultMessage: [String: String] = [:]
    @State private var permissionResultIsError: [String: Bool] = [:]
    @State private var relayTestResult: [String: RelayDiagnosticResult] = [:]
    @State private var relayAdvancedExpanded: [String: Bool] = [:]
    @State private var selectedRelayTemplateInputs: [String: String] = [:]
    @State private var relayCredentialModeInputs: [String: RelayCredentialMode] = [:]

    @State private var newProviderName = ""
    @State private var newProviderBaseURL = "https://"
    @State private var newProviderTemplateID = "generic-newapi"
    @State private var selectedRelayPresetID: String?
    @State private var customNewAPIRelayExpanded = false
    @State private var selectedSettingsTab: SettingsTab = .general
    @State private var selectedGroup: ProviderGroup = .official
    @State private var selectedProviderID: String?
    private let panelBackground = Color(hex: 0x232325)
    private let cardBackground = Color.black
    private let outlineColor = Color.white.opacity(0.12)
    private let settingsTitleFont = Font.system(size: 16, weight: .semibold)
    private let settingsBodyFont = Font.system(size: 13, weight: .regular)
    private let settingsLabelFont = Font.system(size: 13, weight: .semibold)
    private let settingsHintFont = Font.system(size: 12, weight: .regular)
    private let settingsTitleColor = Color.white
    private let settingsBodyColor = Color.white.opacity(0.92)
    private let settingsHintColor = Color.white.opacity(0.62)

    private enum ProviderGroup: String, CaseIterable, Identifiable {
        case official
        case thirdParty

        var id: String { rawValue }
    }

    private struct RelayTemplatePreset: Identifiable {
        let manifest: RelayAdapterManifest
        let suggestedBaseURL: String?

        var id: String { manifest.id }
        var displayName: String { manifest.displayName }
    }

    private enum PermissionPrompt: Identifiable {
        case notifications
        case keychain
        case fullDisk
        case autoDiscovery
        case resetLocalData

        var id: String {
            switch self {
            case .notifications: return "notifications"
            case .keychain: return "keychain"
            case .fullDisk: return "fullDisk"
            case .autoDiscovery: return "autoDiscovery"
            case .resetLocalData: return "resetLocalData"
            }
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case models

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.text(.settingsTitle))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(viewModel.text(.done)) {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            settingsTabBar

            Group {
                if selectedSettingsTab == .general {
                    ScrollView {
                        topGeneralSection
                    }
                } else {
                    HStack(spacing: 12) {
                        sidebar
                            .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)

                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(outlineColor, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            seedInputsFromConfig()
            syncSelection()
            viewModel.refreshPermissionStatusesNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissionStatusesNow()
        }
        .onChange(of: viewModel.config.providers.map(\.id)) { _, _ in
            seedInputsFromConfig()
            syncSelection()
        }
        .onChange(of: selectedGroup) { _, _ in
            syncSelection()
        }
        .alert(
            viewModel.text(.codexDeleteProfileTitle),
            isPresented: Binding(
                get: { codexProfilePendingDelete != nil },
                set: { newValue in
                    if !newValue {
                        codexProfilePendingDelete = nil
                    }
                }
            ),
            presenting: codexProfilePendingDelete
        ) { slotID in
            Button(viewModel.text(.codexDeleteConfirm), role: .destructive) {
                let key = slotID.rawValue
                viewModel.removeCodexProfile(slotID: slotID)
                codexProfileJSONInputs.removeValue(forKey: key)
                codexProfileResult.removeValue(forKey: key)
                codexProfileExpanded.remove(key)
                codexProfilePendingDelete = nil
            }
            Button(viewModel.text(.done), role: .cancel) {
                codexProfilePendingDelete = nil
            }
        } message: { _ in
            Text(viewModel.text(.codexDeleteProfileMessage))
        }
        .confirmationDialog(
            permissionAlertTitle,
            isPresented: Binding(
                get: { permissionPrompt != nil },
                set: { newValue in
                    if !newValue {
                        permissionPrompt = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(viewModel.text(.permissionContinue)) {
                handlePermissionPrompt()
            }
            Button(viewModel.text(.permissionCancel), role: .cancel) {
                permissionPrompt = nil
            }
        } message: {
            Text(permissionAlertMessage)
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 10) {
            settingsTabButton(.general)
            settingsTabButton(.models)
            Spacer()
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedSettingsTab == tab

        return Button {
            selectedSettingsTab = tab
        } label: {
            Text(viewModel.text(tab == .general ? .settingsGeneralTab : .settingsModelsTab))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : outlineColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsActionButton(
        _ title: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(destructive ? Color(hex: 0xD83E3E) : nil)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(destructive ? Color(hex: 0xD83E3E) : nil)
        }
    }

    private func relayPresetProvider(for presetID: String) -> ProviderDescriptor? {
        viewModel.config.providers.first { provider in
            provider.family == .thirdParty && provider.relayConfig?.adapterID == presetID
        }
    }

    private func setRelayPresetEnabled(_ enabled: Bool, preset: RelayTemplatePreset) {
        if let provider = relayPresetProvider(for: preset.id) {
            viewModel.setEnabled(enabled, providerID: provider.id)
            selectedGroup = .thirdParty
            selectedProviderID = provider.id
            return
        }

        guard enabled else { return }

        let beforeIDs = Set(viewModel.config.providers.map(\.id))
        viewModel.addOpenRelay(
            name: preset.displayName,
            baseURL: preset.suggestedBaseURL ?? "https://",
            preferredAdapterID: preset.id
        )
        if let added = viewModel.config.providers.first(where: { !beforeIDs.contains($0.id) }) {
            selectedGroup = .thirdParty
            selectedProviderID = added.id
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $selectedGroup) {
                Text(viewModel.text(.officialTab)).tag(ProviderGroup.official)
                Text(viewModel.text(.thirdPartyTab)).tag(ProviderGroup.thirdParty)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if selectedGroup == .thirdParty {
                thirdPartySidebarContent
            } else {
                List {
                    if !enabledSidebarProviders.isEmpty {
                        Section {
                            ForEach(enabledSidebarProviders) { provider in
                                sidebarProviderRow(provider)
                            }
                            .onMove(perform: moveEnabledProviders)
                        }
                    }
                    if !disabledSidebarProviders.isEmpty {
                        Section {
                            ForEach(disabledSidebarProviders) { provider in
                                sidebarProviderRow(provider)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(cardBackground)
                .frame(minHeight: 220, maxHeight: .infinity)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private var thirdPartySidebarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(relayBuiltInPresets) { preset in
                    relayPresetSidebarRow(preset)
                }

                if !customRelayProviders.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    ForEach(customRelayProviders) { provider in
                        sidebarProviderRow(provider)
                    }
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                DisclosureGroup(
                    isExpanded: $customNewAPIRelayExpanded,
                    content: {
                        newAPICustomSection
                            .padding(.top, 6)
                    },
                    label: {
                        Text("NewAPI 自定义")
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsTitleColor)
                    }
                )
                .tint(.white)
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
    }

    private func sidebarProviderRow(_ provider: ProviderDescriptor) -> some View {
        let isSelected = selectedProviderID == provider.id

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { provider.enabled },
                set: { viewModel.setEnabled($0, providerID: provider.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            providerIcon(for: provider, size: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(sidebarDisplayName(for: provider))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(provider.enabled ? viewModel.text(.toggleOn) : viewModel.text(.toggleOff))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? settingsBodyColor : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.95) : outlineColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProviderID = provider.id
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedProvider {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    providerSettingsCard(selectedProvider)
                }
            }
        } else {
            VStack {
                Spacer()
                Text(viewModel.text(.selectProviderHint))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var topGeneralSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(viewModel.text(.language))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)
                Picker("", selection: Binding(
                    get: { viewModel.language },
                    set: { viewModel.setLanguage($0) }
                )) {
                    Text(viewModel.text(.chinese)).tag(AppLanguage.zhHans)
                    Text(viewModel.text(.english)).tag(AppLanguage.en)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Toggle(
                    viewModel.text(.launchAtLogin),
                    isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: { viewModel.setLaunchAtLoginEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .tint(.green)
                .font(settingsLabelFont)
            }

            Text(viewModel.text(.launchAtLoginHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

            permissionsSection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.white.opacity(0.08))

            Text(viewModel.text(.permissionsTitle))
                .font(settingsTitleFont)
                .foregroundStyle(settingsTitleColor)

            Text(viewModel.text(.permissionsHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow(alignment: .top) {
                    permissionStatusTile(
                        title: viewModel.text(.permissionNotificationsTitle),
                        hint: viewModel.text(.permissionNotificationsHint),
                        statusText: notificationPermissionStatusText,
                        statusColor: notificationPermissionStatusColor,
                        buttonTitle: viewModel.text(.permissionNotificationsAction),
                        resultMessage: permissionResultMessage[PermissionPrompt.notifications.id],
                        resultIsError: permissionResultIsError[PermissionPrompt.notifications.id] ?? false
                    ) {
                        permissionPrompt = .notifications
                    }

                    permissionStatusTile(
                        title: viewModel.text(.permissionKeychainTitle),
                        hint: viewModel.text(.permissionKeychainHint),
                        statusText: keychainPermissionStatusText,
                        statusColor: keychainPermissionStatusColor,
                        buttonTitle: viewModel.text(.permissionKeychainAction),
                        resultMessage: permissionResultMessage[PermissionPrompt.keychain.id],
                        resultIsError: permissionResultIsError[PermissionPrompt.keychain.id] ?? false
                    ) {
                        permissionPrompt = .keychain
                    }

                    permissionStatusTile(
                        title: viewModel.text(.permissionFullDiskTitle),
                        hint: viewModel.text(.permissionFullDiskHint),
                        statusText: fullDiskPermissionStatusText,
                        statusColor: fullDiskPermissionStatusColor,
                        buttonTitle: viewModel.text(.permissionFullDiskAction),
                        resultMessage: permissionResultMessage[PermissionPrompt.fullDisk.id],
                        resultIsError: permissionResultIsError[PermissionPrompt.fullDisk.id] ?? false
                    ) {
                        permissionPrompt = .fullDisk
                    }
                }
            }

            permissionActionRow(
                title: viewModel.text(.localDiscoveryTitle),
                hint: viewModel.text(.localDiscoveryHint),
                buttonTitle: viewModel.text(.localDiscoveryAction)
            ) {
                permissionPrompt = .autoDiscovery
            }

            permissionActionRow(
                title: viewModel.text(.resetLocalDataTitle),
                hint: viewModel.text(.resetLocalDataHint),
                buttonTitle: viewModel.text(.resetLocalDataAction),
                destructive: true
            ) {
                permissionPrompt = .resetLocalData
            }

            Text(viewModel.text(.permissionsPrivacyPromise))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

        }
    }

    private func permissionStatusTile(
        title: String,
        hint: String,
        statusText: String,
        statusColor: Color,
        buttonTitle: String,
        resultMessage: String?,
        resultIsError: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                Text(hint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(statusText)
                    .font(settingsLabelFont)
                    .foregroundStyle(statusColor)
                Spacer(minLength: 8)
                settingsActionButton(buttonTitle, action: action)
            }
            if let resultMessage, !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(settingsHintFont)
                    .foregroundStyle(resultIsError ? Color(hex: 0xD83E3E) : Color(hex: 0x51DB42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func permissionActionRow(
        title: String,
        hint: String,
        buttonTitle: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                Text(hint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if destructive {
                settingsActionButton(buttonTitle, prominent: true, destructive: true, action: action)
            } else {
                settingsActionButton(buttonTitle, action: action)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private var notificationPermissionStatusText: String {
        viewModel.hasNotificationPermission
            ? viewModel.text(.permissionStatusAuthorized)
            : viewModel.text(.permissionStatusPending)
    }

    private var notificationPermissionStatusColor: Color {
        viewModel.hasNotificationPermission ? Color(hex: 0x51DB42) : Color(hex: 0xD87E3E)
    }

    private var keychainPermissionStatusText: String {
        viewModel.secureStorageReady
            ? viewModel.text(.permissionStatusAuthorized)
            : viewModel.text(.permissionStatusPending)
    }

    private var keychainPermissionStatusColor: Color {
        viewModel.secureStorageReady ? Color(hex: 0x51DB42) : Color(hex: 0xD87E3E)
    }

    private var fullDiskPermissionStatusText: String {
        if viewModel.fullDiskAccessGranted {
            return viewModel.text(.permissionStatusAuthorized)
        }
        if viewModel.fullDiskAccessRelevant || viewModel.fullDiskAccessRequested {
            return viewModel.text(.permissionStatusNeedsAction)
        }
        return viewModel.text(.permissionStatusPending)
    }

    private var fullDiskPermissionStatusColor: Color {
        viewModel.fullDiskAccessGranted ? Color(hex: 0x51DB42) : Color(hex: 0xD87E3E)
    }

    private var newAPICustomSection: some View {
        let selectedPreset = relayBuiltInPresets.first(where: { $0.id == selectedRelayPresetID })
        let selectedManifest = selectedPreset?.manifest ?? relaySiteTemplates.first?.manifest
        let selectedRequiredInputs = selectedManifest.map {
            relayRequiredInputs(
                for: $0,
                tokenChannelEnabled: $0.tokenRequest != nil && $0.match.defaultTokenChannelEnabled,
                accountChannelEnabled: $0.match.defaultBalanceChannelEnabled,
                showsManualUserID: relayTemplateNeedsManualUserID($0)
            )
        } ?? [.displayName, .baseURL]
        let showNameField = true
        let showBaseURLField = selectedRequiredInputs.contains(.baseURL)

        return VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.relayTemplate))
                .font(settingsLabelFont)
                .foregroundStyle(settingsHintColor)

            Text(relaySiteTemplates.first?.displayName ?? "NewAPI")
                .font(settingsBodyFont)
                .foregroundStyle(settingsBodyColor)

            HStack(spacing: 8) {
                if showNameField {
                    TextField(viewModel.text(.providerName), text: $newProviderName)
                        .textFieldStyle(.roundedBorder)
                }
                if showBaseURLField {
                    TextField(viewModel.text(.baseURL), text: $newProviderBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                settingsActionButton(viewModel.text(.addProvider), prominent: true) {
                    let beforeIDs = Set(viewModel.config.providers.map(\.id))
                    viewModel.addOpenRelay(
                        name: resolvedRelayNameInput(
                            typedName: newProviderName,
                            manifest: selectedManifest
                        ),
                        baseURL: resolvedRelayBaseURLInput(
                            typedBaseURL: newProviderBaseURL,
                            manifest: selectedManifest
                        ),
                        preferredAdapterID: selectedRelayPresetID ?? newProviderTemplateID
                    )
                    if let added = viewModel.config.providers.first(where: { !beforeIDs.contains($0.id) }) {
                        selectedGroup = .thirdParty
                        selectedProviderID = added.id
                    }
                    newProviderName = ""
                    selectedRelayPresetID = nil
                    applyNewRelayTemplate(newProviderTemplateID)
                    customNewAPIRelayExpanded = false
                }
            }

            if !showBaseURLField, let selectedManifest, let suggestedBaseURL = suggestedBaseURL(for: selectedManifest) {
                Text("Base URL: \(suggestedBaseURL)")
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            if let preset = selectedPreset ?? relaySiteTemplates.first(where: { $0.id == newProviderTemplateID }) {
                Text(relayRequiredInputSummary(
                    manifest: preset.manifest,
                    tokenChannelEnabled: preset.manifest.tokenRequest != nil && preset.manifest.match.defaultTokenChannelEnabled,
                    accountChannelEnabled: preset.manifest.match.defaultBalanceChannelEnabled,
                    showsManualUserID: relayTemplateNeedsManualUserID(preset.manifest)
                ))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

                Text(relayFixedTemplateSummary(for: preset.manifest))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            Text(viewModel.text(.relayTemplatePresetHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
        }
    }

    private func relayPresetSidebarRow(_ preset: RelayTemplatePreset) -> some View {
        let provider = relayPresetProvider(for: preset.id)
        let isEnabled = provider?.enabled ?? false
        let isSelected = provider.map { selectedProviderID == $0.id } ?? false

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { setRelayPresetEnabled($0, preset: preset) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            if let provider {
                providerIcon(for: provider, size: 12)
            } else if let image = bundledImage(named: "relay_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)
                    .lineLimit(1)
                Text(isEnabled ? viewModel.text(.toggleOn) : viewModel.text(.toggleOff))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? settingsBodyColor : settingsHintColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.95) : outlineColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let provider {
                selectedProviderID = provider.id
            }
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.providers))
                .font(.subheadline.weight(.semibold))

            Text(viewModel.text(.officialProviders))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.config.providers.filter { $0.family == .official }) { provider in
                providerSettingsCard(provider)
            }

            Text(viewModel.text(.thirdPartyProviders))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.config.providers.filter { $0.family == .thirdParty }) { provider in
                providerSettingsCard(provider)
            }
        }
    }

    @ViewBuilder
    private func providerSettingsCard(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    providerIcon(for: provider, size: 14)
                    Text(sidebarDisplayName(for: provider))
                    Toggle("", isOn: Binding(
                        get: { provider.enabled },
                        set: { viewModel.setEnabled($0, providerID: provider.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.green)
                }
                    .font(settingsTitleFont)
                    .foregroundStyle(settingsTitleColor)
                Spacer()
                toggleStateBadge(isOn: provider.enabled)
            }

            if snapshot != nil || error != nil {
                providerUsageSummarySection(snapshot: snapshot, error: error)
            }

            HStack(spacing: 8) {
                Text(viewModel.text(.lowThreshold))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                Slider(
                    value: Binding(
                        get: { provider.threshold.lowRemaining },
                        set: { viewModel.setLowThreshold($0, providerID: provider.id) }
                    ),
                    in: 0...100
                )
                Text(String(format: "%.0f", provider.threshold.lowRemaining))
                    .font(settingsHintFont.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(settingsBodyColor)
            }

            HStack(spacing: 8) {
                Text(viewModel.text(.statusBarDisplayProvider))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                    set: { newValue in
                        if newValue {
                            viewModel.setStatusBarProvider(providerID: provider.id)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(.blue)
                .labelsHidden()
            }

            if provider.family == .official {
                officialConfigSection(provider)
            } else if provider.isRelay {
                openRelayConfigSection(provider)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func providerUsageSummarySection(snapshot: UsageSnapshot?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot {
                HStack(spacing: 16) {
                    if let remaining = snapshot.remaining {
                        providerUsageMetric(
                            title: snapshot.unit == "quota" ? viewModel.text(.balanceLabel) : viewModel.text(.remaining),
                            value: formattedSettingsAmount(remaining),
                            unit: snapshot.unit
                        )
                    }

                    if let used = snapshot.used {
                        providerUsageMetric(
                            title: viewModel.text(.used),
                            value: formattedSettingsAmount(used),
                            unit: snapshot.unit
                        )
                    }

                    if let limit = snapshot.limit {
                        providerUsageMetric(
                            title: viewModel.text(.limit),
                            value: formattedSettingsAmount(limit),
                            unit: snapshot.unit
                        )
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text("\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: snapshot.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !snapshot.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(snapshot.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func providerUsageMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
            Text(unit.isEmpty ? value : "\(value) \(unit)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(settingsTitleColor)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func officialConfigSection(_ provider: ProviderDescriptor) -> some View {
        let supportedSourceModes = provider.supportedOfficialSourceModes
        let supportedWebModes = provider.supportedOfficialWebModes
        let quotaDisplayBinding = Binding(
            get: {
                officialQuotaDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.quotaDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode)
            },
            set: { officialQuotaDisplayModeInputs[provider.id] = $0 }
        )
        let sourceBinding = Binding(
            get: {
                let current = officialSourceModeInputs[provider.id] ?? (provider.officialConfig?.sourceMode ?? .auto)
                return supportedSourceModes.contains(current) ? current : (supportedSourceModes.first ?? .auto)
            },
            set: { officialSourceModeInputs[provider.id] = $0 }
        )
        let webBinding = Binding(
            get: {
                let current = officialWebModeInputs[provider.id] ?? (provider.officialConfig?.webMode ?? .disabled)
                return supportedWebModes.contains(current) ? current : (supportedWebModes.first ?? .disabled)
            },
            set: { officialWebModeInputs[provider.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(viewModel.text(.sourceMode))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsHintColor)
                Picker("", selection: sourceBinding) {
                    ForEach(supportedSourceModes) { mode in
                        Text(sourceModeLabel(mode))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            if supportedWebModes.count > 1 {
                HStack(spacing: 8) {
                    Text(viewModel.text(.webMode))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsHintColor)
                    Picker("", selection: webBinding) {
                        ForEach(supportedWebModes) { mode in
                            Text(webModeLabel(mode))
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
            }

            if provider.type == .claude {
                HStack(spacing: 8) {
                    Text(viewModel.text(.quotaDisplayMode))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsHintColor)
                    Picker("", selection: quotaDisplayBinding) {
                        Text(viewModel.text(.quotaDisplayRemaining)).tag(OfficialQuotaDisplayMode.remaining)
                        Text(viewModel.text(.quotaDisplayUsed)).tag(OfficialQuotaDisplayMode.used)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Text(viewModel.text(.claudeQuotaDisplayHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            if provider.supportsOfficialManualCookieInput {
                HStack {
                    SecureField(viewModel.text(.manualCookieHeader), text: Binding(
                        get: { officialCookieInputs[provider.id, default: ""] },
                        set: { officialCookieInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    settingsActionButton(viewModel.text(.saveToken)) {
                        let raw = officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !raw.isEmpty else { return }
                        _ = viewModel.saveOfficialManualCookie(raw, providerID: provider.id)
                        officialCookieInputs[provider.id] = ""
                        viewModel.restartPolling()
                    }

                    Text(viewModel.hasOfficialManualCookie(for: provider) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                        .font(settingsHintFont)
                        .foregroundStyle(viewModel.hasOfficialManualCookie(for: provider) ? .green : .secondary)
                }
            }

            Text(viewModel.text(.officialAutoDiscoveryHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

            if provider.type == .codex {
                codexProfileManagementSection()
            }

            settingsActionButton(viewModel.text(.saveConfig), prominent: true) {
                viewModel.updateOfficialProviderSettings(
                    providerID: provider.id,
                    sourceMode: sourceBinding.wrappedValue ?? supportedSourceModes.first ?? .auto,
                    webMode: webBinding.wrappedValue ?? supportedWebModes.first ?? .disabled,
                    quotaDisplayMode: provider.type == .claude ? quotaDisplayBinding.wrappedValue : nil
                )
            }
        }
    }

    @ViewBuilder
    private func codexProfileManagementSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.codexProfiles))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.text(.codexProfileHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            let profiles = viewModel.codexProfilesForSettings()
            let slotIDs = profiles.map(\.slotID).sorted()

            ForEach(slotIDs, id: \.rawValue) { slotID in
                let key = slotID.rawValue
                let profile = profiles.first(where: { $0.slotID == slotID })
                let isExpanded = codexProfileExpanded.contains(key)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(viewModel.codexSettingsTitle(for: slotID))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        if profile?.isCurrentSystemAccount == true {
                            Text(viewModel.text(.codexCurrentAccount))
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(hex: 0x296322))
                                )
                        }
                        Text(profile?.accountEmail ?? viewModel.text(.codexProfileEmailUnknown))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let importedAt = profile?.lastImportedAt {
                            Text("\(viewModel.text(.codexImportedAt)) \(settingsElapsedText(from: importedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if profile != nil {
                            Button(viewModel.text(.codexDeleteProfile), role: .destructive) {
                                codexProfilePendingDelete = slotID
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0xD83E3E))
                        }
                    }

                    if profile == nil {
                        Text(viewModel.text(.codexImportNextProfile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if isExpanded {
                            codexProfileExpanded.remove(key)
                        } else {
                            codexProfileExpanded.insert(key)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                            Text(viewModel.text(.codexProfileDetails))
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        TextEditor(text: Binding(
                            get: { codexProfileJSONInputs[key] ?? profile?.authJSON ?? "" },
                            set: { codexProfileJSONInputs[key] = $0 }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 88)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(outlineColor, lineWidth: 1)
                        )

                        HStack {
                            Button(viewModel.text(.codexImportProfile)) {
                                codexProfileResult[key] = viewModel.saveCodexProfile(
                                    slotID: slotID,
                                    displayName: "Codex \(slotID.rawValue)",
                                    authJSON: codexProfileJSONInputs[key] ?? profile?.authJSON ?? ""
                                )
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }

                    if let result = codexProfileResult[key], !result.isEmpty {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains(viewModel.text(.codexProfileImportFailed)) ? .red : .green)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(outlineColor, lineWidth: 1)
                )
            }

            let nextSlotID = viewModel.nextCodexProfileSlotID()
            let nextKey = nextSlotID.rawValue
            let nextExpanded = codexProfileExpanded.contains(nextKey)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.codexSettingsTitle(for: nextSlotID))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.text(.codexImportNextProfile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    if nextExpanded {
                        codexProfileExpanded.remove(nextKey)
                    } else {
                        codexProfileExpanded.insert(nextKey)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: nextExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Text(viewModel.text(.codexProfileDetails))
                            .font(.caption.weight(.semibold))
                        Text(viewModel.text(.codexAuthJSONHowTo))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if nextExpanded {
                    TextEditor(text: Binding(
                        get: { codexProfileJSONInputs[nextKey] ?? "" },
                        set: { codexProfileJSONInputs[nextKey] = $0 }
                    ))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 88)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )

                    HStack {
                        Button(viewModel.text(.codexImportProfile)) {
                            codexProfileResult[nextKey] = viewModel.saveCodexProfile(
                                slotID: nextSlotID,
                                displayName: "Codex \(nextSlotID.rawValue)",
                                authJSON: codexProfileJSONInputs[nextKey] ?? ""
                            )
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    if let result = codexProfileResult[nextKey], !result.isEmpty {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains(viewModel.text(.codexProfileImportFailed)) ? .red : .green)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
        }
    }

    private func sourceModeLabel(_ mode: OfficialSourceMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .api: return "API"
        case .cli: return "CLI"
        case .web: return "Web"
        }
    }

    private func webModeLabel(_ mode: OfficialWebMode) -> String {
        switch mode {
        case .disabled: return viewModel.text(.webDisabled)
        case .autoImport: return viewModel.text(.webAutoImport)
        case .manual: return viewModel.text(.webManual)
        }
    }

    private var permissionAlertTitle: String {
        switch permissionPrompt {
        case .notifications:
            return viewModel.text(.permissionNotificationsTitle)
        case .keychain:
            return viewModel.text(.permissionKeychainTitle)
        case .fullDisk:
            return viewModel.text(.permissionFullDiskTitle)
        case .autoDiscovery:
            return viewModel.text(.localDiscoveryTitle)
        case .resetLocalData:
            return viewModel.text(.resetLocalDataTitle)
        case .none:
            return ""
        }
    }

    private var permissionAlertMessage: String {
        switch permissionPrompt {
        case .notifications:
            return viewModel.text(.permissionNotificationsConfirm)
        case .keychain:
            return viewModel.text(.permissionKeychainConfirm)
        case .fullDisk:
            return viewModel.text(.permissionFullDiskConfirm)
        case .autoDiscovery:
            return viewModel.text(.localDiscoveryConfirm)
        case .resetLocalData:
            return viewModel.text(.resetLocalDataConfirm)
        case .none:
            return ""
        }
    }

    private func handlePermissionPrompt() {
        let prompt = permissionPrompt
        permissionPrompt = nil

        switch prompt {
        case .notifications:
            viewModel.requestNotificationPermission()
            permissionResultMessage[PermissionPrompt.notifications.id] = viewModel.text(.permissionNotificationsRequested)
            permissionResultIsError[PermissionPrompt.notifications.id] = false
        case .keychain:
            let ok = viewModel.prepareSecureStorageAccess()
            permissionResultMessage[PermissionPrompt.keychain.id] = ok
                ? viewModel.text(.permissionKeychainReady)
                : viewModel.text(.permissionKeychainFailed)
            permissionResultIsError[PermissionPrompt.keychain.id] = !ok
        case .fullDisk:
            viewModel.openFullDiskAccessSettings()
            permissionResultMessage[PermissionPrompt.fullDisk.id] = viewModel.text(.permissionFullDiskRequested)
            permissionResultIsError[PermissionPrompt.fullDisk.id] = false
        case .autoDiscovery:
            permissionResultMessage[PermissionPrompt.autoDiscovery.id] = viewModel.text(.localDiscoveryScanning)
            permissionResultIsError[PermissionPrompt.autoDiscovery.id] = false
            Task { @MainActor in
                let result = await viewModel.discoverLocalProviders()
                permissionResultMessage[PermissionPrompt.autoDiscovery.id] = result
                permissionResultIsError[PermissionPrompt.autoDiscovery.id] = result == viewModel.text(.localDiscoveryNothingFound)
            }
        case .resetLocalData:
            viewModel.resetLocalAppData()
            seedInputsFromConfig()
            syncSelection()
            selectedSettingsTab = .general
            permissionResultMessage[PermissionPrompt.resetLocalData.id] = viewModel.text(.resetLocalDataDone)
            permissionResultIsError[PermissionPrompt.resetLocalData.id] = false
        case .none:
            break
        }
        viewModel.refreshPermissionStatusesNow()
    }

    @ViewBuilder
    private func openRelayConfigSection(_ provider: ProviderDescriptor) -> some View {
        let relayViewConfig = provider.relayViewConfig
        let accountAuth = relayViewConfig?.accountBalance?.auth
        let simpleMode = true
        let providerAdapterID = provider.relayConfig?.adapterID
            ?? provider.relayManifest?.id
            ?? "generic-newapi"
        let selectedTemplateID = selectedRelayTemplateInputs[provider.id] ?? providerAdapterID
        let selectedTemplate = relaySiteTemplates.first(where: { $0.id == selectedTemplateID })?.manifest
            ?? provider.relayManifest
            ?? RelayAdapterRegistry.shared.manifest(for: provider.baseURL ?? "", preferredID: selectedTemplateID)
        let currentPreset = providerAdapterID == "generic-newapi"
            ? nil
            : relayBuiltInPresets.first(where: { $0.id == providerAdapterID })?.manifest
        let tokenChannelEnabled = tokenUsageEnabledInputs[provider.id]
            ?? relayViewConfig?.tokenUsageEnabled
            ?? selectedTemplate.match.defaultTokenChannelEnabled
        let accountChannelEnabled = accountEnabledInputs[provider.id]
            ?? relayViewConfig?.accountBalance?.enabled
            ?? selectedTemplate.match.defaultBalanceChannelEnabled
        let tokenTemplate = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer")
        let balanceTemplate = relayCredentialTemplate(
            authHeader: selectedTemplate.balanceRequest.authHeader ?? relayViewConfig?.accountBalance?.authHeader,
            authScheme: selectedTemplate.balanceRequest.authScheme ?? relayViewConfig?.accountBalance?.authScheme
        )
        let showTokenCredential = tokenChannelEnabled
        let showBalanceCredential = accountChannelEnabled
        let defaultUserID = relayViewConfig?.accountBalance?.userID
            ?? selectedTemplate.balanceRequest.userID
            ?? ""
        let showUserIDField = showBalanceCredential && relayTemplateNeedsManualUserID(selectedTemplate)
        let currentBaseURL = baseURLInputs[provider.id] ?? (provider.baseURL ?? "")
        let showNameField = true
        let showBaseURLField = !simpleMode || requiresBaseURLInput(for: selectedTemplate, currentBaseURL: currentBaseURL)
        let credentialMode = relayCredentialModeInputs[provider.id]
            ?? provider.relayConfig?.balanceCredentialMode
            ?? .manualPreferred

        VStack(alignment: .leading, spacing: 8) {
            if let currentPreset, selectedRelayTemplateInputs[provider.id] == nil {
                HStack(spacing: 8) {
                    Text(viewModel.text(.matchedAdapter))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsHintColor)
                    Text(currentPreset.displayName)
                        .font(settingsBodyFont)
                        .foregroundStyle(settingsBodyColor)
                    Spacer()
                    settingsActionButton(viewModel.text(.relayTemplate)) {
                        selectedRelayTemplateInputs[provider.id] = "generic-newapi"
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(viewModel.text(.relayTemplate))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsHintColor)
                    Picker("", selection: Binding(
                        get: { selectedRelayTemplateInputs[provider.id] ?? "generic-newapi" },
                        set: { selectedRelayTemplateInputs[provider.id] = $0 }
                    )) {
                        ForEach(relaySiteTemplates) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            if showNameField || showBaseURLField {
                HStack(spacing: 8) {
                    if showNameField {
                        TextField(viewModel.text(.providerName), text: Binding(
                            get: { providerNameInputs[provider.id] ?? provider.name },
                            set: { providerNameInputs[provider.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    if showBaseURLField {
                        TextField(viewModel.text(.baseURL), text: Binding(
                            get: { baseURLInputs[provider.id] ?? (provider.baseURL ?? "") },
                            set: { baseURLInputs[provider.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if simpleMode {
                if !showBaseURLField, let suggestedBaseURL = suggestedBaseURL(for: selectedTemplate) {
                    Text("Base URL: \(suggestedBaseURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showUserIDField {
                Text(viewModel.text(.userID))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsHintColor)

                TextField(viewModel.text(.userID), text: Binding(
                    get: { userIDInputs[provider.id] ?? defaultUserID },
                    set: { userIDInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.plain)
                .relayProminentInput()

                if let userIDHint = relaySetupHint(for: selectedTemplate, field: .userID) {
                    Text(userIDHint)
                        .font(settingsHintFont)
                        .foregroundStyle(settingsHintColor)
                }
            }

            if showBalanceCredential {
                Text(relayCredentialSectionTitle(isAccount: true, templateKind: balanceTemplate.kind))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsHintColor)

                HStack {
                    SecureField(balanceTemplate.placeholder, text: Binding(
                        get: { systemTokenInputs[provider.id, default: ""] },
                        set: { systemTokenInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .relayProminentInput()

                    settingsActionButton(relayCredentialSaveLabel(templateKind: balanceTemplate.kind)) {
                        guard let accountAuth else { return }
                        let token = systemTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty else { return }
                        _ = viewModel.saveToken(token, auth: accountAuth)
                        systemTokenInputs[provider.id] = ""
                        viewModel.restartPolling()
                    }

                    if let accountAuth {
                        Text(viewModel.hasToken(auth: accountAuth) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                            .font(settingsHintFont)
                            .foregroundStyle(viewModel.hasToken(auth: accountAuth) ? .green : .secondary)
                    }
                }

                Text(balanceTemplate.hint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)

                if let balanceSetupHint = relaySetupHint(for: selectedTemplate, field: .balanceAuth) {
                    Text(balanceSetupHint)
                        .font(settingsHintFont)
                        .foregroundStyle(settingsHintColor)
                }

                Text(relayCredentialLookupHint(templateKind: balanceTemplate.kind))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            if showTokenCredential {
                Text(relayCredentialSectionTitle(isAccount: false, templateKind: tokenTemplate.kind))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsHintColor)

                HStack {
                    SecureField(tokenTemplate.placeholder, text: Binding(
                        get: { tokenInputs[provider.id, default: ""] },
                        set: { tokenInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .relayProminentInput()

                    settingsActionButton(relayCredentialSaveLabel(templateKind: tokenTemplate.kind)) {
                        let token = tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty else { return }
                        _ = viewModel.saveToken(token, for: provider)
                        tokenInputs[provider.id] = ""
                        viewModel.restartPolling()
                    }

                    Text(viewModel.hasToken(for: provider) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                        .font(settingsHintFont)
                        .foregroundStyle(viewModel.hasToken(for: provider) ? .green : .secondary)
                }

                Text(tokenTemplate.hint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)

                if let quotaSetupHint = relaySetupHint(for: selectedTemplate, field: .quotaAuth) {
                    Text(quotaSetupHint)
                        .font(settingsHintFont)
                        .foregroundStyle(settingsHintColor)
                }

                Text(relayCredentialLookupHint(templateKind: tokenTemplate.kind))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            HStack(spacing: 8) {
                Text(viewModel.text(.credentialMode))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsHintColor)
                Picker("", selection: Binding(
                    get: { credentialMode },
                    set: { relayCredentialModeInputs[provider.id] = $0 }
                )) {
                    ForEach(RelayCredentialMode.allCases) { mode in
                        Text(relayCredentialModeLabel(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Text(viewModel.text(.credentialModeHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

            HStack(spacing: 8) {
                Text("\(viewModel.text(.matchedAdapter)): \(selectedTemplate.displayName)")
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            relayRuntimeStatusSection(provider, selectedTemplate: selectedTemplate)

            Text(relayRequiredInputSummary(
                manifest: selectedTemplate,
                tokenChannelEnabled: showTokenCredential,
                accountChannelEnabled: showBalanceCredential,
                showsManualUserID: showUserIDField
            ))
            .font(settingsHintFont)
            .foregroundStyle(settingsHintColor)

            Text(relayFixedTemplateSummary(for: selectedTemplate))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

            if let diagnosticHint = relayDiagnosticHint(for: selectedTemplate) {
                Text(diagnosticHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            HStack(spacing: 8) {
                settingsActionButton(viewModel.text(.saveConfig), prominent: true) {
                    viewModel.updateOpenProviderSettings(
                        providerID: provider.id,
                        name: resolvedRelayNameInput(
                            typedName: providerNameInputs[provider.id] ?? provider.name,
                            manifest: selectedTemplate
                        ),
                        baseURL: resolvedRelayBaseURLInput(
                            typedBaseURL: baseURLInputs[provider.id] ?? (provider.baseURL ?? ""),
                            manifest: selectedTemplate
                        ),
                        preferredAdapterID: selectedRelayTemplateInputs[provider.id] ?? providerAdapterID,
                        balanceCredentialMode: relayCredentialModeInputs[provider.id]
                            ?? provider.relayConfig?.balanceCredentialMode
                            ?? .manualPreferred,
                        tokenUsageEnabled: tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled,
                        accountEnabled: accountEnabledInputs[provider.id] ?? accountChannelEnabled,
                        authHeader: authHeaderInputs[provider.id] ?? (relayViewConfig?.accountBalance?.authHeader ?? "Authorization"),
                        authScheme: authSchemeInputs[provider.id] ?? (relayViewConfig?.accountBalance?.authScheme ?? "Bearer"),
                        userID: userIDInputs[provider.id] ?? defaultUserID,
                        userIDHeader: userHeaderInputs[provider.id] ?? (relayViewConfig?.accountBalance?.userIDHeader ?? "New-Api-User"),
                        endpointPath: endpointPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.endpointPath ?? "/api/user/self"),
                        remainingJSONPath: remainingPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.remainingJSONPath ?? "data.quota"),
                        usedJSONPath: usedPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.usedJSONPath ?? ""),
                        limitJSONPath: limitPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.limitJSONPath ?? ""),
                        successJSONPath: successPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.successJSONPath ?? ""),
                        unit: unitInputs[provider.id] ?? (relayViewConfig?.accountBalance?.unit ?? "quota")
                    )
                }

                settingsActionButton(viewModel.text(.testConnection)) {
                    Task {
                        guard let previewDescriptor = viewModel.relayDescriptorForPreview(
                            providerID: provider.id,
                            name: resolvedRelayNameInput(
                                typedName: providerNameInputs[provider.id] ?? provider.name,
                                manifest: selectedTemplate
                            ),
                            baseURL: resolvedRelayBaseURLInput(
                                typedBaseURL: baseURLInputs[provider.id] ?? (provider.baseURL ?? ""),
                                manifest: selectedTemplate
                            ),
                            preferredAdapterID: selectedTemplateID,
                            balanceCredentialMode: relayCredentialModeInputs[provider.id]
                                ?? provider.relayConfig?.balanceCredentialMode
                                ?? .manualPreferred,
                            tokenUsageEnabled: tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled,
                            accountEnabled: accountEnabledInputs[provider.id] ?? accountChannelEnabled,
                            authHeader: authHeaderInputs[provider.id] ?? (relayViewConfig?.accountBalance?.authHeader ?? "Authorization"),
                            authScheme: authSchemeInputs[provider.id] ?? (relayViewConfig?.accountBalance?.authScheme ?? "Bearer"),
                            userID: userIDInputs[provider.id] ?? defaultUserID,
                            userIDHeader: userHeaderInputs[provider.id] ?? (relayViewConfig?.accountBalance?.userIDHeader ?? "New-Api-User"),
                            endpointPath: endpointPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.endpointPath ?? "/api/user/self"),
                            remainingJSONPath: remainingPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.remainingJSONPath ?? "data.quota"),
                            usedJSONPath: usedPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.usedJSONPath ?? ""),
                            limitJSONPath: limitPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.limitJSONPath ?? ""),
                            successJSONPath: successPathInputs[provider.id] ?? (relayViewConfig?.accountBalance?.successJSONPath ?? ""),
                            unit: unitInputs[provider.id] ?? (relayViewConfig?.accountBalance?.unit ?? "quota")
                        ) else {
                            relayTestResult[provider.id] = RelayDiagnosticResult(
                                success: false,
                                fetchHealth: .endpointMisconfigured,
                                resolvedAdapterID: selectedTemplateID,
                                resolvedAuthSource: nil,
                                message: viewModel.text(.error),
                                snapshotPreview: nil
                            )
                            return
                        }
                        relayTestResult[provider.id] = await viewModel.testRelayConnection(descriptor: previewDescriptor)
                    }
                }

                if provider.id != "open-ailinyu" {
                    settingsActionButton(viewModel.text(.removeProvider), destructive: true) {
                        viewModel.removeProvider(providerID: provider.id)
                    }
                }
            }

            if let relayTestResult = relayTestResult[provider.id] {
                relayDiagnosticSection(relayTestResult)
            }

            DisclosureGroup(
                isExpanded: Binding(
                    get: { relayAdvancedExpanded[provider.id] ?? false },
                    set: { relayAdvancedExpanded[provider.id] = $0 }
                ),
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        let tokenChannelBinding = Binding(
                            get: { tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled },
                            set: { tokenUsageEnabledInputs[provider.id] = $0 }
                        )
                        labeledToggle(viewModel.text(.enableTokenChannel), isOn: tokenChannelBinding)

                        let accountChannelBinding = Binding(
                            get: { accountEnabledInputs[provider.id] ?? accountChannelEnabled },
                            set: { accountEnabledInputs[provider.id] = $0 }
                        )
                        labeledToggle(viewModel.text(.enableAccountChannel), isOn: accountChannelBinding)

                        HStack(spacing: 8) {
                            TextField(viewModel.text(.authHeader), text: Binding(
                                get: {
                                    authHeaderInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.authHeader
                                        ?? selectedTemplate.balanceRequest.authHeader
                                        ?? "Authorization"
                                },
                                set: { authHeaderInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField(viewModel.text(.authScheme), text: Binding(
                                get: {
                                    authSchemeInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.authScheme
                                        ?? selectedTemplate.balanceRequest.authScheme
                                        ?? "Bearer"
                                },
                                set: { authSchemeInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            TextField(viewModel.text(.userIDHeader), text: Binding(
                                get: {
                                    userHeaderInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.userIDHeader
                                        ?? selectedTemplate.balanceRequest.userIDHeader
                                        ?? "New-Api-User"
                                },
                                set: { userHeaderInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField(viewModel.text(.endpointPath), text: Binding(
                                get: {
                                    endpointPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.endpointPath
                                        ?? selectedTemplate.balanceRequest.path
                                },
                                set: { endpointPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            TextField(viewModel.text(.unit), text: Binding(
                                get: {
                                    unitInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.unit
                                        ?? selectedTemplate.extract.unit
                                        ?? "quota"
                                },
                                set: { unitInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField(viewModel.text(.remainingPath), text: Binding(
                                get: {
                                    remainingPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.remainingJSONPath
                                        ?? selectedTemplate.extract.remaining
                                },
                                set: { remainingPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            TextField(viewModel.text(.usedPath), text: Binding(
                                get: {
                                    usedPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.usedJSONPath
                                        ?? selectedTemplate.extract.used
                                        ?? ""
                                },
                                set: { usedPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField(viewModel.text(.limitPath), text: Binding(
                                get: {
                                    limitPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.limitJSONPath
                                        ?? selectedTemplate.extract.limit
                                        ?? ""
                                },
                                set: { limitPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        TextField(viewModel.text(.successPath), text: Binding(
                            get: {
                                successPathInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.successJSONPath
                                    ?? selectedTemplate.extract.success
                                    ?? ""
                            },
                            set: { successPathInputs[provider.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                },
                label: {
                    Text(viewModel.text(.advancedSettings))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsHintColor)
                }
            )
        }
    }

    private var sidebarProviders: [ProviderDescriptor] {
        let providers = viewModel.config.providers.filter { provider in
            switch selectedGroup {
            case .official:
                return provider.family == .official
            case .thirdParty:
                return provider.family == .thirdParty
            }
        }
        return providers.filter(\.enabled) + providers.filter { !$0.enabled }
    }

    private var enabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter(\.enabled)
    }

    private var disabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter { !$0.enabled }
    }

    private var customRelayProviders: [ProviderDescriptor] {
        let builtInPresetIDs = Set(relayBuiltInPresets.map(\.id))
        return viewModel.config.providers.filter { provider in
            provider.family == .thirdParty &&
            !builtInPresetIDs.contains(provider.relayConfig?.adapterID ?? "")
        }
    }

    private var relayTemplatePresets: [RelayTemplatePreset] {
        RelayAdapterRegistry.shared
            .availableManifests()
            .map { manifest in
                RelayTemplatePreset(
                    manifest: manifest,
                    suggestedBaseURL: suggestedBaseURL(for: manifest)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.id == "generic-newapi", rhs.id == "generic-newapi") {
                case (true, false):
                    return false
                case (false, true):
                    return true
                default:
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
    }

    private var relaySiteTemplates: [RelayTemplatePreset] {
        relayTemplatePresets.filter { $0.id == "generic-newapi" }
    }

    private var relayBuiltInPresets: [RelayTemplatePreset] {
        relayTemplatePresets.filter { $0.id != "generic-newapi" }
    }

    private func relayTemplateNeedsManualUserID(_ manifest: RelayAdapterManifest) -> Bool {
        let setupRequiresUserID = manifest.setup?.requiredInputs.contains(.userID) ?? false
        return setupRequiresUserID || (
            manifest.balanceRequest.userID == nil &&
            !(manifest.balanceRequest.userIDHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
    }

    private func suggestedBaseURL(for manifest: RelayAdapterManifest) -> String? {
        if let recommendedBaseURL = manifest.setup?.recommendedBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedBaseURL.isEmpty {
            return recommendedBaseURL
        }
        guard let hostPattern = manifest.match.hostPatterns.first(where: { $0 != "*" }) else {
            return nil
        }
        let normalizedHost: String
        if hostPattern.hasPrefix("*.") {
            normalizedHost = String(hostPattern.dropFirst(2))
        } else {
            normalizedHost = hostPattern
        }
        return normalizedHost.isEmpty ? nil : "https://\(normalizedHost)"
    }

    private func applyNewRelayTemplate(_ templateID: String) {
        newProviderTemplateID = templateID
        guard let preset = relaySiteTemplates.first(where: { $0.id == templateID }) else { return }
        if let suggestedBaseURL = preset.suggestedBaseURL {
            newProviderBaseURL = suggestedBaseURL
        } else {
            newProviderBaseURL = "https://"
        }
        if selectedRelayPresetID == nil {
            newProviderName = ""
        }
    }

    private func applyRelayPreset(_ preset: RelayTemplatePreset) {
        if let suggestedBaseURL = preset.suggestedBaseURL {
            newProviderBaseURL = suggestedBaseURL
        } else {
            newProviderBaseURL = "https://"
        }
        newProviderName = preset.displayName
    }

    private func resolvedRelayNameInput(
        typedName: String,
        manifest: RelayAdapterManifest?
    ) -> String {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return manifest?.displayName ?? typedName
    }

    private func resolvedRelayBaseURLInput(
        typedBaseURL: String,
        manifest: RelayAdapterManifest?
    ) -> String {
        let trimmed = typedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return suggestedBaseURL(for: manifest ?? RelayAdapterRegistry.genericManifest) ?? typedBaseURL
    }

    private enum RelaySetupHintField {
        case quotaAuth
        case balanceAuth
        case userID
    }

    private func relaySetupHint(
        for manifest: RelayAdapterManifest,
        field: RelaySetupHintField
    ) -> String? {
        let localized: RelaySetupManifest.LocalizedText?
        switch field {
        case .quotaAuth:
            localized = manifest.setup?.quotaAuthHint
        case .balanceAuth:
            localized = manifest.setup?.balanceAuthHint
        case .userID:
            localized = manifest.setup?.userIDHint
        }

        switch viewModel.language {
        case .zhHans:
            return localized?.zhHans ?? localized?.en
        case .en:
            return localized?.en ?? localized?.zhHans
        }
    }

    private func relayDiagnosticHint(for manifest: RelayAdapterManifest) -> String? {
        switch viewModel.language {
        case .zhHans:
            return manifest.setup?.diagnosticHints?.zhHans ?? manifest.setup?.diagnosticHints?.en
        case .en:
            return manifest.setup?.diagnosticHints?.en ?? manifest.setup?.diagnosticHints?.zhHans
        }
    }

    private func relayRequiredInputs(
        for manifest: RelayAdapterManifest,
        tokenChannelEnabled: Bool,
        accountChannelEnabled: Bool,
        showsManualUserID: Bool
    ) -> [RelayRequiredInputKind] {
        if let setupInputs = manifest.setup?.requiredInputs, !setupInputs.isEmpty {
            var resolved: [RelayRequiredInputKind] = []
            for item in setupInputs {
                switch item {
                case .quotaAuth where tokenChannelEnabled:
                    resolved.append(item)
                case .balanceAuth where accountChannelEnabled:
                    resolved.append(item)
                case .userID where showsManualUserID:
                    resolved.append(item)
                case .quotaAuth, .balanceAuth, .userID:
                    continue
                default:
                    resolved.append(item)
                }
            }
            if showsManualUserID && !resolved.contains(.userID) && relayTemplateNeedsManualUserID(manifest) {
                resolved.append(.userID)
            }
            return resolved
        }

        var inferred: [RelayRequiredInputKind] = [.displayName, .baseURL]
        if tokenChannelEnabled {
            inferred.append(.quotaAuth)
        }
        if accountChannelEnabled {
            inferred.append(.balanceAuth)
        }
        if showsManualUserID {
            inferred.append(.userID)
        }
        return inferred
    }

    private func requiresDisplayNameInput(
        for manifest: RelayAdapterManifest,
        currentName: String
    ) -> Bool {
        let requiredInputs = manifest.setup?.requiredInputs ?? []
        if requiredInputs.isEmpty {
            return true
        }
        if requiredInputs.contains(.displayName) {
            return true
        }
        return currentName.trimmingCharacters(in: .whitespacesAndNewlines) != manifest.displayName
    }

    private func requiresBaseURLInput(
        for manifest: RelayAdapterManifest,
        currentBaseURL: String
    ) -> Bool {
        let requiredInputs = manifest.setup?.requiredInputs ?? []
        if requiredInputs.isEmpty {
            return true
        }
        if requiredInputs.contains(.baseURL) {
            return true
        }
        guard let suggestedBaseURL = suggestedBaseURL(for: manifest) else {
            return true
        }
        return ProviderDescriptor.normalizeRelayBaseURL(currentBaseURL) != ProviderDescriptor.normalizeRelayBaseURL(suggestedBaseURL)
    }

    private func relayRequiredInputSummary(
        manifest: RelayAdapterManifest,
        tokenChannelEnabled: Bool,
        accountChannelEnabled: Bool,
        showsManualUserID: Bool
    ) -> String {
        let tokenTemplateKind = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer").kind
        let balanceTemplateKind = relayCredentialTemplate(
            authHeader: manifest.balanceRequest.authHeader,
            authScheme: manifest.balanceRequest.authScheme
        ).kind
        let items = relayRequiredInputs(
            for: manifest,
            tokenChannelEnabled: tokenChannelEnabled,
            accountChannelEnabled: accountChannelEnabled,
            showsManualUserID: showsManualUserID
        ).filter { $0 != .displayName }.map { item in
            switch item {
            case .displayName:
                return viewModel.language == .zhHans ? "名称" : "Name"
            case .baseURL:
                return "Base URL"
            case .quotaAuth:
                return relayCredentialFieldName(isAccount: false, templateKind: tokenTemplateKind)
            case .balanceAuth:
                return relayCredentialFieldName(isAccount: true, templateKind: balanceTemplateKind)
            case .userID:
                return viewModel.language == .zhHans ? "用户 ID" : "User ID"
            }
        }

        let joined = items.joined(separator: viewModel.language == .zhHans ? "、" : ", ")
        if viewModel.language == .zhHans {
            if joined.isEmpty {
                return "当前模板 `\(manifest.displayName)` 的接口配置已固定，名称可自定义。"
            }
            return "当前模板 `\(manifest.displayName)` 的核心必填项：\(joined)。名称可自定义。"
        } else {
            if joined.isEmpty {
                return "Template `\(manifest.displayName)` already fixes the endpoint details; the display name is optional and customizable."
            }
            return "Template `\(manifest.displayName)` only needs these core fields: \(joined). Display name is optional and customizable."
        }
    }

    private func relayFixedTemplateSummary(for manifest: RelayAdapterManifest) -> String {
        let language = viewModel.language
        var parts: [String] = []

        if let suggestedBaseURL = suggestedBaseURL(for: manifest) {
            parts.append(language == .zhHans ? "固定地址 = \(suggestedBaseURL)" : "base URL = \(suggestedBaseURL)")
        }

        parts.append("\(manifest.balanceRequest.method) \(manifest.balanceRequest.path)")
        parts.append(language == .zhHans
            ? "剩余 = \(manifest.extract.remaining)"
            : "remaining = \(manifest.extract.remaining)")

        if let used = manifest.extract.used, !used.isEmpty {
            parts.append(language == .zhHans ? "已用 = \(used)" : "used = \(used)")
        }
        if let limit = manifest.extract.limit, !limit.isEmpty {
            parts.append(language == .zhHans ? "上限 = \(limit)" : "limit = \(limit)")
        }
        if let unit = manifest.extract.unit, !unit.isEmpty {
            parts.append(language == .zhHans ? "单位 = \(unit)" : "unit = \(unit)")
        }

        let joined = parts.joined(separator: language == .zhHans ? "；" : "; ")
        if language == .zhHans {
            return "以下内容由模板固定：\(joined)。如需改接口或字段映射，再展开高级设置。"
        } else {
            return "These values are fixed by the template: \(joined). Open Advanced settings only if the site differs."
        }
    }

    private var selectedFamily: ProviderFamily {
        switch selectedGroup {
        case .official:
            return .official
        case .thirdParty:
            return .thirdParty
        }
    }

    private func moveEnabledProviders(from source: IndexSet, to destination: Int) {
        viewModel.reorderEnabledProviders(
            family: selectedFamily,
            fromOffsets: source,
            toOffset: destination
        )
    }

    private var selectedProvider: ProviderDescriptor? {
        guard let selectedProviderID else { return nil }
        return sidebarProviders.first(where: { $0.id == selectedProviderID })
    }

    private func syncSelection() {
        let ids = sidebarProviders.map(\.id)
        guard !ids.isEmpty else {
            selectedProviderID = nil
            return
        }
        if let selectedProviderID, ids.contains(selectedProviderID) {
            return
        }
        self.selectedProviderID = ids.first
    }

    private func sidebarDisplayName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .copilot:
            return "Copilot"
        case .zai:
            return "Z.ai"
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return "Kimi"
        case .relay, .open, .dragon:
            return provider.name
        }
    }

    private func iconName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "codex_icon"
        case .kimi:
            return "kimi_icon"
        default:
            return "relay_icon"
        }
    }

    private func fallbackIcon(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "terminal.fill"
        case .kimi:
            return "moon.stars.fill"
        default:
            return "globe"
        }
    }

    @ViewBuilder
    private func providerIcon(for provider: ProviderDescriptor, size: CGFloat) -> some View {
        if let image = bundledImage(named: iconName(for: provider)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackIcon(for: provider))
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
    }

    private func bundledImage(named name: String) -> NSImage? {
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }

    private func seedInputsFromConfig() {
        for provider in viewModel.config.providers where provider.isRelay {
            let relayViewConfig = provider.relayViewConfig
            let defaultManifest = provider.relayManifest
                ?? RelayAdapterRegistry.shared.manifest(
                    for: provider.baseURL ?? "",
                    preferredID: provider.relayConfig?.adapterID
                )
            if selectedRelayTemplateInputs[provider.id] == nil {
                let providerAdapterID = provider.relayConfig?.adapterID
                    ?? provider.relayManifest?.id
                    ?? "generic-newapi"
                selectedRelayTemplateInputs[provider.id] = providerAdapterID == "generic-newapi"
                    ? "generic-newapi"
                    : nil
            }
            if providerNameInputs[provider.id] == nil {
                providerNameInputs[provider.id] = provider.name
            }
            if baseURLInputs[provider.id] == nil {
                baseURLInputs[provider.id] = provider.baseURL ?? ""
            }
            if tokenUsageEnabledInputs[provider.id] == nil {
                tokenUsageEnabledInputs[provider.id] = relayViewConfig?.tokenUsageEnabled ?? true
            }
            if accountEnabledInputs[provider.id] == nil {
                accountEnabledInputs[provider.id] = relayViewConfig?.accountBalance?.enabled ?? false
            }
            if authHeaderInputs[provider.id] == nil {
                authHeaderInputs[provider.id] = relayViewConfig?.accountBalance?.authHeader ?? "Authorization"
            }
            if authSchemeInputs[provider.id] == nil {
                authSchemeInputs[provider.id] = relayViewConfig?.accountBalance?.authScheme ?? "Bearer"
            }
            if userIDInputs[provider.id] == nil {
                userIDInputs[provider.id] = relayViewConfig?.accountBalance?.userID
                    ?? defaultManifest.balanceRequest.userID
                    ?? ""
            }
            if userHeaderInputs[provider.id] == nil {
                userHeaderInputs[provider.id] = relayViewConfig?.accountBalance?.userIDHeader ?? "New-Api-User"
            }
            if endpointPathInputs[provider.id] == nil {
                endpointPathInputs[provider.id] = relayViewConfig?.accountBalance?.endpointPath ?? "/api/user/self"
            }
            if remainingPathInputs[provider.id] == nil {
                remainingPathInputs[provider.id] = relayViewConfig?.accountBalance?.remainingJSONPath ?? "data.quota"
            }
            if usedPathInputs[provider.id] == nil {
                usedPathInputs[provider.id] = relayViewConfig?.accountBalance?.usedJSONPath ?? ""
            }
            if limitPathInputs[provider.id] == nil {
                limitPathInputs[provider.id] = relayViewConfig?.accountBalance?.limitJSONPath ?? ""
            }
            if successPathInputs[provider.id] == nil {
                successPathInputs[provider.id] = relayViewConfig?.accountBalance?.successJSONPath ?? ""
            }
            if unitInputs[provider.id] == nil {
                unitInputs[provider.id] = relayViewConfig?.accountBalance?.unit ?? "quota"
            }
            if relayCredentialModeInputs[provider.id] == nil {
                relayCredentialModeInputs[provider.id] = provider.relayConfig?.balanceCredentialMode ?? .manualPreferred
            }
        }

        for provider in viewModel.config.providers where provider.family == .official {
            if officialSourceModeInputs[provider.id] == nil {
                officialSourceModeInputs[provider.id] = provider.officialConfig?.sourceMode ?? .auto
            }
            if officialWebModeInputs[provider.id] == nil {
                officialWebModeInputs[provider.id] = provider.officialConfig?.webMode ?? .disabled
            }
            if officialQuotaDisplayModeInputs[provider.id] == nil {
                officialQuotaDisplayModeInputs[provider.id] = provider.officialConfig?.quotaDisplayMode
                    ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode
            }
        }

        for profile in viewModel.codexProfilesForSettings() {
            let key = profile.slotID.rawValue
            if codexProfileJSONInputs[key] == nil {
                codexProfileJSONInputs[key] = profile.authJSON
            }
        }
    }

    @ViewBuilder
    private func labeledToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .tint(.green)
            Spacer(minLength: 8)
            toggleStateBadge(isOn: isOn.wrappedValue)
        }
    }

    @ViewBuilder
    private func toggleStateBadge(isOn: Bool) -> some View {
        Text(isOn ? viewModel.text(.toggleOn) : viewModel.text(.toggleOff))
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((isOn ? Color.green : Color.red).opacity(0.14))
            )
    }

    private enum RelayCredentialTemplateKind {
        case cookie
        case bearer
        case custom(header: String, scheme: String)
    }

    private struct RelayCredentialTemplate {
        let kind: RelayCredentialTemplateKind
        let placeholder: String
        let hint: String
    }

    private func relayCredentialTemplate(authHeader: String?, authScheme: String?) -> RelayCredentialTemplate {
        let language = viewModel.language
        let header = (authHeader ?? "Authorization").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = (authScheme ?? "Bearer").trimmingCharacters(in: .whitespacesAndNewlines)

        if header.caseInsensitiveCompare("Cookie") == .orderedSame {
            if language == .zhHans {
                return RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "粘贴完整 Cookie Header，例如 session=...; token=...",
                    hint: "这里填写完整 Cookie Header，不是单个字段。"
                )
            } else {
                return RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "Paste the full Cookie header, for example session=...; token=...",
                    hint: "Paste the full Cookie header, not a single cookie field."
                )
            }
        }

        if header.caseInsensitiveCompare("Authorization") == .orderedSame &&
            (scheme.isEmpty || scheme.caseInsensitiveCompare("Bearer") == .orderedSame) {
            if language == .zhHans {
                return RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "粘贴 Bearer Token，例如 Bearer eyJ... 或 eyJ...",
                    hint: "这里填写 Authorization Bearer 值，带或不带 Bearer 前缀都可以。"
                )
            } else {
                return RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "Paste the bearer token, for example Bearer eyJ... or eyJ...",
                    hint: "Paste the Authorization bearer value, with or without the Bearer prefix."
                )
            }
        }

        let normalizedHeader = header.isEmpty ? "Authorization" : header
        let normalizedScheme = scheme
        if language == .zhHans {
            return RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "粘贴 \(normalizedHeader) 的值：\(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "这里填写站点要求的自定义请求头值。"
            )
        } else {
            return RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "Paste the \(normalizedHeader) value: \(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "Paste the custom header value required by this site."
            )
        }
    }

    private func relayCredentialFieldName(
        isAccount: Bool,
        templateKind: RelayCredentialTemplateKind
    ) -> String {
        let language = viewModel.language
        switch templateKind {
        case .cookie:
            return "Cookie"
        case .bearer:
            if language == .zhHans {
                return isAccount ? "Access Token" : "API Key / Token"
            } else {
                return isAccount ? "Access Token" : "API Key / Token"
            }
        case .custom(let header, _):
            if language == .zhHans {
                return "\(header) 值"
            } else {
                return "\(header) value"
            }
        }
    }

    private func relayCredentialSectionTitle(
        isAccount: Bool,
        templateKind: RelayCredentialTemplateKind
    ) -> String {
        let fieldName = relayCredentialFieldName(isAccount: isAccount, templateKind: templateKind)
        if viewModel.language == .zhHans {
            return isAccount ? "余额 \(fieldName)" : "配额 \(fieldName)"
        } else {
            return isAccount ? "Balance \(fieldName)" : "Quota \(fieldName)"
        }
    }

    private func relayCredentialSaveLabel(templateKind: RelayCredentialTemplateKind) -> String {
        switch templateKind {
        case .cookie:
            return viewModel.language == .zhHans ? "保存 Cookie" : "Save Cookie"
        case .bearer:
            return viewModel.language == .zhHans ? "保存 Access Token" : "Save Access Token"
        case .custom(let header, _):
            return viewModel.language == .zhHans ? "保存 \(header)" : "Save \(header)"
        }
    }

    private func relayCredentialLookupHint(templateKind: RelayCredentialTemplateKind) -> String {
        switch templateKind {
        case .cookie:
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制完整 Cookie。"
                : "Open the matching request in browser DevTools Network and copy the full Cookie value from Request Headers."
        case .bearer:
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 Authorization 的 Bearer 值。"
                : "Open the matching request in browser DevTools Network and copy the Authorization bearer value from Request Headers."
        case .custom(let header, _):
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 \(header) 的值。"
                : "Open the matching request in browser DevTools Network and copy the \(header) value from Request Headers."
        }
    }

    private func relayCredentialModeLabel(_ mode: RelayCredentialMode) -> String {
        switch mode {
        case .manualPreferred:
            return viewModel.text(.credentialModeManualPreferred)
        case .browserPreferred:
            return viewModel.text(.credentialModeBrowserPreferred)
        case .browserOnly:
            return viewModel.text(.credentialModeBrowserOnly)
        }
    }

    private func formattedSettingsAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    @ViewBuilder
    private func relayDiagnosticSection(_ result: RelayDiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(result.success ? viewModel.text(.connectionSuccess) : viewModel.text(.connectionFailed))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.success ? .green : Color(hex: 0xD83E3E))

                Text(relayFetchHealthLabel(result.fetchHealth))
                    .font(.caption)
                    .foregroundStyle(relayFetchHealthColor(result.fetchHealth))
            }

            Text("\(viewModel.text(.matchedAdapter)): \(result.resolvedAdapterID)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let authSource = result.resolvedAuthSource, !authSource.isEmpty {
                Text("\(viewModel.text(.authSourceLabel)): \(authSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let preview = result.snapshotPreview {
                Text(relayDiagnosticPreviewText(preview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func relayRuntimeStatusSection(_ provider: ProviderDescriptor, selectedTemplate: RelayAdapterManifest) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let authSource = viewModel.relayAuthSource(for: provider.id)
        let fetchHealth = viewModel.relayFetchHealth(for: provider.id)
        let freshness = viewModel.relayValueFreshness(for: provider.id)
        let error = viewModel.errors[provider.id]

        VStack(alignment: .leading, spacing: 6) {
            Text(relayRuntimeStatusTitle())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(viewModel.text(.matchedAdapter)): \(selectedTemplate.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let authSource, !authSource.isEmpty {
                Text("\(viewModel.text(.authSourceLabel)): \(authSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let fetchHealth {
                HStack(spacing: 8) {
                    Text(relayFetchHealthTitle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(relayFetchHealthLabel(fetchHealth))
                        .font(.caption)
                        .foregroundStyle(relayFetchHealthColor(fetchHealth))
                }
            }

            if let freshness {
                HStack(spacing: 8) {
                    Text(relayFreshnessTitle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(relayValueFreshnessLabel(freshness))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot {
                Text("\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: snapshot.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func relayFetchHealthLabel(_ health: FetchHealth) -> String {
        switch (viewModel.language, health) {
        case (.zhHans, .ok):
            return "接口正常"
        case (.zhHans, .authExpired):
            return "认证失效"
        case (.zhHans, .rateLimited):
            return "接口限流"
        case (.zhHans, .endpointMisconfigured):
            return "接口配置异常"
        case (.zhHans, .unreachable):
            return "站点不可达"
        case (.en, .ok):
            return "Live"
        case (.en, .authExpired):
            return "Auth expired"
        case (.en, .rateLimited):
            return "Rate limited"
        case (.en, .endpointMisconfigured):
            return "Config issue"
        case (.en, .unreachable):
            return "Unreachable"
        }
    }

    private func relayFetchHealthColor(_ health: FetchHealth) -> Color {
        switch health {
        case .ok:
            return .green
        case .rateLimited:
            return Color(hex: 0xD87E3E)
        case .authExpired, .endpointMisconfigured, .unreachable:
            return Color(hex: 0xD83E3E)
        }
    }

    private func relayValueFreshnessLabel(_ freshness: ValueFreshness) -> String {
        switch (viewModel.language, freshness) {
        case (.zhHans, .live):
            return "实时值"
        case (.zhHans, .cachedFallback):
            return "缓存回退"
        case (.zhHans, .empty):
            return "暂无可用值"
        case (.en, .live):
            return "Live"
        case (.en, .cachedFallback):
            return "Cached fallback"
        case (.en, .empty):
            return "No usable value"
        }
    }

    private func relayRuntimeStatusTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "当前连接状态"
        case .en:
            return "Current connection status"
        }
    }

    private func relayFetchHealthTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "抓取状态"
        case .en:
            return "Fetch health"
        }
    }

    private func relayFreshnessTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "数据状态"
        case .en:
            return "Value state"
        }
    }

    private func relayDiagnosticPreviewText(_ preview: RelayDiagnosticSnapshotPreview) -> String {
        let unit = preview.unit.isEmpty ? "" : " \(preview.unit)"
        let remaining = preview.remaining.map { formattedSettingsAmount($0) } ?? "-"
        let used = preview.used.map { formattedSettingsAmount($0) } ?? "-"
        let limit = preview.limit.map { formattedSettingsAmount($0) } ?? "-"
        if viewModel.language == .zhHans {
            return "预览: 剩余 \(remaining)\(unit) / 已用 \(used)\(unit) / 上限 \(limit)\(unit)"
        }
        return "Preview: remaining \(remaining)\(unit) / used \(used)\(unit) / limit \(limit)\(unit)"
    }

    private func settingsElapsedText(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        switch viewModel.language {
        case .zhHans:
            if seconds < 60 { return "\(seconds) 秒前" }
            if seconds < 3600 { return "\(seconds / 60) 分钟前" }
            if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
            return "\(seconds / 86_400) 天前"
        case .en:
            if seconds < 60 { return "\(seconds)s ago" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86_400 { return "\(seconds / 3600)h ago" }
            return "\(seconds / 86_400)d ago"
        }
    }

}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

private extension View {
    func relayProminentInput() -> some View {
        self
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.2)
            )
            .shadow(color: Color.accentColor.opacity(0.16), radius: 8, y: 2)
    }
}
