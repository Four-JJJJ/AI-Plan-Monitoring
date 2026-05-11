import AppKit
import OhMyUsageApplication
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    var onDone: (() -> Void)? = nil
    private let settingsClockController = SettingsClockController()

    @State var relayEditorDraft = RelayProviderEditorDraft()
    @State var relayTestResultGeneration = 0
    @State var officialEditorDraft = OfficialProviderEditorDraft()
    @State var profileDraftState = SettingsProfileDraftState()
    @State var dialogState = SettingsDialogState()
    @State var runtimeState = SettingsRuntimeState()
    @FocusState var focusedThresholdProviderID: String?

    @State var newRelaySiteDraft = NewRelaySiteDraftState()
    @State var navigationState = SettingsNavigationState()
    @State var providerReorderLocalMouseUpMonitor: Any?
    @State var providerReorderGlobalMouseUpMonitor: Any?
    @State var showingRelayNewSiteDraft = false
    @State var editingNewRelaySiteName = false
    @State var editingRelayProviderID: String?
    @State var relayTitleEditOriginalValue = ""
    @FocusState var focusedRelayTitleEditorID: String?

    // MARK: - 设置页视觉 Token（改这里可全局影响样式）
    // 整个设置页外层背景。
    var panelBackground: Color {
        settingsUsesLightAppearance ? Color(hex: 0xF3F4F6) : Color(hex: 0x232323)
    }

    // “通用设置”主内容滚动区域底色。
    var cardBackground: Color {
        settingsUsesLightAppearance ? Color(hex: 0xFFFFFF) : Color.black
    }

    // 通用描边色：用于模型面板、卡片边框等。
    var outlineColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.12)
    }
    // 内层卡片/黑色内容容器圆角。
    let cardCornerRadius: CGFloat = 12
    let settingsShellCornerRadius: CGFloat = 20
    let settingsSidebarCornerRadius: CGFloat = 20
    let settingsSectionCornerRadius: CGFloat = 12
    var settingsShellStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    var settingsSidebarFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.78) : Color.white.opacity(0.03)
    }

    var settingsSectionFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.035) : Color.black.opacity(0.22)
    }
    let settingsAccentBlue = Color(hex: 0x168DFF)
    let settingsAccentGreen = Color(hex: 0x31D158)
    let settingsAccentPurple = Color(hex: 0xC93BFF)
    let settingsAccentCyan = Color(hex: 0x12D6F3)
    // 分割线颜色。
    var dividerColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.15)
    }
    // 模型设置详情项垂直间距（设计稿统一 24px）。
    let modelSettingsItemSpacing: CGFloat = 24
    // 本地扫描区内部内容项间距（设计稿统一 12px）。
    let localDiscoveryItemSpacing: CGFloat = 12

    // 主要标题字号（例如“关于”页标题）。
    let settingsTitleFont = Font.system(size: 16, weight: .semibold)
    // 正文描述字号（12 Regular）。
    let settingsBodyFont = Font.system(size: 12, weight: .regular)
    // 标签标题字号（12 Semibold）。
    let settingsLabelFont = Font.system(size: 12, weight: .semibold)
    // 提示文字字号（10 Regular）。
    let settingsHintFont = Font.system(size: 10, weight: .regular)
    // 多行正文目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    let settingsBodyMultilineSpacing: CGFloat = 4
    // 多行提示文字目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    let settingsHintMultilineSpacing: CGFloat = 3

    // 标题文字颜色。
    var settingsTitleColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.80)
    }

    // 常规正文颜色。
    var settingsBodyColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.78) : Color.white.opacity(0.80)
    }

    // 次级提示色。
    var settingsHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.56) : Color.white.opacity(0.55)
    }

    // 更弱提示色，用于“检查失败”等弱错误提示。
    var settingsMutedHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.40) : Color.white.opacity(0.40)
    }
    // 输入框填充色。
    var settingsInputFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.06) : Color.white.opacity(0.15)
    }

    // 输入框占位色。
    var settingsInputPlaceholderColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.35) : Color.white.opacity(0.30)
    }
    var settingsSubtlePanelFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.035) : Color.white.opacity(0.03)
    }

    var settingsSubtlePanelStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.06)
    }

    var settingsSelectedRowFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.30)
    }

    var settingsSelectedRowStrokeColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.52) : Color.white.opacity(0.80)
    }

    var settingsRowStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.30)
    }

    var settingsDropIndicatorColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.90) : Color.white.opacity(0.90)
    }

    var settingsControlFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.05) : Color(hex: 0x2A2B2F)
    }

    var settingsControlStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    var settingsPopoverFillColor: Color {
        settingsUsesLightAppearance ? Color.white : Color(hex: 0x1F2024)
    }

    var settingsPopoverSelectedFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.12)
    }

    var settingsQuotaTrackColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.30)
    }

    var settingsTrendPrimaryColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.78) : Color.white.opacity(0.62)
    }

    var settingsTrendMutedColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.22)
    }

    var settingsSliderTintColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue : Color.white.opacity(0.80)
    }
    // API 余额页右侧配置项统一标签列宽与控件间距。
    var thirdPartyConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 56 : 112
    }

    var settingsNestedConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 24 : 56
    }

    let thirdPartyConfigLabelSpacing: CGFloat = 16

    var thirdPartyConfigControlWidth: CGFloat {
        534 - thirdPartyConfigLabelWidth - thirdPartyConfigLabelSpacing
    }

    var thirdPartyConfigSliderWidth: CGFloat {
        max(280, thirdPartyConfigControlWidth - 96)
    }

    var officialConfigLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 60 : 112
    }

    var settingsGeneralLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 48 : 124
    }

    var settingsGeneralHintLeadingPadding: CGFloat {
        settingsGeneralLabelWidth + 16
    }

    var settingsMenuBarLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 60 : 160
    }

    var settingsMenuBarHintLeadingPadding: CGFloat {
        settingsMenuBarLabelWidth + 16
    }

    var settingsDetailLabelWidth: CGFloat {
        viewModel.language == .zhHans ? 80 : 160
    }

    struct RelayTemplatePreset: Identifiable {
        let manifest: RelayAdapterManifest
        let suggestedBaseURL: String?

        var id: String { manifest.id }
        var displayName: String { manifest.displayName }
    }

    struct CodexQuotaMetricDisplay: Identifiable {
        var id: String
        var title: String
        var valueText: String
        var resetText: String
        var percent: Double?
        var barColor: Color
        var isAvailable: Bool = true
        var healthPercent: Double? = nil
        var isBlockedByDepletedQuota: Bool = false
    }

    enum OfficialMonitoringHealthStatus: Equatable {
        case unknown
        case authError
        case configError
        case rateLimited
        case disconnected
        case sufficient
        case tight
        case exhausted
    }

    nonisolated static func resolvedOfficialMonitoringProvider(
        type: ProviderType,
        providers: [ProviderDescriptor]
    ) -> ProviderDescriptor {
        SettingsQuotaPresenter.resolvedOfficialMonitoringProvider(type: type, providers: providers)
    }

    nonisolated static func quotaMetricPercents(
        for window: UsageQuotaWindow,
        displaysUsedQuota: Bool
    ) -> (displayPercent: Double, healthPercent: Double) {
        SettingsQuotaPresenter.quotaMetricPercents(for: window, displaysUsedQuota: displaysUsedQuota)
    }

    nonisolated static func officialMonitoringHealthStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double]
    ) -> OfficialMonitoringHealthStatus {
        switch SettingsQuotaPresenter.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        ) {
        case .unknown:
            return .unknown
        case .authError:
            return .authError
        case .configError:
            return .configError
        case .rateLimited:
            return .rateLimited
        case .disconnected:
            return .disconnected
        case .sufficient:
            return .sufficient
        case .tight:
            return .tight
        case .exhausted:
            return .exhausted
        }
    }

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

    var theme: SettingsTheme {
        SettingsTheme(
            panelBackground: panelBackground,
            cardBackground: cardBackground,
            shellStrokeColor: settingsShellStrokeColor,
            sidebarFillColor: settingsSidebarFillColor,
            sectionFillColor: settingsSectionFillColor,
            subtlePanelFillColor: settingsSubtlePanelFillColor,
            subtlePanelStrokeColor: settingsSubtlePanelStrokeColor,
            sectionCornerRadius: settingsSectionCornerRadius,
            shellCornerRadius: settingsShellCornerRadius,
            sidebarCornerRadius: settingsSidebarCornerRadius,
            accentColor: settingsAccentBlue,
            dividerColor: dividerColor,
            titleColor: settingsTitleColor,
            hintColor: settingsHintColor,
            mutedHintColor: settingsMutedHintColor
        )
    }

    private func handleSettingsAppear() {
        clearRelayTestResults()
        seedInputsFromConfig()
        syncSelection()
        resetProviderReorderState()
        viewModel.refreshPermissionStatusesNow()
        restartSettingsClockIfNeeded()
    }

    private var overlayPresentation: SettingsOverlayPresentation {
        SettingsOverlayPresenter.presentation(
            dialogState: dialogState,
            hasOAuthImportDialog: showsOAuthImportDialog,
            language: viewModel.language,
            text: { viewModel.text($0) }
        )
    }

    private var providerEnabledStateKeys: [String] {
        viewModel.config.providers.map { "\($0.id):\($0.enabled)" }
    }

    private func clearRelayTestResults() {
        relayTestResultGeneration += 1
        guard !relayEditorDraft.relayTestResult.isEmpty else { return }
        relayEditorDraft.relayTestResult.removeAll()
    }

    @ViewBuilder
    private var settingsOverlayContent: some View {
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

    private var settingsMainContent: some View {
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

    private var settingsColorScheme: ColorScheme {
        .dark
    }

    var settingsUsesLightAppearance: Bool {
        false
    }

    @ViewBuilder
    private var settingsSidebarIdentityIcon: some View {
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

    private var settingsUpdateActionDisabled: Bool {
        viewModel.updateCheckInFlight ||
        viewModel.updateDownloadInFlight ||
        viewModel.updateInstallBufferingInFlight ||
        viewModel.updateInstallationInFlight
    }

    private var settingsShowsUpdateButton: Bool {
        switch viewModel.settingsUpdateDisplayState.kind {
        case .updateAvailable, .downloading, .installBuffering:
            return true
        case .idle, .checkFailed, .upToDate, .failed:
            return false
        }
    }

    private var settingsHeaderPresentation: SettingsHeaderPresentation {
        SettingsWorkspacePresenter.headerPresentation(
            selectedTab: navigationState.selectedSettingsTab,
            localizedText: { viewModel.localizedText($0, $1) },
            generalTabTitle: viewModel.text(.settingsGeneralTab)
        )
    }

    private var settingsSidebarPresentation: SettingsWorkspaceSidebarPresentation {
        var presentation = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: { viewModel.localizedText($0, $1) },
            generalTabTitle: viewModel.text(.settingsGeneralTab)
        )
        presentation.updateButtonTitle = viewModel.updateActionTitle
        return presentation
    }

    @ViewBuilder
    private var settingsContentPane: some View {
        SettingsTabContentView(selectedTab: navigationState.selectedSettingsTab) {
            settingsGeneralDetailPage
        } general: {
            settingsGeneralDetailPage
        } menuBar: {
            settingsMenuBarDetailPage
        } permissions: {
            settingsGeneralDetailPage
        } localData: {
            settingsGeneralDetailPage
        } officialProviders: {
            settingsOfficialSubscriptionsPage
        } customProviders: {
            settingsRelayProvidersPage
        }
    }

    private var settingsGeneralDetailPage: some View {
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

    private var settingsMenuBarDetailPage: some View {
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

    private var settingsOfficialSubscriptionsPage: some View {
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

    private var settingsRelayProvidersPage: some View {
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

    private var overviewDashboardContent: some View {
        SettingsOverviewView(items: overviewCardItems, theme: theme) {
            officialUsageTrendsOverviewSection
        }
    }

    @ViewBuilder
    private func providerSidebarContent(for group: ProviderGroup) -> some View {
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
    private var officialUsageTrendsOverviewSection: some View {
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

    private func settingsSectionPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .fill(settingsSectionFillColor)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
    }

    private var overviewCardItems: [SettingsOverviewCardItem] {
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

    private func overviewAccentColor(_ accent: SettingsOverviewAccent) -> Color {
        switch accent {
        case .blue:
            return settingsAccentBlue
        case .green:
            return settingsAccentGreen
        case .purple:
            return settingsAccentPurple
        case .cyan:
            return settingsAccentCyan
        }
    }

    private var settingsOverviewCardPresentations: [SettingsOverviewCardPresentation] {
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

    private var officialProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .official }.count
    }

    private var officialUsageTrendOverviewProviders: [ProviderDescriptor] {
        SettingsOverviewPresenter.officialUsageTrendProviders(
            providers: viewModel.config.providers,
            shouldShow: { shouldShowOfficialLocalTrendCard(for: $0) }
        )
    }

    private var thirdPartyProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .thirdParty }.count
    }

    private var lastRefreshSummaryText: String {
        SettingsOverviewPresenter.lastRefreshText(
            lastUpdatedAt: viewModel.lastUpdatedAt,
            now: runtimeState.settingsNow,
            language: viewModel.language,
            localizedText: { viewModel.localizedText($0, $1) }
        )
    }

    private var showsResetDataDialog: Bool {
        dialogState.permissionPrompt == .resetLocalData
    }

    private var showsCodexProfileEditorDialog: Bool {
        dialogState.codexProfileEditor != nil
    }

    private var showsClaudeProfileEditorDialog: Bool {
        dialogState.claudeProfileEditor != nil
    }

    private var showsNewAPISiteDialog: Bool {
        dialogState.isNewAPISiteDialogPresented
    }

    var activeOAuthImportDialogState: OAuthImportState? {
        if let codex = viewModel.oauthImportState(for: .codex), codex.isRunning {
            return codex
        }
        if let claude = viewModel.oauthImportState(for: .claude), claude.isRunning {
            return claude
        }
        return nil
    }

    private var showsOAuthImportDialog: Bool {
        activeOAuthImportDialogState != nil
    }

    private var resetDataConfirmDialog: some View {
        SettingsResetDialogView(
            title: overlayPresentation.resetDialog.title,
            description: overlayPresentation.resetDialog.description,
            cancelTitle: overlayPresentation.resetDialog.cancelTitle,
            confirmTitle: overlayPresentation.resetDialog.confirmTitle,
            onCancel: {
                dialogState.permissionPrompt = nil
            },
            onConfirm: {
                handlePermissionPrompt()
            }
        )
    }

    @ViewBuilder
    func settingsActionButton(
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
    func settingsElapsedText(from date: Date) -> String {
        SettingsOverviewPresenter.elapsedText(
            from: date,
            now: runtimeState.settingsNow,
            language: viewModel.language
        )
    }

    private func restartSettingsClockIfNeeded() {
        settingsClockController.restartClockIfNeeded(
            isVisible: viewModel.settingsWindowVisible,
            existingTask: &runtimeState.settingsClockTask
        ) { referenceDate in
            tickSettingsClock(referenceDate: referenceDate)
        }
    }

    private func stopSettingsClock() {
        settingsClockController.stopClock(existingTask: &runtimeState.settingsClockTask)
    }

    private func tickSettingsClock(referenceDate: Date = Date()) {
        settingsClockController.tick(referenceDate: referenceDate) { resolvedDate in
            runtimeState.settingsNow = resolvedDate
        }
    }

}

#Preview("Settings / General") {
    SettingsView(viewModel: {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsagePreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vm = AppViewModel(
            configurationRepository: AppConfigurationRepository(
                store: ConfigStore(baseDirectoryURL: root)
            )
        )
        vm.setLanguage(.zhHans)
        return vm
    }())
    .frame(width: 1000, height: 720)
    .preferredColorScheme(.dark)
}
