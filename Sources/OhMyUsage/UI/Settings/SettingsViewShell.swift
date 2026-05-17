import AppKit
import SwiftUI

extension SettingsView {
    var body: some View {
        SettingsRootView(
            colorScheme: settingsColorScheme,
            showsModalOverlay: overlayPresentation.showsModalOverlay
        ) {
            settingsMainContent
        } overlay: {
            settingsOverlayContent
        }
        .onAppear {
            handleSettingsAppear()
        }
        .onDisappear {
            clearRelayTestResults()
            stopSettingsClock()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard viewModel.settingsWindowVisible else { return }
            viewModel.refreshPermissionStatusesNow()
        }
        .onChange(of: viewModel.settingsWindowVisible) { _, _ in
            clearRelayTestResults()
            restartSettingsClockIfNeeded()
        }
        .onChange(of: providerEnabledStateKeys) { _, _ in
            clearRelayTestResults()
        }
        .onChange(of: viewModel.config.providers.map(\.id)) { _, _ in
            clearRelayTestResults()
            seedInputsFromConfig()
            resetProviderReorderState()
            syncSelection()
        }
        .onChange(of: navigationState.selectedGroup) { _, _ in
            clearRelayTestResults()
            resetProviderReorderState()
            syncSelection()
        }
        .onChange(of: navigationState.selectedSettingsTab) { _, newValue in
            clearRelayTestResults()
            navigationState.selectTab(newValue)
            if newValue.isProviderSection {
                viewModel.refreshSettingsProfileState()
            }
        }
        .onChange(of: navigationState.selectedProviderID) { _, _ in
            clearRelayTestResults()
        }
        .alert(
            viewModel.text(.codexDeleteProfileTitle),
            isPresented: Binding(
                get: { dialogState.codexProfilePendingDelete != nil },
                set: { newValue in
                    if !newValue {
                        dialogState.codexProfilePendingDelete = nil
                    }
                }
            ),
            presenting: dialogState.codexProfilePendingDelete
        ) { slotID in
            Button(viewModel.text(.codexDeleteConfirm), role: .destructive) {
                let key = slotID.rawValue
                viewModel.removeCodexProfile(slotID: slotID)
                profileDraftState.clearCodexState(forKey: key)
                dialogState.codexProfilePendingDelete = nil
            }
            Button(viewModel.text(.done), role: .cancel) {
                dialogState.codexProfilePendingDelete = nil
            }
        } message: { _ in
            Text(viewModel.text(.codexDeleteProfileMessage))
        }
        .alert(
            viewModel.localizedText("删除 Claude 账号", "Delete Claude account"),
            isPresented: Binding(
                get: { dialogState.claudeProfilePendingDelete != nil },
                set: { newValue in
                    if !newValue {
                        dialogState.claudeProfilePendingDelete = nil
                    }
                }
            ),
            presenting: dialogState.claudeProfilePendingDelete
        ) { slotID in
            Button(viewModel.localizedText("确认删除", "Delete"), role: .destructive) {
                let key = slotID.rawValue
                viewModel.removeClaudeProfile(slotID: slotID)
                profileDraftState.clearClaudeState(forKey: key)
                dialogState.claudeProfilePendingDelete = nil
            }
            Button(viewModel.text(.done), role: .cancel) {
                dialogState.claudeProfilePendingDelete = nil
            }
        } message: { _ in
            Text(viewModel.localizedText("删除后将移除该账号保存的凭证与目录配置，本机当前 Claude 登录态不会立刻受影响。", "This removes the saved credentials and directory binding for the account. It does not immediately sign the current local Claude session out."))
        }
        .confirmationDialog(
            permissionAlertTitle,
            isPresented: Binding(
                get: { dialogState.permissionPrompt != nil && dialogState.permissionPrompt != .resetLocalData },
                set: { newValue in
                    if !newValue {
                        if dialogState.permissionPrompt != .resetLocalData {
                            dialogState.permissionPrompt = nil
                        }
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(viewModel.text(.permissionContinue)) {
                handlePermissionPrompt()
            }
            Button(viewModel.text(.permissionCancel), role: .cancel) {
                dialogState.permissionPrompt = nil
            }
        } message: {
            Text(permissionAlertMessage)
        }
    }

    func handleSettingsAppear() {
        clearRelayTestResults()
        seedInputsFromConfig()
        syncSelection()
        resetProviderReorderState()
        viewModel.refreshPermissionStatusesNow()
        restartSettingsClockIfNeeded()
    }

    var providerEnabledStateKeys: [String] {
        viewModel.config.providers.map { "\($0.id):\($0.enabled)" }
    }

    func clearRelayTestResults() {
        relayTestResultGeneration += 1
        guard !relayEditorDraft.relayTestResult.isEmpty else { return }
        relayEditorDraft.relayTestResult.removeAll()
    }

    @ViewBuilder
    var settingsOverlayContent: some View {
        switch overlayPresentation.activeKind {
        case .resetData:
            resetDataConfirmDialog
        case .codexProfileEditor:
            codexProfileEditorDialog
        case .claudeProfileEditor:
            claudeProfileEditorDialog
        case .oauthImport:
            oauthImportProgressDialog
        case .newAPISite:
            newAPISiteDialog
        case .none:
            EmptyView()
        }
    }

    var settingsMainContent: some View {
        SettingsShellView(
            background: theme.panelBackground,
            detailFillColor: Color.black.opacity(0.40),
            detailStrokeColor: Color.white.opacity(0.08),
            sidebar: {
                SettingsWorkspaceSidebarView(
                    presentation: settingsSidebarPresentation,
                    selectedTab: navigationState.selectedSettingsTab,
                    currentVersion: viewModel.currentAppVersion,
                    lastRefreshText: lastRefreshSummaryText,
                    updateDisabled: settingsUpdateActionDisabled,
                    showsUpdateButton: settingsShowsUpdateButton,
                    theme: theme,
                    onSelectTab: { navigationState.selectTab($0) },
                    onUpdateAction: { viewModel.openLatestReleaseDownload() },
                    onCheckUpdates: { viewModel.checkForAppUpdate(force: true) },
                    onOpenGitHub: { viewModel.openRepositoryPage() }
                ) {
                    settingsSidebarIdentityIcon
                }
            },
            header: {
                EmptyView()
            },
            content: {
                settingsContentPane
            }
        )
    }

    @ViewBuilder
    var settingsSidebarIdentityIcon: some View {
        if let image = AppIconImageProvider.image(size: 36) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(settingsAccentBlue.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(settingsAccentBlue)
                )
        }
    }

    var settingsUpdateActionDisabled: Bool {
        viewModel.updateCheckInFlight ||
        viewModel.updateDownloadInFlight ||
        viewModel.updateInstallBufferingInFlight ||
        viewModel.updateInstallationInFlight
    }

    var settingsShowsUpdateButton: Bool {
        switch viewModel.settingsUpdateDisplayState.kind {
        case .updateAvailable, .downloading, .installBuffering:
            return true
        case .idle, .checkFailed, .upToDate, .failed:
            return false
        }
    }

    var settingsHeaderPresentation: SettingsHeaderPresentation {
        SettingsWorkspacePresenter.headerPresentation(
            selectedTab: navigationState.selectedSettingsTab,
            localizedText: { viewModel.localizedText($0, $1) },
            generalTabTitle: viewModel.text(.settingsGeneralTab)
        )
    }

    var settingsSidebarPresentation: SettingsWorkspaceSidebarPresentation {
        var presentation = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: { viewModel.localizedText($0, $1) },
            generalTabTitle: viewModel.text(.settingsGeneralTab)
        )
        presentation.updateButtonTitle = viewModel.updateActionTitle
        return presentation
    }

    @ViewBuilder
    var settingsContentPane: some View {
        SettingsTabContentView(selectedTab: navigationState.selectedSettingsTab) {
            settingsGeneralDetailPage
        } general: {
            settingsGeneralDetailPage
        } menuBar: {
            settingsMenuBarDetailPage
        } usageAnalytics: {
            UsageAnalyticsSettingsView(viewModel: viewModel, theme: theme)
        } permissions: {
            settingsGeneralDetailPage
        } localData: {
            settingsGeneralDetailPage
        } officialProviders: {
            settingsOfficialSubscriptionsPage
        } customProviders: {
            settingsRelayProvidersPage
        } donate: {
            SettingsDonateView(
                message: viewModel.localizedText(
                    "如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护",
                    "If oh-myusage has helped you, you can buy me a coffee or support continued maintenance."
                ),
                alipayAccessibilityLabel: viewModel.localizedText("支付宝赞赏二维码", "Alipay donation QR code"),
                wechatAccessibilityLabel: viewModel.localizedText("微信赞赏二维码", "WeChat donation QR code")
            )
        }
    }

    var settingsGeneralDetailPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appBehaviorSection

                dividerLine

                permissionAccessSection

                dividerLine

                localDataManagementSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var settingsMenuBarDetailPage: some View {
        ScrollView {
            menuBarPreferencesSection
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var settingsOfficialSubscriptionsPage: some View {
        HStack(alignment: .top, spacing: 0) {
            officialSubscriptionsSidebar
                .frame(width: 188)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)

            officialSubscriptionsDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            navigationState.selectedGroup = .official
            syncSelection()
        }
    }

    var settingsRelayProvidersPage: some View {
        HStack(alignment: .top, spacing: 0) {
            relayProvidersSidebar
                .frame(width: 188)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)

            relayProvidersDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            navigationState.selectedGroup = .thirdParty
            syncSelection()
        }
    }

    var overviewDashboardContent: some View {
        SettingsOverviewView(items: overviewCardItems, theme: theme) {
            officialUsageTrendsOverviewSection
        }
    }

    @ViewBuilder
    func providerSidebarContent(for group: ProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(group == .official
                ? viewModel.localizedText("官方服务", "Official Services")
                : viewModel.localizedText("自定义接口", "Custom Endpoints"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(settingsTitleColor)

            Group {
                if group == .official {
                    officialSidebarContent
                } else {
                    thirdPartySidebarContent
                }
            }
        }
    }

    @ViewBuilder
    var officialUsageTrendsOverviewSection: some View {
        let providers = officialUsageTrendOverviewProviders

        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.localizedText("官方服务使用趋势", "Official Usage Trends"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(settingsTitleColor)

                    Text(viewModel.localizedText(
                        "仅汇总已启用的官方服务，本地趋势不等同于官方剩余额度。",
                        "Only enabled official services are shown. Local trends are not the same as official remaining quota."
                    ))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(providers) { provider in
                    settingsSectionPanel {
                        officialLocalTrendSection(
                            provider: provider,
                            snapshot: viewModel.snapshots[provider.id],
                            showsDivider: false,
                            title: SettingsOverviewPresenter.officialUsageTrendTitle(
                                displayName: sidebarDisplayName(for: provider),
                                language: viewModel.language
                            )
                        )
                    }
                }
            }
        }
    }

    var overviewCardItems: [SettingsOverviewCardItem] {
        settingsOverviewCardPresentations.map { presentation in
            SettingsOverviewCardItem(
                id: presentation.id,
                icon: presentation.icon,
                title: presentation.title,
                value: presentation.value,
                detail: presentation.detail,
                accent: overviewAccentColor(presentation.accent)
            )
        }
    }

    var settingsOverviewCardPresentations: [SettingsOverviewCardPresentation] {
        SettingsOverviewPresenter.cards(
            providers: viewModel.config.providers,
            statusBarMultiUsageEnabled: viewModel.statusBarMultiUsageEnabled,
            statusBarMultiProviderIDs: viewModel.config.statusBarMultiProviderIDs,
            statusBarProviderID: viewModel.config.statusBarProviderID,
            statusBarAppearanceMode: viewModel.statusBarAppearanceMode,
            statusBarDisplayStyle: viewModel.statusBarDisplayStyle,
            hasNotificationPermission: viewModel.hasNotificationPermission,
            secureStorageReady: viewModel.secureStorageReady,
            fullDiskAccessRelevant: viewModel.fullDiskAccessRelevant,
            fullDiskAccessRequested: viewModel.fullDiskAccessRequested,
            fullDiskAccessGranted: viewModel.fullDiskAccessGranted,
            localizedText: { viewModel.localizedText($0, $1) }
        )
    }

    var officialProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .official }.count
    }

    var officialUsageTrendOverviewProviders: [ProviderDescriptor] {
        SettingsOverviewPresenter.officialUsageTrendProviders(
            providers: viewModel.config.providers,
            shouldShow: { shouldShowOfficialLocalTrendCard(for: $0) }
        )
    }

    var thirdPartyProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .thirdParty }.count
    }

    var lastRefreshSummaryText: String {
        SettingsOverviewPresenter.lastRefreshText(
            lastUpdatedAt: viewModel.lastUpdatedAt,
            now: runtimeState.settingsNow,
            language: viewModel.language,
            localizedText: { viewModel.localizedText($0, $1) }
        )
    }
}
