import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct PermissionTileHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 取权限卡片中的最大高度，保证三张卡视觉等高。
        value = max(value, nextValue())
    }
}

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
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
    @State private var officialTraeValueDisplayModeInputs: [String: OfficialTraeValueDisplayMode] = [:]
    @State private var thirdPartyQuotaDisplayModeInputs: [String: OfficialQuotaDisplayMode] = [:]
    @State private var officialWorkspaceInputs: [String: String] = [:]
    @State private var officialCookieInputs: [String: String] = [:]
    @State private var codexProfileJSONInputs: [String: String] = [:]
    @State private var codexProfileNoteInputs: [String: String] = [:]
    @State private var codexProfileResult: [String: String] = [:]
    @State private var codexProfilePendingDelete: CodexSlotID?
    @State private var codexProfileEditor: CodexProfileEditorState?
    @State private var codexProfileEditorJSON = ""
    @State private var codexProfileEditorNote = ""
    @State private var claudeProfileJSONInputs: [String: String] = [:]
    @State private var claudeProfileConfigDirInputs: [String: String] = [:]
    @State private var claudeProfileNoteInputs: [String: String] = [:]
    @State private var claudeProfileResult: [String: String] = [:]
    @State private var claudeProfilePendingDelete: CodexSlotID?
    @State private var claudeProfileEditor: ClaudeProfileEditorState?
    @State private var claudeProfileEditorSource: ClaudeProfileSource = .configDir
    @State private var claudeProfileEditorConfigDir = ""
    @State private var claudeProfileEditorJSON = ""
    @State private var claudeProfileEditorNote = ""
    @State private var permissionPrompt: PermissionPrompt?
    @State private var permissionResultMessage: [String: String] = [:]
    @State private var permissionResultIsError: [String: Bool] = [:]
    @State private var autoDiscoveryScanning = false
    @State private var permissionTileHeight: CGFloat = 0
    @State private var relayTestResult: [String: RelayDiagnosticResult] = [:]
    @State private var relayAdvancedExpanded: [String: Bool] = [:]
    @State private var selectedRelayTemplateInputs: [String: String] = [:]
    @State private var relayCredentialModeInputs: [String: RelayCredentialMode] = [:]
    @State private var officialThresholdInputs: [String: String] = [:]
    @State private var isNewAPISiteDialogPresented = false
    @FocusState private var focusedThresholdProviderID: String?

    @State private var newProviderName = ""
    @State private var newProviderBaseURL = "https://"
    @State private var newProviderTemplateID = "generic-newapi"
    @State private var selectedRelayPresetID: String?
    @State private var selectedSettingsTab: SettingsTab = .overview
    @State private var selectedGroup: ProviderGroup = .official
    @State private var selectedProviderID: String?
    @State private var settingsNow = Date()
    @State private var draggingProviderID: String?
    @State private var reorderPreviewProviderIDs: [String]?
    @State private var dropTargetProviderID: String?
    @State private var dropTargetInsertAfter = false
    @State private var localUsageTrendSummaries: [String: LocalUsageSummary] = [:]
    @State private var localUsageTrendErrors: [String: String] = [:]
    @State private var localUsageTrendLoadingQueryKeys: Set<String> = []
    @State private var localUsageTrendScopes: [String: LocalUsageTrendScope] = [:]
    @State private var localUsageTrendSelectedAccountKeys: [String: String] = [:]
    @State private var localUsageTrendQueryLastRefreshedAt: [String: Date] = [:]
    @State private var localUsageTrendExpandedAccountSelectorProviderID: String?
    @State private var localUsageTrendHoveredHourlyPointID: String?
    @State private var localUsageTrendHoveredWeeklyPointID: String?
    @State private var settingsWallpaperLuminance: Double?

    private let settingsClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let localUsageTrendRefreshTTL: TimeInterval = 60

    // MARK: - 设置页视觉 Token（改这里可全局影响样式）
    // 整个设置页外层背景。
    private var panelBackground: Color {
        settingsUsesLightAppearance ? Color(hex: 0xF3F4F6).opacity(0.92) : Color(hex: 0x232323).opacity(0.92)
    }

    // “通用设置”主内容滚动区域底色。
    private var cardBackground: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.72) : Color.black.opacity(0.42)
    }

    // 通用描边色：用于模型面板、卡片边框等。
    private var outlineColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.30)
    }
    // 内层卡片/黑色内容容器圆角。
    private let cardCornerRadius: CGFloat = 8
    private let settingsShellCornerRadius: CGFloat = 20
    private let settingsSidebarCornerRadius: CGFloat = 20
    private let settingsSectionCornerRadius: CGFloat = 8
    private var settingsShellStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    private var settingsSidebarFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.58) : Color.white.opacity(0.055)
    }

    private var settingsSectionFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.48) : Color.white.opacity(0.055)
    }
    private let settingsAccentBlue = Color(hex: 0x168DFF)
    private let settingsAccentGreen = Color(hex: 0x31D158)
    private let settingsAccentPurple = Color(hex: 0xC93BFF)
    private let settingsAccentCyan = Color(hex: 0x12D6F3)
    // 分割线颜色。
    private var dividerColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.15)
    }
    // 模型设置详情项垂直间距（设计稿统一 24px）。
    private let modelSettingsItemSpacing: CGFloat = 24
    // 本地扫描区内部内容项间距（设计稿统一 12px）。
    private let localDiscoveryItemSpacing: CGFloat = 12

    // 主要标题字号（例如“关于”页标题）。
    private let settingsTitleFont = Font.system(size: 16, weight: .semibold)
    // 正文描述字号（12 Regular）。
    private let settingsBodyFont = Font.system(size: 12, weight: .regular)
    // 标签标题字号（12 Semibold）。
    private let settingsLabelFont = Font.system(size: 12, weight: .semibold)
    // 提示文字字号（10 Regular）。
    private let settingsHintFont = Font.system(size: 10, weight: .regular)
    // 多行正文目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    private let settingsBodyMultilineSpacing: CGFloat = 4
    // 多行提示文字目标行高（设计稿 150%）：系统默认行高基础上补齐的额外行距。
    private let settingsHintMultilineSpacing: CGFloat = 3

    // 标题文字颜色。
    private var settingsTitleColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.80)
    }

    // 常规正文颜色。
    private var settingsBodyColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.78) : Color.white.opacity(0.80)
    }

    // 次级提示色。
    private var settingsHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.56) : Color.white.opacity(0.55)
    }

    // 更弱提示色，用于“检查失败”等弱错误提示。
    private var settingsMutedHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.40) : Color.white.opacity(0.40)
    }
    private let settingsUpdatePositiveColor = Color(hex: 0x69BD64)
    private let settingsUpdateNegativeColor = Color(hex: 0xD05757)
    // 输入框填充色。
    private var settingsInputFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.62) : Color.white.opacity(0.14)
    }

    // 输入框占位色。
    private var settingsInputPlaceholderColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.35) : Color.white.opacity(0.30)
    }
    private var settingsSubtlePanelFillColor: Color {
        settingsUsesLightAppearance ? Color.white.opacity(0.46) : Color.white.opacity(0.045)
    }

    private var settingsSubtlePanelStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.08) : Color.white.opacity(0.06)
    }

    private var settingsSelectedRowFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.30)
    }

    private var settingsSelectedRowStrokeColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.52) : Color.white.opacity(0.80)
    }

    private var settingsRowStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.30)
    }

    private var settingsDropIndicatorColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.90) : Color.white.opacity(0.90)
    }

    private var settingsControlFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.05) : Color(hex: 0x2A2B2F)
    }

    private var settingsControlStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    private var settingsPopoverFillColor: Color {
        settingsUsesLightAppearance ? Color.white : Color(hex: 0x1F2024)
    }

    private var settingsPopoverSelectedFillColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.12) : Color.white.opacity(0.12)
    }

    private var settingsQuotaTrackColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.30)
    }

    private var settingsTrendPrimaryColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.78) : Color.white.opacity(0.62)
    }

    private var settingsTrendMutedColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.16) : Color.white.opacity(0.22)
    }

    private var settingsSliderTintColor: Color {
        settingsUsesLightAppearance ? settingsAccentBlue : Color.white.opacity(0.80)
    }
    // API 余额页右侧配置项统一标签列宽（设计稿为 60）。
    private let thirdPartyConfigLabelWidth: CGFloat = 60
    private let thirdPartyConfigLabelSpacing: CGFloat = 12

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
        case overview
        case general
        case menuBar
        case permissions
        case localData
        case officialProviders
        case customProviders

        var id: String { rawValue }

        var isProviderSection: Bool {
            self == .officialProviders || self == .customProviders
        }
    }

    private struct CodexProfileEditorState: Identifiable {
        var slotID: CodexSlotID
        var title: String
        var isNewSlot: Bool

        var id: String { "\(slotID.rawValue)-\(isNewSlot ? "new" : "edit")" }
    }

    private struct ClaudeProfileEditorState: Identifiable {
        var slotID: CodexSlotID
        var title: String
        var isNewSlot: Bool

        var id: String { "\(slotID.rawValue)-\(isNewSlot ? "new" : "edit")" }
    }

    private struct CodexQuotaMetricDisplay: Identifiable {
        var id: String
        var title: String
        var valueText: String
        var resetText: String
        var percent: Double?
        var barColor: Color
        var isAvailable: Bool = true
    }

    private struct OfficialDetailedDataRow: Identifiable {
        var id: String
        var key: String
        var value: String
    }

    private struct OfficialDetailedDataGroup: Identifiable {
        var id: String
        var title: String
        var rows: [OfficialDetailedDataRow]
    }

    private struct CodexTeamDisplayInfo {
        var alias: String
        var teamID: String
    }

    private struct LocalUsageTrendChartStatus {
        var text: String
        var color: Color
    }

    private struct SettingsOverviewCardItem: Identifiable {
        var id: String
        var icon: String
        var title: String
        var value: String
        var detail: String
        var accent: Color
    }

    var body: some View {
        // 设置页整体布局：全窗口铺底，让红绿灯直接落在背景上。
        ZStack {
            settingsMainContent
                .blur(radius: showsModalOverlay ? 4 : 0)
                .animation(.easeInOut(duration: 0.16), value: showsModalOverlay)

            if showsResetDataDialog {
                settingsModalBackdrop

                resetDataConfirmDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsCodexProfileEditorDialog {
                settingsModalBackdrop

                codexProfileEditorDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsClaudeProfileEditorDialog {
                settingsModalBackdrop

                claudeProfileEditorDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsOAuthImportDialog {
                settingsModalBackdrop

                oauthImportProgressDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsNewAPISiteDialog {
                settingsModalBackdrop

                newAPISiteDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
        // 设置内容需要覆盖标题栏区域，避免系统安全区留下顶部分层。
        .ignoresSafeArea()
        .environment(\.colorScheme, settingsColorScheme)
        .onAppear {
            seedInputsFromConfig()
            syncSelection()
            resetProviderReorderState()
            refreshSettingsAppearanceSample()
            applySettingsWindowAppearance()
            viewModel.refreshPermissionStatusesNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSettingsAppearanceSample()
            applySettingsWindowAppearance()
            viewModel.refreshPermissionStatusesNow()
        }
        .onReceive(settingsClock) { value in
            settingsNow = value
        }
        .onChange(of: viewModel.statusBarAppearanceMode) { _, _ in
            refreshSettingsAppearanceSample()
            applySettingsWindowAppearance()
        }
        .onChange(of: settingsWallpaperLuminance) { _, _ in
            applySettingsWindowAppearance()
        }
        .onChange(of: viewModel.config.providers.map(\.id)) { _, _ in
            seedInputsFromConfig()
            resetProviderReorderState()
            syncSelection()
        }
        .onChange(of: selectedGroup) { _, _ in
            resetProviderReorderState()
            syncSelection()
        }
        .onChange(of: selectedSettingsTab) { _, newValue in
            if newValue == .officialProviders {
                selectedGroup = .official
            } else if newValue == .customProviders {
                selectedGroup = .thirdParty
            }
            if newValue.isProviderSection {
                viewModel.refreshSettingsProfileState()
            }
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
                codexProfilePendingDelete = nil
            }
            Button(viewModel.text(.done), role: .cancel) {
                codexProfilePendingDelete = nil
            }
        } message: { _ in
            Text(viewModel.text(.codexDeleteProfileMessage))
        }
        .alert(
            viewModel.localizedText("删除 Claude 账号", "Delete Claude account"),
            isPresented: Binding(
                get: { claudeProfilePendingDelete != nil },
                set: { newValue in
                    if !newValue {
                        claudeProfilePendingDelete = nil
                    }
                }
            ),
            presenting: claudeProfilePendingDelete
        ) { slotID in
            Button(viewModel.localizedText("确认删除", "Delete"), role: .destructive) {
                let key = slotID.rawValue
                viewModel.removeClaudeProfile(slotID: slotID)
                claudeProfileJSONInputs.removeValue(forKey: key)
                claudeProfileConfigDirInputs.removeValue(forKey: key)
                claudeProfileResult.removeValue(forKey: key)
                claudeProfilePendingDelete = nil
            }
            Button(viewModel.text(.done), role: .cancel) {
                claudeProfilePendingDelete = nil
            }
        } message: { _ in
            Text(viewModel.localizedText("删除后将移除该账号保存的凭证与目录配置，本机当前 Claude 登录态不会立刻受影响。", "This removes the saved credentials and directory binding for the account. It does not immediately sign the current local Claude session out."))
        }
        .confirmationDialog(
            permissionAlertTitle,
            isPresented: Binding(
                get: { permissionPrompt != nil && permissionPrompt != .resetLocalData },
                set: { newValue in
                    if !newValue {
                        if permissionPrompt != .resetLocalData {
                            permissionPrompt = nil
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
                permissionPrompt = nil
            }
        } message: {
            Text(permissionAlertMessage)
        }
    }

    private var settingsMainContent: some View {
        ZStack {
            settingsBackgroundLayer

            HStack(alignment: .top, spacing: 18) {
                settingsNavigationSidebar
                    .frame(width: 220)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 18) {
                    settingsHeaderBar
                    settingsContentPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 44)
        }
    }

    private var settingsColorScheme: ColorScheme {
        settingsUsesLightAppearance ? .light : .dark
    }

    private var settingsUsesLightAppearance: Bool {
        SettingsWindowAppearanceResolver.usesLightAppearance(
            mode: viewModel.statusBarAppearanceMode,
            wallpaperLuminance: settingsWallpaperLuminance
        )
    }

    private var settingsBackgroundLayer: some View {
        ZStack {
            VisualEffectBlur(
                material: settingsUsesLightAppearance ? .sidebar : .hudWindow,
                blendingMode: .behindWindow
            )

            LinearGradient(
                colors: settingsUsesLightAppearance
                    ? [
                        Color(hex: 0xF8FAFC).opacity(0.82),
                        Color(hex: 0xE9EEF6).opacity(0.70)
                    ]
                    : [
                        Color(hex: 0x26272C).opacity(0.78),
                        Color(hex: 0x101114).opacity(0.82)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            NoiseTexture(opacity: settingsUsesLightAppearance ? 0.012 : 0.024)
        }
        .ignoresSafeArea()
    }

    private func settingsGlassSurface(cornerRadius: CGFloat, fill: Color) -> some View {
        ZStack {
            VisualEffectBlur(
                material: settingsUsesLightAppearance ? .sidebar : .hudWindow,
                blendingMode: .withinWindow
            )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)

            NoiseTexture(opacity: settingsUsesLightAppearance ? 0.008 : 0.016)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var settingsModalBackdrop: some View {
        ZStack {
            VisualEffectBlur(
                material: settingsUsesLightAppearance ? .popover : .hudWindow,
                blendingMode: .withinWindow
            )
            Color.black.opacity(settingsUsesLightAppearance ? 0.12 : 0.22)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func refreshSettingsAppearanceSample() {
        guard viewModel.statusBarAppearanceMode == .followWallpaper else {
            settingsWallpaperLuminance = nil
            return
        }
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        settingsWallpaperLuminance = SettingsWindowAppearanceResolver.wallpaperLuminance(for: screen)
    }

    private func applySettingsWindowAppearance() {
        guard let window = NSApp.windows.first(where: { $0.title == "AI Plan Monitor Settings" }) ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        SettingsWindowAppearanceResolver.apply(to: window, usesLightAppearance: settingsUsesLightAppearance)
    }

    private var settingsNavigationSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                settingsSidebarIdentityIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Plan Monitor")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(settingsTitleColor)
                    Text(viewModel.localizedText("监控与设置工作台", "Monitoring workspace"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                }
            }

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    settingsSidebarSectionTitle(viewModel.localizedText("工作台", "Workspace"))
                    settingsSidebarTabButton(
                        .overview,
                        icon: "square.grid.2x2"
                    )

                    settingsSidebarSectionTitle(viewModel.localizedText("偏好", "Preferences"))
                    settingsSidebarTabButton(
                        .general,
                        icon: "gearshape"
                    )
                    settingsSidebarTabButton(
                        .menuBar,
                        icon: "menubar.rectangle"
                    )

                    settingsSidebarSectionTitle(viewModel.localizedText("安全", "Security"))
                    settingsSidebarTabButton(
                        .permissions,
                        icon: "lock.shield"
                    )
                    settingsSidebarTabButton(
                        .localData,
                        icon: "externaldrive"
                    )

                    settingsSidebarSectionTitle(viewModel.localizedText("服务", "Services"))
                    settingsSidebarTabButton(
                        .officialProviders,
                        icon: "shippingbox"
                    )
                    settingsSidebarTabButton(
                        .customProviders,
                        icon: "point.3.connected.trianglepath.dotted"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                settingsSidebarVersionRow
                settingsSidebarInfoRow(
                    title: viewModel.localizedText("最近刷新", "Last refresh"),
                    value: lastRefreshSummaryText
                )
                settingsSidebarGitHubLink
            }
        }
        .padding(18)
        .background(
            settingsGlassSurface(
                cornerRadius: settingsSidebarCornerRadius,
                fill: settingsSidebarFillColor
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsSidebarCornerRadius, style: .continuous)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var settingsSidebarIdentityIcon: some View {
        if let image = bundledImage(named: "app_icon_source") {
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

    private func settingsSidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(settingsHintColor.opacity(0.86))
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.top, 8)
    }

    private func settingsSidebarTabButton(
        _ tab: SettingsTab,
        icon: String
    ) -> some View {
        let isSelected = selectedSettingsTab == tab
        let selectedFill = settingsUsesLightAppearance ? settingsAccentBlue : Color.white.opacity(0.15)
        let selectedForeground = settingsUsesLightAppearance ? Color.white : settingsTitleColor
        let idleForeground = settingsUsesLightAppearance ? settingsTitleColor : settingsBodyColor
        let hoverFill = settingsUsesLightAppearance ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
        let selectedStroke = settingsUsesLightAppearance ? Color.white.opacity(0.08) : Color.white.opacity(0.22)

        return ModernSettingsSidebarTabButton(
            icon: icon,
            title: settingsTabTitle(tab),
            isSelected: isSelected,
            selectedFill: selectedFill,
            hoverFill: hoverFill,
            selectedForeground: selectedForeground,
            idleForeground: idleForeground,
            mutedForeground: settingsHintColor,
            selectedStroke: selectedStroke
        ) {
            selectedSettingsTab = tab
            if tab == .officialProviders {
                selectedGroup = .official
            } else if tab == .customProviders {
                selectedGroup = .thirdParty
            }
        }
    }

    private var settingsSidebarVersionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.localizedText("当前版本", "Current version"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(settingsHintColor)

            HStack(alignment: .center, spacing: 8) {
                Text(viewModel.currentAppVersion)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    viewModel.checkForAppUpdate(force: true)
                } label: {
                    Text(viewModel.localizedText("检查更新", "Check Updates"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(settingsUpdateActionDisabled)
            }

            settingsSidebarUpdateStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(settingsSubtlePanelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var settingsSidebarUpdateStatus: some View {
        let state = viewModel.settingsUpdateDisplayState

        if let statusText = state.statusText {
            let tone = settingsSidebarUpdateStatusTone(for: state)
            let tint = settingsTopUpdateStatusColor(for: tone)
            let detailText = settingsSidebarUpdateDetailText(for: state)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: settingsSidebarUpdateIcon(for: state.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 15, height: 15)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(settingsSidebarUpdateTitle(for: state, fallback: statusText))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detailText {
                            Text(detailText)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let actionTitle = settingsSidebarUpdateActionTitle(for: state) {
                    settingsSidebarUpdateActionButton(
                        title: actionTitle,
                        tint: tint,
                        isEnabled: settingsSidebarUpdateActionEnabled(for: state)
                    ) {
                        viewModel.openLatestReleaseDownload()
                    }
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(tint.opacity(settingsUsesLightAppearance ? 0.28 : 0.34))
                    .frame(height: 1)
            }
        }
    }

    private func settingsSidebarUpdateActionButton(
        title: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Label(title, systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.96 : 0.56))
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(isEnabled ? 1 : 0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
    }

    private func settingsSidebarUpdateStatusTone(
        for state: AppViewModel.SettingsUpdateDisplayState
    ) -> AppViewModel.UpdateDisplayTone {
        if case .checkFailed = state.kind {
            return .neutral
        }
        return state.tone
    }

    private func settingsSidebarUpdateIcon(
        for kind: AppViewModel.SettingsUpdateDisplayState.Kind
    ) -> String {
        switch kind {
        case .idle:
            return "arrow.down.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .checkFailed:
            return "exclamationmark.triangle"
        case .upToDate:
            return "checkmark.circle"
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .installBuffering:
            return "clock"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func settingsSidebarUpdateTitle(
        for state: AppViewModel.SettingsUpdateDisplayState,
        fallback: String
    ) -> String {
        switch state.kind {
        case .updateAvailable:
            return viewModel.text(.updateAvailableTitle)
        default:
            return fallback
        }
    }

    private func settingsSidebarUpdateDetailText(
        for state: AppViewModel.SettingsUpdateDisplayState
    ) -> String? {
        switch state.kind {
        case let .updateAvailable(version):
            return String(
                format: viewModel.text(.updateAvailableBody),
                version,
                viewModel.currentAppVersion
            )
        case .checking:
            return viewModel.text(.aboutUpdateChecking)
        default:
            return viewModel.updateStatusSummary
        }
    }

    private func settingsSidebarUpdateActionTitle(
        for state: AppViewModel.SettingsUpdateDisplayState
    ) -> String? {
        switch state.kind {
        case .updateAvailable:
            return viewModel.localizedText("立即升级", "Upgrade Now")
        case .failed:
            return state.retryTitle
        default:
            return nil
        }
    }

    private func settingsSidebarUpdateActionEnabled(
        for state: AppViewModel.SettingsUpdateDisplayState
    ) -> Bool {
        switch state.kind {
        case .updateAvailable:
            return viewModel.isUpdateActionEnabled
        case .failed:
            return state.isRetryEnabled
        default:
            return false
        }
    }

    private var settingsSidebarGitHubLink: some View {
        Button {
            viewModel.openRepositoryPage()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)

                Text("GitHub")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
            }
            .foregroundStyle(settingsTitleColor)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(settingsSubtlePanelFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var settingsUpdateActionDisabled: Bool {
        viewModel.updateCheckInFlight ||
        viewModel.updateDownloadInFlight ||
        viewModel.updateInstallBufferingInFlight ||
        viewModel.updateInstallationInFlight
    }

    private func settingsSidebarInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(settingsHintColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settingsTitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(settingsSubtlePanelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
        )
    }

    private var settingsHeaderBar: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsHeaderTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(settingsTitleColor)

                Text(settingsHeaderSubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            settingsRefreshAllButton
        }
    }

    private var settingsRefreshAllButton: some View {
        Button {
            viewModel.refreshNow()
        } label: {
            Label(viewModel.localizedText("刷新全部", "Refresh All"), systemImage: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 104)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(settingsAccentBlue)
        .help(viewModel.localizedText("立即刷新所有已启用服务", "Refresh all enabled services now"))
    }

    @ViewBuilder
    private var settingsHeaderUpdatePill: some View {
        if let statusText = viewModel.settingsUpdateDisplayState.statusText {
            let state = viewModel.settingsUpdateDisplayState
            let statusTone: AppViewModel.UpdateDisplayTone = {
                if case .checkFailed = state.kind {
                    return .neutral
                }
                return state.tone
            }()

            settingsHeaderPill(
                title: state.retryTitle.map { "\(statusText) · \($0)" } ?? statusText,
                icon: "sparkles",
                tint: settingsTopUpdateStatusColor(for: statusTone),
                fill: settingsTopUpdateStatusColor(for: statusTone).opacity(0.10)
            ) {
                if case .updateAvailable = state.kind {
                    viewModel.openLatestReleaseDownload()
                } else if state.retryTitle != nil {
                    viewModel.openLatestReleaseDownload()
                }
            }
        }
    }

    @ViewBuilder
    private func settingsHeaderPill(
        title: String,
        icon: String,
        tint: Color,
        fill: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        let label = Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)

        if let action {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(tint)
        } else {
            label
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private var settingsContentPane: some View {
        switch selectedSettingsTab {
        case .overview:
            overviewDashboardContent
        case .general:
            settingsSingleSectionContent(
                title: viewModel.localizedText("常规", "General"),
                subtitle: viewModel.localizedText("设置语言、设置窗口外观、开机启动和基础应用行为。", "Configure language, settings window appearance, launch at login, and basic app behavior.")
            ) {
                appBehaviorSection
            }
        case .menuBar:
            settingsSingleSectionContent(
                title: viewModel.localizedText("菜单栏", "Menubar"),
                subtitle: viewModel.localizedText("控制菜单栏显示哪些服务、如何展示以及信息密度。", "Control which services appear in the menubar, how they render, and information density.")
            ) {
                menuBarPreferencesSection
            }
        case .permissions:
            settingsSingleSectionContent(
                title: viewModel.localizedText("权限", "Permissions"),
                subtitle: viewModel.localizedText("管理通知、钥匙串和全盘访问授权。", "Manage notifications, keychain, and full disk access.")
            ) {
                permissionAccessSection
            }
        case .localData:
            settingsSingleSectionContent(
                title: viewModel.localizedText("本地数据", "Local Data"),
                subtitle: viewModel.localizedText("扫描本机账号配置，或重置 AI Plan Monitor 的本地数据。", "Discover local account config or reset AI Plan Monitor's local data.")
            ) {
                localDataManagementSection
            }
        case .officialProviders:
            providerDashboardContent(group: .official)
        case .customProviders:
            providerDashboardContent(group: .thirdParty)
        }
    }

    private var overviewDashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsOverviewGrid(items: generalOverviewItems)
                officialUsageTrendsOverviewSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
        .background(
            settingsGlassSurface(
                cornerRadius: settingsShellCornerRadius,
                fill: cardBackground
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous))
    }

    private func settingsSingleSectionContent<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSectionCard(title: title, subtitle: subtitle) {
                    content()
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
        .background(
            settingsGlassSurface(
                cornerRadius: settingsShellCornerRadius,
                fill: cardBackground
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous))
    }

    private func providerDashboardContent(group: ProviderGroup) -> some View {
        HStack(alignment: .top, spacing: 16) {
            settingsSectionPanel {
                providerSidebarContent(for: group)
            }
            .frame(width: 280)
            .frame(maxHeight: .infinity, alignment: .top)

            settingsSectionPanel {
                detailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .background(
            settingsGlassSurface(
                cornerRadius: settingsShellCornerRadius,
                fill: cardBackground
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: settingsShellCornerRadius, style: .continuous))
        .onAppear {
            selectedGroup = group
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

    private func settingsOverviewGrid(items: [SettingsOverviewCardItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(items) { item in
                settingsOverviewCard(item)
            }
        }
    }

    private func settingsOverviewCard(_ item: SettingsOverviewCardItem) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.accent)

                Spacer(minLength: 12)

                Text(item.value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(item.accent)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)
                Text(item.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: settingsSectionCornerRadius, style: .continuous)
                .fill(item.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsSectionCornerRadius, style: .continuous)
                .stroke(item.accent.opacity(0.35), lineWidth: 1)
        )
        .hoverGlow(
            tint: item.accent,
            intensity: settingsUsesLightAppearance ? 0.08 : 0.12,
            radius: 120,
            cornerRadius: settingsSectionCornerRadius
        )
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

                officialUsageTrendSparklineGrid(providers: providers)

                ForEach(providers) { provider in
                    settingsSectionPanel {
                        officialLocalTrendSection(
                            provider: provider,
                            snapshot: viewModel.snapshots[provider.id],
                            showsDivider: false,
                            title: officialUsageTrendOverviewTitle(for: provider)
                        )
                    }
                }
            }
        }
    }

    private func officialUsageTrendSparklineGrid(providers: [ProviderDescriptor]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(providers) { provider in
                officialUsageTrendSparklineCard(
                    provider: provider,
                    snapshot: viewModel.snapshots[provider.id]
                )
            }
        }
    }

    private func officialUsageTrendSparklineCard(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let summary = localUsageTrendResolvedSummary(provider: provider, snapshot: snapshot)
        let values = localUsageTrendSparklineValues(summary)
        let hasValues = values.contains { $0 > 0 }
        let tint = hasValues ? settingsTrendPrimaryColor : settingsTrendMutedColor

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                providerIcon(for: provider, size: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sidebarDisplayName(for: provider))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsTitleColor)
                        .lineLimit(1)
                    Text(localUsageTrendSparklineCaption(summary))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            MiniSparkline(dataPoints: values, color: tint, lineWidth: 2, showsFill: true)
                .frame(height: 28)
                .opacity(hasValues ? 1 : 0.55)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: settingsSectionCornerRadius, style: .continuous)
                .fill(settingsSubtlePanelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsSectionCornerRadius, style: .continuous)
                .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
        )
        .hoverGlow(
            tint: tint,
            intensity: settingsUsesLightAppearance ? 0.08 : 0.12,
            radius: 110,
            cornerRadius: settingsSectionCornerRadius
        )
        .onAppear {
            refreshLocalUsageTrendIfNeeded(provider: provider, snapshot: snapshot)
        }
    }

    private func settingsSectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSectionPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(settingsTitleColor)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
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
            settingsGlassSurface(
                cornerRadius: settingsSectionCornerRadius,
                fill: settingsSectionFillColor
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: settingsSectionCornerRadius, style: .continuous)
                .stroke(settingsShellStrokeColor, lineWidth: 1)
        )
    }

    private var settingsHeaderTitle: String {
        switch selectedSettingsTab {
        case .overview:
            return viewModel.localizedText("设置概览", "Settings Overview")
        case .general:
            return viewModel.localizedText("常规", "General")
        case .menuBar:
            return viewModel.localizedText("菜单栏", "Menubar")
        case .permissions:
            return viewModel.localizedText("权限", "Permissions")
        case .localData:
            return viewModel.localizedText("本地数据", "Local Data")
        case .officialProviders:
            return viewModel.localizedText("官方服务", "Official Services")
        case .customProviders:
            return viewModel.localizedText("自定义接口", "Custom Endpoints")
        }
    }

    private var settingsHeaderSubtitle: String {
        switch selectedSettingsTab {
        case .overview:
            return viewModel.localizedText(
                "把监控、权限和服务配置收拢成一个可快速扫描的工作台。",
                "A scannable workspace for monitoring, permissions, and service configuration."
            )
        case .general:
            return viewModel.localizedText(
                "管理应用语言、启动行为和基础偏好。",
                "Manage app language, launch behavior, and basic preferences."
            )
        case .menuBar:
            return viewModel.localizedText(
                "调整菜单栏里显示哪些模型、如何显示以及跟随哪种外观。",
                "Adjust which models appear in the menubar, how they render, and which appearance mode they use."
            )
        case .permissions:
            return viewModel.localizedText(
                "检查授权状态，确保通知、钥匙串和本地读取能力可用。",
                "Review authorization status for notifications, keychain, and local file access."
            )
        case .localData:
            return viewModel.localizedText(
                "发现本地 CLI 账号配置，或在需要时清理本地应用数据。",
                "Discover local CLI account config or clear local app data when needed."
            )
        case .officialProviders:
            return viewModel.localizedText(
                "管理 Codex、Claude、Gemini、Cursor 等官方来源和账号。",
                "Manage official sources and accounts such as Codex, Claude, Gemini, and Cursor."
            )
        case .customProviders:
            return viewModel.localizedText(
                "配置 Relay、New API 和第三方余额接口。",
                "Configure Relay, New API, and third-party balance endpoints."
            )
        }
    }

    private var generalOverviewItems: [SettingsOverviewCardItem] {
        let totalProviders = viewModel.config.providers.count
        let enabledProviders = viewModel.config.providers.filter(\.enabled).count
        let disabledProviders = totalProviders - enabledProviders
        let requiredPermissions = settingsRequiredPermissionCount
        let grantedPermissions = settingsGrantedPermissionCount
        let isMulti = viewModel.statusBarMultiUsageEnabled

        return [
            SettingsOverviewCardItem(
                id: "providers",
                icon: "square.stack.3d.up",
                title: viewModel.localizedText("已追踪服务", "Tracked Providers"),
                value: "\(totalProviders)",
                detail: viewModel.localizedText(
                    "\(officialProviderCount) 个官方来源，\(thirdPartyProviderCount) 个自定义来源",
                    "\(officialProviderCount) official sources, \(thirdPartyProviderCount) custom sources"
                ),
                accent: settingsAccentBlue
            ),
            SettingsOverviewCardItem(
                id: "enabled",
                icon: "bolt.heart",
                title: viewModel.localizedText("活跃监控", "Active Monitors"),
                value: "\(enabledProviders)",
                detail: disabledProviders > 0
                    ? viewModel.localizedText("还有 \(disabledProviders) 个已停用", "\(disabledProviders) currently disabled")
                    : viewModel.localizedText("全部服务都已启用", "All services enabled"),
                accent: settingsAccentGreen
            ),
            SettingsOverviewCardItem(
                id: "permissions",
                icon: "lock.shield",
                title: viewModel.localizedText("权限状态", "Permissions"),
                value: "\(grantedPermissions)/\(requiredPermissions)",
                detail: viewModel.localizedText(
                    "通知、钥匙串与全盘访问统一收纳",
                    "Notifications, keychain, and full disk access in one place"
                ),
                accent: settingsAccentPurple
            ),
            SettingsOverviewCardItem(
                id: "menubar",
                icon: "menubar.rectangle",
                title: viewModel.localizedText("界面与菜单栏", "Interface & Menubar"),
                value: isMulti ? viewModel.localizedText("多模型", "Multi") : viewModel.localizedText("单模型", "Single"),
                detail: viewModel.localizedText(
                    "设置窗口 \(statusBarAppearanceModeSummary) · 菜单栏 \(statusBarDisplayStyleSummary)",
                    "Settings window \(statusBarAppearanceModeSummary) · Menubar \(statusBarDisplayStyleSummary)"
                ),
                accent: settingsAccentCyan
            )
        ]
    }

    private var modelOverviewItems: [SettingsOverviewCardItem] {
        let totalProviders = viewModel.config.providers.count
        let enabledProviders = viewModel.config.providers.filter(\.enabled).count

        return [
            SettingsOverviewCardItem(
                id: "official-models",
                icon: "shippingbox",
                title: viewModel.localizedText("官方服务", "Official Services"),
                value: "\(officialProviderCount)",
                detail: viewModel.localizedText("内置来源与官方账号接入", "Built-in services and first-party accounts"),
                accent: settingsAccentBlue
            ),
            SettingsOverviewCardItem(
                id: "relay-models",
                icon: "point.3.connected.trianglepath.dotted",
                title: viewModel.localizedText("自定义来源", "Custom Sources"),
                value: "\(thirdPartyProviderCount)",
                detail: viewModel.localizedText("Relay / New API / 余额接口", "Relay, New API, and balance endpoints"),
                accent: settingsAccentPurple
            ),
            SettingsOverviewCardItem(
                id: "enabled-models",
                icon: "checkmark.circle",
                title: viewModel.localizedText("正在轮询", "Polling Now"),
                value: "\(enabledProviders)",
                detail: viewModel.localizedText(
                    "共 \(totalProviders) 个来源，其中 \(totalProviders - enabledProviders) 个暂停",
                    "\(totalProviders - enabledProviders) paused out of \(totalProviders) sources"
                ),
                accent: settingsAccentGreen
            ),
            SettingsOverviewCardItem(
                id: "pinned-models",
                icon: "pin.circle",
                title: viewModel.localizedText("菜单栏来源", "Menubar Sources"),
                value: "\(statusBarSourceCount)",
                detail: viewModel.localizedText(
                    "设置窗口 \(statusBarAppearanceModeSummary) · 菜单栏 \(statusBarDisplayStyleSummary)",
                    "Settings window \(statusBarAppearanceModeSummary) · Menubar \(statusBarDisplayStyleSummary)"
                ),
                accent: settingsAccentCyan
            )
        ]
    }

    private var officialProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .official }.count
    }

    private var officialUsageTrendOverviewProviders: [ProviderDescriptor] {
        viewModel.config.providers.filter { provider in
            provider.enabled && shouldShowOfficialLocalTrendCard(for: provider)
        }
    }

    private func officialUsageTrendOverviewTitle(for provider: ProviderDescriptor) -> String {
        let displayName = sidebarDisplayName(for: provider)
        if viewModel.language == .zhHans {
            return "\(displayName) 使用趋势"
        }
        return "\(displayName) Usage Trend"
    }

    private var thirdPartyProviderCount: Int {
        viewModel.config.providers.filter { $0.family == .thirdParty }.count
    }

    private var settingsRequiredPermissionCount: Int {
        var count = 2
        if viewModel.fullDiskAccessRelevant || viewModel.fullDiskAccessRequested {
            count += 1
        }
        return count
    }

    private var settingsGrantedPermissionCount: Int {
        var count = 0
        if viewModel.hasNotificationPermission {
            count += 1
        }
        if viewModel.secureStorageReady {
            count += 1
        }
        if (viewModel.fullDiskAccessRelevant || viewModel.fullDiskAccessRequested) && viewModel.fullDiskAccessGranted {
            count += 1
        }
        return count
    }

    private var statusBarAppearanceModeSummary: String {
        switch viewModel.statusBarAppearanceMode {
        case .followWallpaper:
            return viewModel.localizedText("跟随壁纸", "Adaptive")
        case .dark:
            return viewModel.localizedText("深色", "Dark")
        case .light:
            return viewModel.localizedText("浅色", "Light")
        }
    }

    private var statusBarDisplayStyleSummary: String {
        switch viewModel.statusBarDisplayStyle {
        case .iconPercent:
            return viewModel.localizedText("图标 + 百分比", "Icon + percent")
        case .barNamePercent:
            return viewModel.localizedText("柱状 + 名称", "Bar + name")
        }
    }

    private var statusBarSourceCount: Int {
        if viewModel.statusBarMultiUsageEnabled {
            return max(1, viewModel.config.statusBarMultiProviderIDs.count)
        }
        return viewModel.config.statusBarProviderID == nil ? 0 : 1
    }

    private var lastRefreshSummaryText: String {
        guard let lastUpdatedAt = viewModel.lastUpdatedAt else {
            return viewModel.localizedText("尚未刷新", "Not refreshed yet")
        }
        return settingsElapsedText(from: lastUpdatedAt)
    }

    private var showsResetDataDialog: Bool {
        permissionPrompt == .resetLocalData
    }

    private var showsCodexProfileEditorDialog: Bool {
        codexProfileEditor != nil
    }

    private var showsClaudeProfileEditorDialog: Bool {
        claudeProfileEditor != nil
    }

    private var showsNewAPISiteDialog: Bool {
        isNewAPISiteDialogPresented
    }

    private var activeOAuthImportDialogState: OAuthImportState? {
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

    private var showsModalOverlay: Bool {
        showsResetDataDialog
            || showsCodexProfileEditorDialog
            || showsClaudeProfileEditorDialog
            || showsOAuthImportDialog
            || showsNewAPISiteDialog
    }

    private var resetDialogTitleText: String {
        viewModel.language == .zhHans ? "重置本地应用数据" : viewModel.text(.resetLocalDataTitle)
    }

    private var resetDialogDescriptionText: String {
        viewModel.language == .zhHans
            ? "确认后会清理本地配置、Codex 账号槽位、启动项和 AI Plan Monitor 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销"
            : viewModel.text(.resetLocalDataConfirm)
    }

    private var resetDialogCancelTitle: String {
        viewModel.language == .zhHans ? "我再想想" : viewModel.text(.permissionCancel)
    }

    private var resetDialogConfirmTitle: String {
        viewModel.language == .zhHans ? "重置数据" : viewModel.text(.resetLocalDataAction)
    }

    private var resetDataConfirmDialog: some View {
        // 自定义重置确认弹窗（Figma 48:2183）：260x202，标题 16/100%，正文 12/150%。
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(resetDialogTitleText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(resetDialogDescriptionText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            HStack(spacing: 8) {
                resetDialogButton(
                    title: resetDialogCancelTitle,
                    background: Color(hex: 0xE6E6E6),
                    foreground: .black,
                    weight: .regular
                ) {
                    permissionPrompt = nil
                }
                .keyboardShortcut(.cancelAction)

                resetDialogButton(
                    title: resetDialogConfirmTitle,
                    background: Color(hex: 0xD05757),
                    foreground: .white,
                    weight: .semibold
                ) {
                    handlePermissionPrompt()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 260, alignment: .center)
        .background(
            DialogSmoothRoundedRectangle(cornerRadius: 26, smoothing: 0.6)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 26, smoothing: 0.6)
                .stroke(Color.white.opacity(0.40), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    private func resetDialogButton(
        title: String,
        background: Color,
        foreground: Color,
        weight: Font.Weight,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: weight))
                .frame(width: 110)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(background)
    }

    private var settingsTabBar: some View {
        // 顶部 tab + 右侧版本信息区域。
        HStack(spacing: 8) {
            settingsTabButton(.overview)
            settingsTabButton(.general)
            settingsTabButton(.menuBar)
            settingsTabButton(.permissions)
            settingsTabButton(.localData)
            settingsTabButton(.officialProviders)
            settingsTabButton(.customProviders)
            Spacer()
            settingsTopMetaBar
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedSettingsTab == tab
        let selectedTextColor = settingsUsesLightAppearance ? settingsAccentBlue : Color.black
        let idleTextColor = settingsBodyColor
        let selectedFillColor = settingsUsesLightAppearance ? settingsAccentBlue.opacity(0.14) : Color.white.opacity(0.8)
        let idleFillColor = settingsUsesLightAppearance ? Color.black.opacity(0.04) : Color.white.opacity(0.15)

        return Button {
            selectedSettingsTab = tab
            if tab == .officialProviders {
                selectedGroup = .official
            } else if tab == .customProviders {
                selectedGroup = .thirdParty
            }
        } label: {
            Text(settingsTabTitle(tab))
                // tab 文字字号与选中态字重。
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? selectedTextColor : idleTextColor)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    // tab 背景：选中是亮底，未选中是 white_15。
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? selectedFillColor : idleFillColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsTabTitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .overview:
            return viewModel.localizedText("概览", "Overview")
        case .general:
            return viewModel.text(.settingsGeneralTab)
        case .menuBar:
            return viewModel.localizedText("菜单栏", "Menubar")
        case .permissions:
            return viewModel.localizedText("权限", "Permissions")
        case .localData:
            return viewModel.localizedText("本地数据", "Local Data")
        case .officialProviders:
            return viewModel.localizedText("官方服务", "Official")
        case .customProviders:
            return viewModel.localizedText("自定义接口", "Custom")
        }
    }

    private var settingsTopMetaBar: some View {
        HStack(spacing: 12) {
            if let statusText = viewModel.settingsUpdateDisplayState.statusText {
                settingsTopUpdateStatusSlot(statusText: statusText)
                    .layoutPriority(3)
            }

            Button {
                viewModel.openCurrentVersionReleaseNotes()
            } label: {
                settingsTopMetaItem(
                    text: currentVersionTitle,
                    iconName: "settings_version_icon",
                    fallbackIcon: "chevron.left.forwardslash.chevron.right",
                    textColor: settingsHintColor
                )
                .padding(.horizontal, 4)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                viewModel.checkForAppUpdate(force: true)
            } label: {
                Text(viewModel.localizedText("检查更新", "Check for Updates"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.updateCheckInFlight || viewModel.updateDownloadInFlight || viewModel.updateInstallBufferingInFlight || viewModel.updateInstallationInFlight)
            .layoutPriority(1)

            Button {
                viewModel.openRepositoryPage()
            } label: {
                settingsTopMetaItem(
                    text: "GitHub",
                    iconName: "settings_github_icon",
                    fallbackIcon: "chevron.left.forwardslash.chevron.right",
                    textColor: settingsHintColor
                )
                .padding(.horizontal, 4)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func settingsTopUpdateStatusSlot(statusText: String) -> some View {
        let state = viewModel.settingsUpdateDisplayState
        let statusTone: AppViewModel.UpdateDisplayTone = {
            if case .checkFailed = state.kind {
                return .neutral
            }
            return state.tone
        }()
        let isUpdateAvailable: Bool = {
            if case .updateAvailable = state.kind {
                return true
            }
            return false
        }()

        HStack(spacing: 6) {
            settingsTopMetaIcon(
                name: "settings_download_icon",
                fallbackIcon: "arrow.down",
                tint: settingsTopUpdateStatusColor(for: statusTone),
                appliesTintToBundledImage: true
            )
            if isUpdateAvailable {
                Button {
                    viewModel.openLatestReleaseDownload()
                } label: {
                    Text(statusText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(settingsTopUpdateStatusColor(for: statusTone))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isUpdateActionEnabled)
            } else {
                Text(statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(settingsTopUpdateStatusColor(for: statusTone))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let retryTitle = state.retryTitle {
                Button {
                    viewModel.openLatestReleaseDownload()
                } label: {
                    Text(retryTitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(settingsTopUpdateStatusColor(for: .negative))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!state.isRetryEnabled)
            }
        }
    }

    private func settingsTopUpdateStatusColor(for tone: AppViewModel.UpdateDisplayTone) -> Color {
        switch tone {
        case .neutral:
            return settingsMutedHintColor
        case .positive:
            return settingsUpdatePositiveColor
        case .negative:
            return settingsUpdateNegativeColor
        }
    }

    @ViewBuilder
    private func settingsTopMetaItem(
        text: String,
        iconName: String,
        fallbackIcon: String,
        textColor: Color,
        textWeight: Font.Weight = .regular
    ) -> some View {
        HStack(spacing: 4) {
            settingsTopMetaIcon(name: iconName, fallbackIcon: fallbackIcon, tint: textColor)
            Text(text)
                .font(.system(size: 11, weight: textWeight))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func settingsTopMetaIcon(
        name: String,
        fallbackIcon: String,
        tint: Color,
        appliesTintToBundledImage: Bool = false
    ) -> some View {
        if let image = bundledImage(named: name) {
            if appliesTintToBundledImage || settingsUsesLightAppearance {
                // 图标按原始宽高比缩放，避免不同视觉比例被拉伸。
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(tint)
            } else {
                // 图标按原始宽高比缩放，避免不同视觉比例被拉伸。
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
            }
        } else {
            Image(systemName: fallbackIcon)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 11, height: 11)
        }
    }

    private var currentVersionTitle: String {
        if viewModel.language == .zhHans {
            return "版本 \(viewModel.currentAppVersion)"
        }
        return "Version \(viewModel.currentAppVersion)"
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
        // 模型设置左侧：顶部分组切换 + 下方模型列表（两段式容器）。
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                modelGroupSegmentControl
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Group {
                if selectedGroup == .thirdParty {
                    thirdPartySidebarContent
                } else {
                    officialSidebarContent
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var modelGroupSegmentControl: some View {
        Picker("", selection: Binding(
            get: { selectedGroup.id },
            set: { newValue in
                if let group = ProviderGroup(rawValue: newValue) {
                    selectedGroup = group
                    selectedSettingsTab = group == .official ? .officialProviders : .customProviders
                }
            }
        )) {
            Text(viewModel.text(.officialTab)).tag(ProviderGroup.official.id)
            Text(viewModel.text(.thirdPartyTab)).tag(ProviderGroup.thirdParty.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 188, height: 20)
    }

    private var thirdPartySidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    providerSidebarList

                    if !unaddedRelayBuiltInPresets.isEmpty {
                        Spacer()
                            .frame(height: 12)

                        dividerLine

                        Spacer()
                            .frame(height: 12)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(unaddedRelayBuiltInPresets) { preset in
                                relayPresetSidebarRow(preset)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 16)

            dividerLine

            Spacer()
                .frame(height: 16)

            addNewAPISiteButton
        }
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var officialSidebarContent: some View {
        ScrollView {
            providerSidebarList
        }
        .scrollIndicators(.never)
        .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
    }

    private var providerSidebarList: some View {
        let enabledProviders = orderedEnabledSidebarProviders
        let disabledProviders = disabledSidebarProviders

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(enabledProviders) { provider in
                    sidebarProviderRow(provider)
                }
            }

            if !enabledProviders.isEmpty, !disabledProviders.isEmpty {
                Spacer()
                    .frame(height: 12)

                dividerLine

                Spacer()
                    .frame(height: 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(disabledProviders) { provider in
                    sidebarProviderRow(provider)
                }
            }
        }
    }

    private var addNewAPISiteButton: some View {
        Button {
            selectedRelayPresetID = nil
            applyNewRelayTemplate("generic-newapi")
            if newProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newProviderName = "NewAPI"
            }
            isNewAPISiteDialogPresented = true
        } label: {
            Text(viewModel.language == .zhHans ? "添加 NewAPI 站点" : "Add NewAPI Site")
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(settingsAccentBlue)
    }

    @ViewBuilder
    private func sidebarProviderRow(_ provider: ProviderDescriptor) -> some View {
        let row = sidebarProviderRowContent(provider)
        if provider.enabled {
            row
                .onDrag {
                    beginProviderReorderDrag(providerID: provider.id)
                }
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: ProviderRowDropDelegate(
                        targetProviderID: provider.id,
                        enabledProviderIDs: enabledSidebarProviders.map(\.id),
                        draggingProviderID: $draggingProviderID,
                        previewProviderIDs: $reorderPreviewProviderIDs,
                        dropTargetProviderID: $dropTargetProviderID,
                        dropTargetInsertAfter: $dropTargetInsertAfter,
                        onPerformDrop: { commitProviderReorder() }
                    )
                )
        } else {
            row
        }
    }

    private func sidebarProviderRowContent(_ provider: ProviderDescriptor) -> some View {
        let isSelected = selectedProviderID == provider.id
        let isDragging = draggingProviderID == provider.id
        let isDropTarget = provider.enabled
            && draggingProviderID != nil
            && draggingProviderID != provider.id
            && dropTargetProviderID == provider.id

        // 左侧“模型列表单行”样式（选中态描边/背景在这里改）。
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { provider.enabled },
                set: {
                    viewModel.setEnabled($0, providerID: provider.id)
                    selectedProviderID = provider.id
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            providerIcon(for: provider, size: 12)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
            Spacer(minLength: 0)

            if provider.enabled {
                reorderHandle()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sidebarProviderRowFill(isSelected: isSelected, isDropTarget: isDropTarget))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isDropTarget
                        ? settingsDropIndicatorColor.opacity(0.72)
                        : (isSelected ? settingsSelectedRowStrokeColor : settingsRowStrokeColor),
                    lineWidth: isDropTarget ? 1.5 : 1
                )
        )
        .overlay(alignment: dropTargetInsertAfter ? .bottom : .top) {
            if provider.enabled,
               let draggingProviderID,
               draggingProviderID != provider.id,
               dropTargetProviderID == provider.id {
                Rectangle()
                    .fill(settingsDropIndicatorColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .shadow(
            color: Color.black.opacity(isDragging || isDropTarget ? 0.18 : 0),
            radius: isDragging || isDropTarget ? 10 : 0,
            x: 0,
            y: isDragging || isDropTarget ? 4 : 0
        )
        .scaleEffect(isDragging ? 0.98 : (isDropTarget ? 1.015 : 1))
        .opacity(isDragging ? 0.62 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProviderID = provider.id
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: orderedEnabledSidebarProviders.map(\.id))
        .animation(.spring(response: 0.18, dampingFraction: 0.72), value: dropTargetProviderID)
        .animation(.spring(response: 0.18, dampingFraction: 0.72), value: draggingProviderID)
    }

    private func sidebarProviderRowFill(isSelected: Bool, isDropTarget: Bool) -> Color {
        if isDropTarget {
            return settingsDropIndicatorColor.opacity(settingsUsesLightAppearance ? 0.12 : 0.18)
        }
        if isSelected {
            return settingsSelectedRowFillColor
        }
        return Color.clear
    }

    private func reorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(settingsHintColor)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
    }

    private func beginProviderReorderDrag(providerID: String) -> NSItemProvider {
        draggingProviderID = providerID
        reorderPreviewProviderIDs = enabledSidebarProviders.map(\.id)
        dropTargetProviderID = providerID
        dropTargetInsertAfter = false
        return NSItemProvider(object: providerID as NSString)
    }

    private func commitProviderReorder() -> Bool {
        defer { resetProviderReorderState() }
        guard let sourceProviderID = draggingProviderID else { return false }

        let originalIDs = enabledSidebarProviders.map(\.id)
        let finalIDs = reorderPreviewProviderIDs ?? originalIDs

        guard let sourceIndex = originalIDs.firstIndex(of: sourceProviderID),
              let destinationIndex = finalIDs.firstIndex(of: sourceProviderID) else {
            return false
        }

        guard sourceIndex != destinationIndex else { return true }

        moveEnabledProviders(from: IndexSet(integer: sourceIndex), to: destinationIndex)
        selectedProviderID = sourceProviderID
        return true
    }

    private func resetProviderReorderState() {
        draggingProviderID = nil
        reorderPreviewProviderIDs = nil
        dropTargetProviderID = nil
        dropTargetInsertAfter = false
    }

    private var enabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter(\.enabled)
    }

    private var disabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter { !$0.enabled }
    }

    private var orderedEnabledSidebarProviders: [ProviderDescriptor] {
        let enabledProviders = enabledSidebarProviders
        guard let previewIDs = reorderPreviewProviderIDs else { return enabledProviders }

        let providerByID = Dictionary(uniqueKeysWithValues: enabledProviders.map { ($0.id, $0) })
        let ordered = previewIDs.compactMap { providerByID[$0] }
        let missing = enabledProviders.filter { !previewIDs.contains($0.id) }
        return ordered + missing
    }

    private struct ProviderRowDropDelegate: DropDelegate {
        let targetProviderID: String
        let enabledProviderIDs: [String]
        @Binding var draggingProviderID: String?
        @Binding var previewProviderIDs: [String]?
        @Binding var dropTargetProviderID: String?
        @Binding var dropTargetInsertAfter: Bool
        let onPerformDrop: () -> Bool

        func validateDrop(info: DropInfo) -> Bool {
            draggingProviderID != nil
        }

        func dropEntered(info: DropInfo) {
            updatePreview(with: info)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            updatePreview(with: info)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            if dropTargetProviderID == targetProviderID {
                dropTargetProviderID = nil
            }
        }

        func performDrop(info: DropInfo) -> Bool {
            updatePreview(with: info)
            return onPerformDrop()
        }

        private func updatePreview(with info: DropInfo) {
            guard let draggingProviderID else { return }
            guard draggingProviderID != targetProviderID else {
                dropTargetProviderID = nil
                return
            }

            let insertAfter = info.location.y > 19
            dropTargetProviderID = targetProviderID
            dropTargetInsertAfter = insertAfter

            var ids = previewProviderIDs ?? enabledProviderIDs
            guard let sourceIndex = ids.firstIndex(of: draggingProviderID),
                  let targetIndex = ids.firstIndex(of: targetProviderID) else {
                return
            }

            let destinationIndex = Self.destinationIndex(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                insertAfter: insertAfter
            )

            guard sourceIndex != destinationIndex else { return }

            let moving = ids.remove(at: sourceIndex)
            let insertion = min(max(0, destinationIndex), ids.count)
            ids.insert(moving, at: insertion)
            previewProviderIDs = ids
        }

        private static func destinationIndex(
            sourceIndex: Int,
            targetIndex: Int,
            insertAfter: Bool
        ) -> Int {
            if insertAfter {
                return sourceIndex < targetIndex ? targetIndex : (targetIndex + 1)
            }
            return sourceIndex < targetIndex ? max(0, targetIndex - 1) : targetIndex
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedProvider {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    providerSettingsCard(selectedProvider)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.never)
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
                Text(viewModel.text(.selectProviderHint))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)
                Text(viewModel.localizedText("从左侧选择一个来源后，这里会显示完整配置。", "Choose a source on the left to inspect and edit its full configuration."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var appBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(settingsLanguageTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)
                languageSegmentControl
                Spacer(minLength: 0)
            }
            .frame(height: 24)

            Spacer()
                .frame(height: 24)

            settingsAppearanceModeSection

            Spacer()
                .frame(height: 24)

            VStack(alignment: .leading, spacing: 8) {
                let launchAtLoginBinding = Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                )
                HStack(spacing: 12) {
                    Text(settingsLaunchTitle)
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                    Toggle(
                        "",
                        isOn: launchAtLoginBinding
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    launchAtLoginBinding.wrappedValue.toggle()
                }

                Text(settingsLaunchHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .padding(.leading, 60)
                    .lineLimit(1)
            }
        }
    }

    private var menuBarPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBarMultiUsageSection

            Spacer()
                .frame(height: 24)

            statusBarDisplayStyleSection
        }
    }

    private var generalBasicsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            appBehaviorSection
            dividerLine
            menuBarPreferencesSection
        }
    }

    private var topGeneralSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            generalBasicsSection
            permissionsSection
        }
    }

    private var statusBarMultiUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let multiUsageBinding = Binding(
                get: { viewModel.statusBarMultiUsageEnabled },
                set: { viewModel.setStatusBarMultiUsageEnabled($0) }
            )
            HStack(spacing: 12) {
                Text(settingsStatusBarMultiUsageTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)
                    .frame(width: 48, alignment: .leading)

                Toggle(
                    "",
                    isOn: multiUsageBinding
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .allowsHitTesting(false)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                multiUsageBinding.wrappedValue.toggle()
            }

            Text(settingsStatusBarMultiUsageHint)
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
                .lineSpacing(0)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .padding(.leading, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBarDisplayStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(settingsStatusBarDisplayStyleTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)
                    .frame(width: 48, alignment: .leading)

                statusBarDisplayStyleSegmentControl

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)

            statusBarDisplayStylePreview
                .padding(.leading, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsAppearanceModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(settingsAppearanceModeTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)
                    .frame(width: 48, alignment: .leading)

                settingsAppearanceModeSegmentControl

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsAppearanceModeSegmentControl: some View {
        Picker("", selection: Binding(
            get: { viewModel.statusBarAppearanceMode.id },
            set: { newValue in
                if let mode = StatusBarAppearanceMode.allCases.first(where: { $0.id == newValue }) {
                    viewModel.setStatusBarAppearanceMode(mode)
                }
            }
        )) {
            Text(settingsAppearanceFollowWallpaper).tag(StatusBarAppearanceMode.followWallpaper.id)
            Text(settingsAppearanceDark).tag(StatusBarAppearanceMode.dark.id)
            Text(settingsAppearanceLight).tag(StatusBarAppearanceMode.light.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 240, height: 24)
    }

    private var statusBarDisplayStyleSegmentControl: some View {
        Picker("", selection: Binding(
            get: { viewModel.statusBarDisplayStyle.id },
            set: { newValue in
                if let style = StatusBarDisplayStyle.allCases.first(where: { $0.id == newValue }) {
                    viewModel.setStatusBarDisplayStyle(style)
                }
            }
        )) {
            Text(settingsStatusBarStyleIconPercent).tag(StatusBarDisplayStyle.iconPercent.id)
            Text(settingsStatusBarStyleBarNamePercent).tag(StatusBarDisplayStyle.barNamePercent.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 180, height: 24)
    }

    @ViewBuilder
    private var statusBarDisplayStylePreview: some View {
        switch viewModel.statusBarDisplayStyle {
        case .iconPercent:
            statusBarDisplayStylePreviewIconPercent
        case .barNamePercent:
            statusBarDisplayStylePreviewBarNamePercent
        }
    }

    private var statusBarPreviewCardHeight: CGFloat { 64 }

    private var statusBarDisplayStylePreviewIconPercent: some View {
        let items: [(icon: String, value: String)] = [
            ("menu_codex_icon", "78%"),
            ("menu_claude_icon", "53%"),
            ("menu_kimi_icon", "96%")
        ]
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(settingsUsesLightAppearance ? Color(hex: 0xF4F5F7) : Color.black)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(settingsRowStrokeColor, lineWidth: 1)

            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        if let image = themedBundledImage(named: item.icon) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .opacity(0.8)
                        }
                        Text(item.value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settingsBodyColor)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 16)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 16, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .frame(height: statusBarPreviewCardHeight, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusBarDisplayStylePreviewBarNamePercent: some View {
        let items: [(name: String, value: String, percent: CGFloat)] = [
            ("Codex", "78%", 78),
            ("Claude", "100%", 100),
            ("Kimi", "10%", 10)
        ]
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(settingsUsesLightAppearance ? Color(hex: 0xF4F5F7) : Color.black)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(settingsRowStrokeColor, lineWidth: 1)

            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(settingsQuotaTrackColor)
                                .frame(width: 10, height: 20)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(settingsUsesLightAppearance ? Color.black.opacity(0.72) : Color.white.opacity(0.8))
                                .frame(width: 6, height: max(0, round(16 * item.percent / 100)))
                                .offset(y: -2)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(settingsBodyColor)
                                .lineLimit(1)
                        }
                        .offset(y: 1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 20)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 20, alignment: .leading)
            .offset(y: 1)
            .padding(.horizontal, 24)
        }
        .frame(height: statusBarPreviewCardHeight, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var permissionsSection: some View {
        // 权限相关三大块：授权卡片 / 本地扫描 / 重置数据。
        VStack(alignment: .leading, spacing: 24) {
            permissionAccessSection
            dividerLine
            localDataManagementSection
        }
    }

    private var permissionAccessSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                permissionStatusTile(
                    title: viewModel.text(.permissionNotificationsTitle),
                    hint: viewModel.text(.permissionNotificationsHint),
                    statusText: notificationPermissionStatusText,
                    statusColor: notificationPermissionStatusColor,
                    buttonTitle: notificationActionTitle,
                    buttonMutedStyle: viewModel.hasNotificationPermission
                ) {
                    handlePermissionAction(.notifications)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: permissionTileHeight > 0 ? permissionTileHeight : nil, alignment: .topLeading)

                permissionStatusTile(
                    title: viewModel.text(.permissionKeychainTitle),
                    hint: viewModel.text(.permissionKeychainHint),
                    statusText: keychainPermissionStatusText,
                    statusColor: keychainPermissionStatusColor,
                    buttonTitle: keychainActionTitle,
                    buttonMutedStyle: viewModel.secureStorageReady
                ) {
                    handlePermissionAction(.keychain)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: permissionTileHeight > 0 ? permissionTileHeight : nil, alignment: .topLeading)

                permissionStatusTile(
                    title: viewModel.text(.permissionFullDiskTitle),
                    hint: viewModel.text(.permissionFullDiskHint),
                    statusText: fullDiskPermissionStatusText,
                    statusColor: fullDiskPermissionStatusColor,
                    buttonTitle: fullDiskActionTitle,
                    buttonMutedStyle: viewModel.fullDiskAccessGranted
                ) {
                    handlePermissionAction(.fullDisk)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: permissionTileHeight > 0 ? permissionTileHeight : nil, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .onPreferenceChange(PermissionTileHeightPreferenceKey.self) { newHeight in
                // 同步三张权限卡片到统一最大高度。
                if abs(permissionTileHeight - newHeight) > 0.5 {
                    permissionTileHeight = newHeight
                }
            }
        }
    }

    private var localDataManagementSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            localDiscoverySection
            dividerLine
            resetDataActionRow
        }
    }

    private var localDiscoverySection: some View {
        VStack(alignment: .leading, spacing: localDiscoveryItemSpacing) {
            localDiscoveryHeaderRow

            if let autoDiscoveryResultText {
                localDiscoveryResultRow(autoDiscoveryResultText)
            }

            localDiscoveryPrivacyBanner
        }
    }

    private var localDiscoveryHeaderRow: some View {
        // 扫描区块头部：按 Figma 47:1737 复原（标题/说明 + 右侧按钮）。
        HStack(alignment: .center, spacing: 98) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localDiscoveryTitleText)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                    .lineSpacing(0)
                Text(viewModel.text(.localDiscoveryHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsCapsuleButton(
                autoDiscoveryActionTitle,
                disabled: autoDiscoveryScanning,
                textOpacity: 0.80,
                borderOpacity: 0.80
            ) {
                startAutoDiscoveryScan()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func localDiscoveryResultRow(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(autoDiscoveryResultColor)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localDiscoveryPrivacyBanner: some View {
        Text(viewModel.text(.permissionsPrivacyPromise))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: 0xD87E3E))
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 橙色声明条：撑满容器宽度并保持文字垂直居中。
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: 0xD87E3E), lineWidth: 0.5)
            )
    }

    private var resetDataActionRow: some View {
        // 重置区块：按 Figma 47:1727 复原（行高 50、左右列固定间距 98）。
        HStack(alignment: .center, spacing: 98) {
            VStack(alignment: .leading, spacing: 8) {
                Text(resetSectionTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                    .lineSpacing(0)
                    .frame(height: 12, alignment: .leading)
                Text(viewModel.text(.resetLocalDataHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .frame(height: 30, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsCapsuleButton(resetActionTitle, destructive: true) {
                permissionPrompt = .resetLocalData
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
    }

    private func permissionStatusTile(
        title: String,
        hint: String,
        statusText: String,
        statusColor: Color,
        buttonTitle: String,
        buttonMutedStyle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // 单个权限卡片：标题/说明 + 底部“状态 + 按钮”固定在底部。
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                Text(hint)
                    .font(settingsBodyFont)
                    .foregroundStyle(settingsHintColor)
                    // 多行正文按设计稿 150% 行高。
                    .lineSpacing(settingsBodyMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // 底部操作行固定贴底，避免卡片底部留白过大。
            HStack(spacing: 8) {
                Text(statusText)
                    .font(settingsLabelFont)
                    .foregroundStyle(statusColor)
                Spacer(minLength: 8)
                settingsCapsuleButton(
                    buttonTitle,
                    textOpacity: buttonMutedStyle ? 0.55 : 0.80,
                    borderOpacity: 0.55,
                    action: action
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            settingsGlassSurface(
                cornerRadius: cardCornerRadius,
                fill: settingsSectionFillColor
            )
        )
        .overlay(
            // 权限卡边框颜色：white_30。
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                // 把卡片真实高度上报给 PreferenceKey，用于三卡片等高。
                Color.clear.preference(key: PermissionTileHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    private func permissionActionRow(
        title: String,
        hint: String,
        hintLineSpacing: CGFloat = 2.5,
        titleHintSpacing: CGFloat = 4,
        alignCenter: Bool = false,
        minHeight: CGFloat? = nil,
        buttonTitle: String,
        buttonDisabled: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // 行级“标题说明 + 右侧按钮”布局（用于扫描、重置区域）。
        let rowAlignment: VerticalAlignment = alignCenter ? .center : .top

        return HStack(alignment: rowAlignment, spacing: 16) {
            VStack(alignment: .leading, spacing: titleHintSpacing) {
                Text(title)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                Text(hint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(hintLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            settingsCapsuleButton(buttonTitle, destructive: destructive, disabled: buttonDisabled, action: action)
                // 非居中模式时，按钮略微下移与文字基线对齐。
                .padding(.top, alignCenter ? 0 : 3)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignCenter ? .center : .topLeading)
    }

    private var dividerLine: some View {
        // 通用设置里的细分割线样式（与设计稿统一）。
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
    }

    private var languageSegmentControl: some View {
        Picker("", selection: Binding(
            get: { viewModel.language.id },
            set: { newValue in
                if let language = AppLanguage.allCases.first(where: { $0.id == newValue }) {
                    viewModel.setLanguage(language)
                }
            }
        )) {
            Text(viewModel.text(.chinese)).tag(AppLanguage.zhHans.id)
            Text(viewModel.text(.english)).tag(AppLanguage.en.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 140, height: 24)
    }

    private func settingsCapsuleButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        dismissInputFocus: Bool = false,
        textOpacity: Double = 0.80,
        borderOpacity: Double = 0.55,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if dismissInputFocus {
                dismissEditingFocus()
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(destructive ? Color(hex: 0xD05757) : settingsAccentBlue)
        .disabled(disabled)
    }

    private func dismissEditingFocus() {
        focusedThresholdProviderID = nil
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeFirstResponder(nil)
        }
    }

    private var resetSectionTitle: String {
        viewModel.language == .zhHans ? "重置本地数据" : viewModel.text(.resetLocalDataTitle)
    }

    private var resetActionTitle: String {
        viewModel.language == .zhHans ? "重置所有数据" : viewModel.text(.resetLocalDataAction)
    }

    private var autoDiscoveryResultText: String? {
        let key = PermissionPrompt.autoDiscovery.id
        guard let rawResult = permissionResultMessage[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawResult.isEmpty else {
            return nil
        }

        if rawResult == viewModel.text(.localDiscoveryNothingFound) {
            return viewModel.language == .zhHans
                ? "暂无可识别的模型，请手动添加或再次尝试"
                : "No recognizable models found. Please add one manually or try again."
        }
        return rawResult
    }

    private var autoDiscoveryResultColor: Color {
        let key = PermissionPrompt.autoDiscovery.id
        let rawResult = permissionResultMessage[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawResult == viewModel.text(.localDiscoveryNothingFound) {
            // orange_100
            return Color(hex: 0xD87E3E)
        }
        return Color(hex: 0x69BD64)
    }

    private var autoDiscoveryActionTitle: String {
        if autoDiscoveryScanning {
            return viewModel.language == .zhHans ? "扫描中···" : "Scanning..."
        }
        return viewModel.text(.localDiscoveryAction)
    }

    private func settingsInputPrompt(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(settingsInputPlaceholderColor)
    }

    private func relayProminentTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .relayProminentInput()
    }

    private func relayProminentSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .relayProminentInput()
    }

    private func relayCompactTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .relayCompactInput()
    }

    private var localDiscoveryTitleText: String {
        viewModel.language == .zhHans ? "扫描本地已登录模型" : viewModel.text(.localDiscoveryTitle)
    }

    private var settingsLanguageTitle: String {
        viewModel.language == .zhHans ? "选择语言" : viewModel.text(.language)
    }

    private var settingsLaunchTitle: String {
        viewModel.language == .zhHans ? "开机启动" : viewModel.text(.launchAtLogin)
    }

    private var settingsLaunchHint: String {
        viewModel.language == .zhHans
            ? "勾选后会把 Al Plan Monitor 注册为登录项。建议安装到“应用程序”后再启用"
            : viewModel.text(.launchAtLoginHint)
    }

    private var settingsStatusBarMultiUsageTitle: String {
        viewModel.localizedText("多模展示", "Multi-Model Display")
    }

    private var settingsStatusBarMultiUsageHint: String {
        viewModel.localizedText(
            "开启后状态栏会同时展示多个勾选模型的用量；模型过多时可能挤占菜单栏空间。",
            "When enabled, the menu bar shows usage from multiple selected providers; too many providers may crowd the menu bar."
        )
    }

    private var settingsStatusBarDisplayStyleTitle: String {
        viewModel.text(.statusBarDisplayStyle)
    }

    private var settingsAppearanceModeTitle: String {
        viewModel.text(.statusBarAppearanceMode)
    }

    private var settingsAppearanceFollowWallpaper: String {
        viewModel.text(.statusBarAppearanceFollowWallpaper)
    }

    private var settingsAppearanceDark: String {
        viewModel.text(.statusBarAppearanceDark)
    }

    private var settingsAppearanceLight: String {
        viewModel.text(.statusBarAppearanceLight)
    }

    private var settingsStatusBarStyleIconPercent: String {
        viewModel.text(.statusBarStyleIconPercent)
    }

    private var settingsStatusBarStyleBarNamePercent: String {
        viewModel.text(.statusBarStyleBarNamePercent)
    }

    private var statusAuthorizedText: String {
        viewModel.language == .zhHans ? "已授权" : "Authorized"
    }

    private var statusUnauthorizedText: String {
        viewModel.language == .zhHans ? "未授权" : "Not authorized"
    }

    private var notificationActionTitle: String {
        if viewModel.language == .zhHans {
            return viewModel.hasNotificationPermission ? "取消授权" : "申请授权"
        }
        return viewModel.text(.permissionNotificationsAction)
    }

    private var keychainActionTitle: String {
        if viewModel.language == .zhHans {
            return viewModel.secureStorageReady ? "取消授权" : "启用钥匙串"
        }
        return viewModel.text(.permissionKeychainAction)
    }

    private var fullDiskActionTitle: String {
        if viewModel.language == .zhHans {
            return viewModel.fullDiskAccessGranted ? "取消授权" : "打开设置"
        }
        return viewModel.text(.permissionFullDiskAction)
    }

    private var notificationPermissionStatusText: String {
        viewModel.hasNotificationPermission
            ? statusAuthorizedText
            : statusUnauthorizedText
    }

    private var notificationPermissionStatusColor: Color {
        viewModel.hasNotificationPermission ? Color(hex: 0x69BD64) : Color(hex: 0xD05757)
    }

    private var keychainPermissionStatusText: String {
        viewModel.secureStorageReady
            ? statusAuthorizedText
            : statusUnauthorizedText
    }

    private var keychainPermissionStatusColor: Color {
        viewModel.secureStorageReady ? Color(hex: 0x69BD64) : Color(hex: 0xD05757)
    }

    private var fullDiskPermissionStatusText: String {
        if viewModel.fullDiskAccessGranted {
            return statusAuthorizedText
        }
        return statusUnauthorizedText
    }

    private var fullDiskPermissionStatusColor: Color {
        viewModel.fullDiskAccessGranted ? Color(hex: 0x69BD64) : Color(hex: 0xD05757)
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
                    relayProminentTextField(viewModel.text(.providerName), text: $newProviderName)
                }
                if showBaseURLField {
                    relayProminentTextField(viewModel.text(.baseURL), text: $newProviderBaseURL)
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
                    isNewAPISiteDialogPresented = false
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

    private var newAPISiteDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == .zhHans ? "添加 NewAPI 站点" : "Add NewAPI Site")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            newAPICustomSection

            HStack {
                Spacer(minLength: 0)
                settingsCapsuleButton(viewModel.text(.permissionCancel)) {
                    isNewAPISiteDialogPresented = false
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            settingsGlassSurface(cornerRadius: 16, fill: panelBackground)
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
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
            } else if let image = themedBundledImage(named: relayPresetIconName(for: preset)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else if let image = themedBundledImage(named: "relay_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(settingsBodyColor)
            }

            Text(preset.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? settingsSelectedRowFillColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? settingsSelectedRowStrokeColor : settingsRowStrokeColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let provider {
                selectedProviderID = provider.id
            }
        }
    }

    private func relayPresetIconName(for preset: RelayTemplatePreset) -> String {
        let presetID = preset.id.lowercased()
        if presetID.contains("moonshot") || presetID.contains("moonsho") {
            return "menu_kimi_icon"
        }
        if presetID.contains("deepseek") {
            return firstExistingRelayIconName([
                "menu_deepseek_icon",
                "menu_deep_seek_icon"
            ]) ?? "menu_relay_icon"
        }
        if presetID.contains("xiaomimimo") || presetID.contains("mimo") {
            return firstExistingRelayIconName([
                "menu_mimo_icon",
                "menu_xiaomimimo_icon",
                "menu_xiaomi_mimo_icon"
            ]) ?? "menu_relay_icon"
        }
        if presetID.contains("minimax") || presetID.contains("minimaxi") {
            return firstExistingRelayIconName([
                "menu_minimax_icon",
                "menu_minimaxi_icon"
            ]) ?? "menu_relay_icon"
        }
        return "menu_relay_icon"
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

        if provider.family == .official {
            officialProviderSettingsCard(provider, snapshot: snapshot, error: error)
        } else {
            thirdPartyProviderSettingsCard(provider, snapshot: snapshot, error: error)
        }
    }

    private func providerSettingsHeader(_ provider: ProviderDescriptor) -> some View {
        let enabledBinding = Binding(
            get: { provider.enabled },
            set: { viewModel.setEnabled($0, providerID: provider.id) }
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(sidebarDisplayName(for: provider))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)

                Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .labelsHidden()
                .allowsHitTesting(false)

                Spacer(minLength: 0)
            }
            // 头部标题行：左侧与详情容器保持 16px；上下各 14px。
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                enabledBinding.wrappedValue.toggle()
            }

            dividerLine
                .frame(maxWidth: .infinity)
        }
    }

    private func thirdPartyProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            providerSettingsHeader(provider)

            VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                thirdPartyThresholdRow(provider)

                providerNameToggleRow(title: officialStatusBarTitle, isOn: Binding(
                    get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                    set: { newValue in
                        viewModel.setStatusBarDisplayEnabled(newValue, providerID: provider.id)
                    }
                ))

                if provider.isRelay {
                    thirdPartyUsagePreferenceRow(provider)
                    openRelayConfigSection(provider)
                }
            }
            .padding(.top, modelSettingsItemSpacing)
        }
    }

    private func thirdPartyThresholdRow(_ provider: ProviderDescriptor) -> some View {
        HStack(spacing: thirdPartyConfigLabelSpacing) {
            Text(officialThresholdTitle)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)

            Slider(
                value: Binding(
                    get: { provider.threshold.lowRemaining },
                    set: { newValue in
                        setOfficialThresholdValue(newValue, providerID: provider.id)
                    }
                ),
                in: 0...100
            )
            .frame(width: 200)
            .tint(settingsSliderTintColor)

            officialThresholdStepper(provider)
        }
        .frame(height: 24)
        .onChange(of: provider.threshold.lowRemaining) { _, newValue in
            if focusedThresholdProviderID != provider.id {
                officialThresholdInputs[provider.id] = formattedOfficialThresholdValue(newValue)
            }
        }
        .onChange(of: focusedThresholdProviderID) { oldValue, newValue in
            if oldValue == provider.id, newValue != provider.id {
                applyOfficialThresholdInput(provider)
            }
        }
    }

    private func thirdPartyUsagePreferenceRow(_ provider: ProviderDescriptor) -> some View {
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                thirdPartyQuotaDisplayModeInputs[provider.id]
                    ?? provider.relayConfig?.quotaDisplayMode
                    ?? .remaining
            },
            set: { newValue in
                thirdPartyQuotaDisplayModeInputs[provider.id] = newValue
                viewModel.updateThirdPartyQuotaDisplayMode(
                    providerID: provider.id,
                    quotaDisplayMode: newValue
                )
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            thirdPartyConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
                officialSegmentControl(
                    selection: quotaDisplayBinding,
                    options: [.remaining, .used],
                    label: { mode in
                        switch mode {
                        case .remaining:
                            viewModel.text(.quotaDisplayRemaining)
                        case .used:
                            viewModel.text(.quotaDisplayUsed)
                        }
                    }
                )
            }
            thirdPartyHintText(viewModel.text(.claudeQuotaDisplayHint))
        }
    }

    private func providerNameToggleRow(
        title: String,
        isOn: Binding<Bool>,
        labelWidth: CGFloat = 60,
        spacing: CGFloat = 12
    ) -> some View {
        HStack(spacing: spacing) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: labelWidth, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.wrappedValue.toggle()
        }
    }

    private func officialProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            providerSettingsHeader(provider)

            VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                officialThresholdRow(provider)

                providerNameToggleRow(title: officialStatusBarTitle, isOn: Binding(
                    get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                    set: { newValue in
                        viewModel.setStatusBarDisplayEnabled(newValue, providerID: provider.id)
                    }
                ))

                providerNameToggleRow(title: officialShowEmailTitle, isOn: Binding(
                    get: { viewModel.showOfficialAccountEmailInMenuBar },
                    set: { viewModel.setShowOfficialAccountEmailInMenuBar($0) }
                ))

                providerNameToggleRow(title: officialShowPlanTypeTitle, isOn: Binding(
                    get: { viewModel.showOfficialPlanTypeInMenuBar(providerID: provider.id) },
                    set: { viewModel.setShowOfficialPlanTypeInMenuBar($0, providerID: provider.id) }
                ))

                officialConfigSection(provider)
            }
            .padding(.top, modelSettingsItemSpacing)

            if provider.type == .codex {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(viewModel.language == .zhHans ? "本机Codex账号" : viewModel.text(.codexProfiles))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                codexProfileManagementSection()
                    .padding(.top, 12)
            } else if provider.type == .claude {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(viewModel.localizedText("本机 Claude 账号", "Local Claude Accounts"))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                claudeProfileManagementSection()
                    .padding(.top, 12)
            } else if snapshot != nil || error != nil {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(localOfficialAccountSectionTitle(for: provider))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                officialSingleAccountCardsSection(
                    provider: provider,
                    snapshot: snapshot,
                    error: error
                )
                    .padding(.top, 12)
            }

        }
    }

    private func officialThresholdRow(_ provider: ProviderDescriptor) -> some View {
        HStack(spacing: 12) {
            Text(officialThresholdTitle)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: 60, alignment: .leading)

            Slider(
                value: Binding(
                    get: { provider.threshold.lowRemaining },
                    set: { newValue in
                        setOfficialThresholdValue(newValue, providerID: provider.id)
                    }
                ),
                in: 0...100
            )
            .frame(width: 200)
            .tint(settingsSliderTintColor)

            officialThresholdStepper(provider)
        }
        .frame(height: 24)
        .onChange(of: provider.threshold.lowRemaining) { _, newValue in
            if focusedThresholdProviderID != provider.id {
                officialThresholdInputs[provider.id] = formattedOfficialThresholdValue(newValue)
            }
        }
        .onChange(of: focusedThresholdProviderID) { oldValue, newValue in
            if oldValue == provider.id, newValue != provider.id {
                applyOfficialThresholdInput(provider)
            }
        }
    }

    private func officialThresholdStepper(_ provider: ProviderDescriptor) -> some View {
        Stepper(
            value: Binding(
                get: { provider.threshold.lowRemaining },
                set: { setOfficialThresholdValue($0, providerID: provider.id) }
            ),
            in: 0...100,
            step: 1
        ) {
            Text(formattedOfficialThresholdValue(provider.threshold.lowRemaining))
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: 48, alignment: .trailing)
        }
        .controlSize(.small)
        .frame(width: 118, height: 24)
    }

    private func localOfficialAccountSectionTitle(for provider: ProviderDescriptor) -> String {
        let displayName = sidebarDisplayName(for: provider)
        if viewModel.language == .zhHans {
            return "本机\(displayName)账号"
        }
        return "Local \(displayName) Account"
    }

    @ViewBuilder
    private func officialSingleAccountCardsSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            officialSingleAccountCard(provider: provider, snapshot: snapshot, error: error)
        }
    }

    private func officialSingleAccountCard(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        let status = codexSlotStatus(provider: provider, snapshot: snapshot)
        let metrics = codexQuotaMetrics(provider: provider, snapshot: snapshot)
        let subtitle = officialMonitorSubtitle(snapshot: snapshot)
        let planType = officialMonitorPlanType(providerType: provider.type, snapshot: snapshot)
        let hasError = (error?.isEmpty == false) || snapshot?.valueFreshness == .empty
        let updatedText: String = {
            guard let snapshot else {
                return viewModel.language == .zhHans ? "更新于 --" : "Updated --"
            }
            if viewModel.language == .zhHans {
                return "更新于 \(settingsElapsedText(from: snapshot.updatedAt))"
            }
            return "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: snapshot.updatedAt))"
        }()

        return officialAccountMonitorCard(
            highlightColor: hasError ? Color(hex: 0xD05757) : nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    providerIcon(for: provider, size: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        settingsModelTitleWithPlanType(
                            title: sidebarDisplayName(for: provider),
                            planType: planType
                        )
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
                .frame(height: 24)

                quotaMetricLayout(
                    metrics: metrics,
                    twoByTwo: provider.type == .claude
                )
                .padding(.top, 8)

                if let error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } else if let snapshot,
                          snapshot.valueFreshness == .empty,
                          !snapshot.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(snapshot.note)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                dividerLine
                    .padding(.top, hasError ? 8 : 10)

                HStack(spacing: 8) {
                    Text(viewModel.localizedText("正在使用", "Current"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0x69BD64))

                    Text(updatedText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)

                    Spacer(minLength: 8)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shouldShowOfficialDetailedDataCard(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        switch provider.type {
        case .codex, .claude, .gemini, .kimi:
            return true
        default:
            return false
        }
    }

    private func shouldShowOfficialLocalTrendCard(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        switch provider.type {
        case .codex, .claude, .gemini, .kimi:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func officialDetailedDataSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        let groups = officialDetailedDataGroups(provider: provider, snapshot: snapshot, error: error)

        officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    providerIcon(for: provider, size: 12)
                    Text(viewModel.localizedText("详细数据", "Detailed Data"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        dividerLine
                            .padding(.vertical, 10)
                    } else {
                        Spacer().frame(height: 8)
                    }
                    officialDetailedDataGroupView(group)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func officialDetailedDataGroupView(_ group: OfficialDetailedDataGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if group.rows.isEmpty {
                Text("--")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
            } else {
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.key)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .frame(width: 136, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsBodyColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func officialDetailedDataGroups(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataGroup] {
        let conciseRows = officialDetailedConciseRows(provider: provider, snapshot: snapshot)
        return [
            OfficialDetailedDataGroup(
                id: "concise",
                title: viewModel.localizedText("关键信息", "Key Info"),
                rows: conciseRows
            )
        ]
    }

    private func officialDetailedConciseRows(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> [OfficialDetailedDataRow] {
        let noteValue = detailedValueOrPlaceholder(snapshot?.note)
        let usageSummary = officialDetailedUsageSummaryValue(provider: provider, snapshot: snapshot)

        return [
            OfficialDetailedDataRow(
                id: "concise.note",
                key: "note",
                value: noteValue
            ),
            OfficialDetailedDataRow(
                id: "concise.usage",
                key: viewModel.localizedText("用量", "Usage"),
                value: usageSummary
            )
        ]
    }

    private func officialDetailedUsageSummaryValue(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> String {
        guard provider.type != .gemini else {
            return viewModel.localizedText(
                "本地趋势数据源暂不可用",
                "Local trend source unavailable"
            )
        }

        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let queryKey = localUsageTrendQueryKey(
            providerID: provider.id,
            scope: scope,
            identityCacheKey: identityCacheKey
        )

        let strictSummary = localUsageTrendSummaries[queryKey]
        let summary = localUsageTrendDisplaySummary(
            provider: provider,
            scope: scope,
            identityCacheKey: identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary
        if let summary {
            return localUsageTrendSummaryText(summary)
        }

        if localUsageTrendLoadingQueryKeys.contains(queryKey) {
            return viewModel.localizedText("读取趋势中...", "Loading trend...")
        }

        return viewModel.localizedText("暂无趋势数据", "No trend data")
    }

    private func officialDetailedDataGroupsFull(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataGroup] {
        var groups: [OfficialDetailedDataGroup] = [
            OfficialDetailedDataGroup(
                id: "base",
                title: viewModel.localizedText("基础状态", "Base Status"),
                rows: officialDetailedBaseRows(snapshot: snapshot, error: error)
            ),
            OfficialDetailedDataGroup(
                id: "main-quota",
                title: viewModel.localizedText("主额度", "Primary Quota"),
                rows: officialDetailedMainQuotaRows(snapshot: snapshot)
            )
        ]

        groups.append(
            OfficialDetailedDataGroup(
                id: "quota-windows",
                title: viewModel.localizedText("quotaWindows 明细", "quotaWindows Details"),
                rows: officialDetailedQuotaWindowRows(snapshot: snapshot)
            )
        )
        groups.append(
            OfficialDetailedDataGroup(
                id: "extras",
                title: "extras",
                rows: officialDetailedDictionaryRows(
                    snapshot?.extras ?? [:],
                    prefix: "extras",
                    maskSensitive: true
                )
            )
        )
        groups.append(
            OfficialDetailedDataGroup(
                id: "rawMeta",
                title: "rawMeta",
                rows: officialDetailedDictionaryRows(
                    snapshot?.rawMeta ?? [:],
                    prefix: "rawMeta",
                    maskSensitive: true
                )
            )
        )

        return groups
    }

    private func officialDetailedBaseRows(
        snapshot: UsageSnapshot?,
        error: String?
    ) -> [OfficialDetailedDataRow] {
        var rows: [OfficialDetailedDataRow] = []

        if let snapshot {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.source",
                    key: "source",
                    value: snapshot.source
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.status",
                    key: "status",
                    value: snapshot.status.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.fetchHealth",
                    key: "fetchHealth",
                    value: snapshot.fetchHealth.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.freshness",
                    key: "valueFreshness",
                    value: snapshot.valueFreshness.rawValue
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.updatedAt",
                    key: "updatedAt",
                    value: isoDateText(snapshot.updatedAt)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.sourceLabel",
                    key: "sourceLabel",
                    value: detailedValueOrPlaceholder(snapshot.sourceLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.accountLabel",
                    key: "accountLabel",
                    value: detailedValueOrPlaceholder(snapshot.accountLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.authSourceLabel",
                    key: "authSourceLabel",
                    value: detailedValueOrPlaceholder(snapshot.authSourceLabel)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.diagnosticCode",
                    key: "diagnosticCode",
                    value: detailedValueOrPlaceholder(snapshot.diagnosticCode)
                )
            )
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.note",
                    key: "note",
                    value: detailedValueOrPlaceholder(snapshot.note)
                )
            )
        } else {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.snapshot",
                    key: "snapshot",
                    value: viewModel.localizedText("暂无快照", "No snapshot")
                )
            )
        }

        if let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(
                OfficialDetailedDataRow(
                    id: "base.error",
                    key: "error",
                    value: error
                )
            )
        }

        return rows
    }

    private func officialDetailedMainQuotaRows(snapshot: UsageSnapshot?) -> [OfficialDetailedDataRow] {
        guard let snapshot else {
            return [
                OfficialDetailedDataRow(
                    id: "main-quota.snapshot",
                    key: "quota",
                    value: viewModel.localizedText("暂无快照", "No snapshot")
                )
            ]
        }
        return [
            OfficialDetailedDataRow(
                id: "main-quota.remaining",
                key: "remaining",
                value: snapshot.remaining.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.used",
                key: "used",
                value: snapshot.used.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.limit",
                key: "limit",
                value: snapshot.limit.map { String(format: "%.2f", $0) } ?? "-"
            ),
            OfficialDetailedDataRow(
                id: "main-quota.unit",
                key: "unit",
                value: detailedValueOrPlaceholder(snapshot.unit)
            )
        ]
    }

    private func officialDetailedQuotaWindowRows(snapshot: UsageSnapshot?) -> [OfficialDetailedDataRow] {
        guard let snapshot, !snapshot.quotaWindows.isEmpty else {
            return [
                OfficialDetailedDataRow(
                    id: "quota-windows.none",
                    key: "windows",
                    value: viewModel.localizedText("暂无数据", "No data")
                )
            ]
        }

        return snapshot.quotaWindows.enumerated().map { index, window in
            OfficialDetailedDataRow(
                id: "quota-windows.\(window.id).\(index)",
                key: "window[\(index)]",
                value: "id=\(window.id) | title=\(window.title) | kind=\(window.kind.rawValue) | remainingPercent=\(String(format: "%.2f", window.remainingPercent)) | usedPercent=\(String(format: "%.2f", window.usedPercent)) | resetAt=\(window.resetAt.map(isoDateText) ?? "-")"
            )
        }
    }

    private func officialDetailedDictionaryRows(
        _ values: [String: String],
        prefix: String,
        maskSensitive: Bool
    ) -> [OfficialDetailedDataRow] {
        guard !values.isEmpty else {
            return [
                OfficialDetailedDataRow(
                    id: "\(prefix).none",
                    key: prefix,
                    value: viewModel.localizedText("暂无数据", "No data")
                )
            ]
        }

        return values.keys.sorted().map { key in
            let rawValue = values[key] ?? ""
            let displayValue = maskSensitive
                ? maskedDetailedValue(forKey: key, rawValue: rawValue)
                : detailedValueOrPlaceholder(rawValue)
            return OfficialDetailedDataRow(
                id: "\(prefix).\(key)",
                key: key,
                value: displayValue
            )
        }
    }

    @ViewBuilder
    private func officialLocalTrendSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        showsDivider: Bool = true,
        title: String? = nil
    ) -> some View {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let queryKey = localUsageTrendQueryKey(
            providerID: provider.id,
            scope: scope,
            identityCacheKey: identityCacheKey
        )
        let loading = localUsageTrendLoadingQueryKeys.contains(queryKey)
        let error = localUsageTrendErrors[queryKey]
        let strictSummary = localUsageTrendSummaries[queryKey]
        let summary = localUsageTrendDisplaySummary(
            provider: provider,
            scope: scope,
            identityCacheKey: identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary
        let hasTrendData = summary.map(localUsageTrendHasData) ?? false
        let chartStatus = localUsageTrendChartStatus(
            provider: provider,
            scope: scope,
            summary: summary,
            loading: loading,
            error: error,
            hasData: hasTrendData
        )
        let displaySummary = hasTrendData ? summary : nil

        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                dividerLine
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(title ?? viewModel.localizedText("使用趋势", "Usage Trend"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)

                    Spacer(minLength: 12)

                    if let summary {
                        MiniSparkline(
                            dataPoints: localUsageTrendSparklineValues(summary),
                            color: settingsTrendPrimaryColor,
                            lineWidth: 1.8,
                            showsFill: false
                        )
                        .frame(width: 92, height: 24)
                        .opacity(localUsageTrendHasData(summary) ? 1 : 0.45)
                        .help(localUsageTrendSummaryText(summary))
                    }
                }

                if localUsageTrendSupportsCurrentAccountScope(provider.type) {
                    localUsageTrendControls(
                        provider: provider,
                        scope: scope,
                        selectedAccountKey: selectedAccountKey,
                        accountOptions: accountOptions
                    )
                    .padding(.top, 16)
                }

                localUsageTrendSummaryCapsule(displaySummary)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 24) {
                    localUsageHourlyTrendSection(
                        points: displaySummary?.hourly24 ?? [],
                        status: chartStatus,
                        hideVisualization: displaySummary == nil
                    )
                    localUsageWeeklyTrendSection(
                        points: displaySummary?.daily7 ?? [],
                        status: chartStatus,
                        hideVisualization: displaySummary == nil
                    )
                }
                .padding(.top, 16)
            }
            .padding(.top, showsDivider ? 24 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshLocalUsageTrendIfNeeded(provider: provider, snapshot: snapshot)
        }
        .onChange(of: scope) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot,
                force: true
            )
        }
        .onChange(of: selectedAccountKey) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot,
                force: true
            )
        }
        .onChange(of: identityCacheKey) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot,
                force: true
            )
        }
    }

    private func localUsageTrendResolvedSummary(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> LocalUsageSummary? {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let queryKey = localUsageTrendQueryKey(
            providerID: provider.id,
            scope: scope,
            identityCacheKey: identityCacheKey
        )
        let strictSummary = localUsageTrendSummaries[queryKey]
        return localUsageTrendDisplaySummary(
            provider: provider,
            scope: scope,
            identityCacheKey: identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary
    }

    private func localUsageTrendSparklineValues(_ summary: LocalUsageSummary?) -> [Double] {
        guard let summary else { return [] }
        let points = localUsageWeeklyDisplayPoints(summary.daily7)
        let metric = localUsageTrendDisplayMetric(points: points)
        return points.map { localUsageTrendValue($0, metric: metric) }
    }

    private func localUsageTrendSparklineCaption(_ summary: LocalUsageSummary?) -> String {
        guard let summary else {
            return viewModel.localizedText("等待本地趋势", "Waiting for local trend")
        }
        return "\(viewModel.localizedText("今日", "Today")) \(localUsageTrendSummaryValueText(summary.today))"
    }

    @ViewBuilder
    private func localUsageTrendControls(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        selectedAccountKey: String?,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> some View {
        let showsAccountSelector = scope == .currentAccount && !accountOptions.isEmpty

        if showsAccountSelector {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    Spacer(minLength: 12)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, height: 24, alignment: .trailing)
                    .frame(height: 24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, alignment: .leading)
                    .frame(height: 24)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                localUsageTrendScopeSegmentControl(provider: provider)
                    .frame(width: localUsageTrendScopeControlWidth, height: 24)
                Spacer(minLength: 0)
            }
        }
    }

    private var localUsageTrendScopeControlWidth: CGFloat {
        viewModel.language == .zhHans ? 140 : 170
    }

    private func localUsageTrendScopeSegmentControl(provider: ProviderDescriptor) -> some View {
        Picker("", selection: Binding(
            get: { localUsageTrendScope(for: provider).id },
            set: { newValue in
                if let scope = LocalUsageTrendScope.allCases.first(where: { $0.id == newValue }) {
                    localUsageTrendScopeBinding(for: provider).wrappedValue = scope
                }
            }
        )) {
            Text(viewModel.localizedText("全量", "All")).tag(LocalUsageTrendScope.allAccounts.id)
            Text(viewModel.localizedText("按账号", "By Account")).tag(LocalUsageTrendScope.currentAccount.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(height: 24)
    }

    private func localUsageTrendEmptyHintText(for provider: ProviderDescriptor) -> String {
        if provider.type == .gemini {
            return viewModel.localizedText("本地趋势数据源暂不可用", "Local trend source unavailable")
        }
        return viewModel.localizedText("暂无趋势数据", "No trend data")
    }

    @ViewBuilder
    private func localUsageHourlyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : points

        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("24小时趋势", "24h Trend"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 50
                )
                .padding(.top, 12)
            } else {
                localUsageHourlyTrendBars(points: displayPoints)
                    .padding(.top, 12)
            }

            localUsageHourlyAxisLabels(points: displayPoints)
                .padding(.top, 8)
        }
    }

    private func localUsageHourlyTrendBars(points: [LocalUsageTrendPoint]) -> some View {
        GeometryReader { proxy in
            let metric = localUsageTrendDisplayMetric(points: points)
            let values = points.map { localUsageTrendValue($0, metric: metric) }
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(points.count, 1)
            let barWidth: CGFloat = 12
            let maxBarHeight: CGFloat = 50
            let minBarHeight: CGFloat = 6

            ZStack(alignment: .bottomLeading) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let value = localUsageTrendValue(point, metric: metric)
                    let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
                    let barHeight = value > 0
                        ? max(minBarHeight, maxBarHeight * ratio)
                        : minBarHeight
                    let isHovered = localUsageTrendHoveredHourlyPointID == point.id
                    let centerX = localUsageHourlyTrendBarCenterX(
                        index: index,
                        count: count,
                        width: proxy.size.width,
                        barWidth: barWidth
                    )

                    ZStack(alignment: .bottom) {
                        Color.clear
                        Capsule()
                            .fill(localUsageTrendBarColor(value: value, isHovered: isHovered))
                            .frame(width: barWidth, height: barHeight)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isHovered ? settingsBodyColor.opacity(0.35) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .frame(width: barWidth, height: maxBarHeight, alignment: .bottom)
                    .contentShape(Rectangle())
                    .position(
                        x: centerX,
                        y: proxy.size.height - maxBarHeight / 2
                    )
                    .help(localUsageTrendTooltipHelpText(point, timeStyle: .hourly))
                    .onHover { hovering in
                        if hovering {
                            localUsageTrendHoveredHourlyPointID = point.id
                        } else if localUsageTrendHoveredHourlyPointID == point.id {
                            localUsageTrendHoveredHourlyPointID = nil
                        }
                    }
                }

                if let hoveredPoint = points.first(where: { $0.id == localUsageTrendHoveredHourlyPointID }),
                   let hoveredIndex = points.firstIndex(where: { $0.id == hoveredPoint.id }) {
                    let tooltipWidth = localUsageTrendTooltipWidth
                    let centerX = localUsageHourlyTrendBarCenterX(
                        index: hoveredIndex,
                        count: count,
                        width: proxy.size.width,
                        barWidth: barWidth
                    )
                    let tooltipX = min(
                        max(tooltipWidth / 2, centerX),
                        max(tooltipWidth / 2, proxy.size.width - tooltipWidth / 2)
                    )

                    localUsageTrendTooltip(point: hoveredPoint, timeStyle: .hourly)
                        .frame(width: tooltipWidth, alignment: .leading)
                        .position(x: tooltipX, y: 17)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(.easeInOut(duration: 0.12), value: localUsageTrendHoveredHourlyPointID)
        }
        .frame(height: 50)
    }

    private var localUsageTrendTooltipWidth: CGFloat {
        viewModel.language == .zhHans ? 138 : 154
    }

    private func localUsageHourlyTrendBarCenterX(
        index: Int,
        count: Int,
        width: CGFloat,
        barWidth: CGFloat
    ) -> CGFloat {
        let safeWidth = max(width, barWidth)
        guard count > 1 else { return safeWidth / 2 }
        let step = max(0, (safeWidth - barWidth) / CGFloat(count - 1))
        return CGFloat(index) * step + barWidth / 2
    }

    private func localUsageTrendBarColor(value: Double, isHovered: Bool) -> Color {
        if isHovered {
            return settingsUsesLightAppearance ? settingsAccentBlue : Color.white.opacity(0.90)
        }
        return value > 0 ? settingsTrendPrimaryColor : settingsTrendMutedColor
    }

    private enum LocalUsageTrendTooltipTimeStyle {
        case hourly
        case daily
    }

    private func localUsageTrendTooltip(
        point: LocalUsageTrendPoint,
        timeStyle: LocalUsageTrendTooltipTimeStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localUsageTrendTooltipTimeText(point.startAt, style: timeStyle))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)

            Text(localUsageTrendTooltipText(point))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(settingsHintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(settingsPopoverFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(settingsUsesLightAppearance ? 0.12 : 0.28), radius: 8, y: 4)
    }

    private func localUsageTrendTooltipHelpText(
        _ point: LocalUsageTrendPoint,
        timeStyle: LocalUsageTrendTooltipTimeStyle
    ) -> String {
        "\(localUsageTrendTooltipTimeText(point.startAt, style: timeStyle)) \(localUsageTrendTooltipText(point))"
    }

    private func localUsageTrendTooltipText(_ point: LocalUsageTrendPoint) -> String {
        let tokens = LocalTrendValueFormatter.metricValueText(
            value: point.totalTokens,
            metric: .tokens,
            language: viewModel.language
        )
        let responses = localUsageTrendResponseText(point.responses)
        return "\(tokens) · \(responses)"
    }

    private func localUsageTrendTooltipTimeText(
        _ date: Date,
        style: LocalUsageTrendTooltipTimeStyle
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = viewModel.language == .zhHans
            ? Locale(identifier: "zh_Hans_CN")
            : Locale(identifier: "en_US_POSIX")
        switch (style, viewModel.language) {
        case (.hourly, .zhHans):
            formatter.dateFormat = "M月d日 HH:00"
        case (.hourly, .en):
            formatter.dateFormat = "MMM d, HH:00"
        case (.daily, .zhHans):
            formatter.dateFormat = "M月d日"
        case (.daily, .en):
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func localUsageHourlyAxisLabels(points: [LocalUsageTrendPoint]) -> some View {
        if !points.isEmpty {
            GeometryReader { proxy in
                let count = max(points.count, 1)
                let barWidth: CGFloat = 12
                let step = count > 1 ? (proxy.size.width - barWidth) / CGFloat(count - 1) : 0

                ZStack(alignment: .topLeading) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let rawX = CGFloat(index) * step + barWidth / 2
                        let clampedX = min(max(12, rawX), max(12, proxy.size.width - 12))
                        Text(localUsageHourlyLabel(point.startAt))
                            .frame(width: 24, alignment: .center)
                            .position(
                                x: clampedX,
                                y: 7
                            )
                    }
                }
            }
            .frame(height: 14)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(settingsHintColor)
        } else {
            Color.clear
                .frame(height: 14)
        }
    }

    @ViewBuilder
    private func localUsageWeeklyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : localUsageWeeklyDisplayPoints(points)
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("7天趋势", "7d Trend"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 50
                )
                .padding(.top, 12)
            } else {
                localUsageWeeklyTrendChart(points: displayPoints)
                    .padding(.top, 12)
            }

            HStack(spacing: 0) {
                ForEach(displayPoints) { point in
                        Text(localUsageWeeklyLabel(point.startAt))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            .padding(.top, 8)
        }
    }

    private func localUsageTrendStatusPlaceholder(
        text: String,
        color: Color,
        height: CGFloat
    ) -> some View {
        ZStack {
            Color.clear
            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func localUsageWeeklyTrendChart(points: [LocalUsageTrendPoint]) -> some View {
        GeometryReader { proxy in
            let metric = localUsageTrendDisplayMetric(points: points)
            let values = points.map { localUsageTrendValue($0, metric: metric) }
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(points.count, 1)

            ZStack(alignment: .topLeading) {
                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = localUsageWeeklyTrendPointX(
                            index: index,
                            count: count,
                            width: proxy.size.width
                        )
                        let y = localUsageTrendY(
                            value: localUsageTrendValue(point, metric: metric),
                            maxValue: maxValue,
                            height: proxy.size.height
                        )
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    settingsTrendPrimaryColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                if let hoveredPoint = points.first(where: { $0.id == localUsageTrendHoveredWeeklyPointID }),
                   let hoveredIndex = points.firstIndex(where: { $0.id == hoveredPoint.id }) {
                    let value = localUsageTrendValue(hoveredPoint, metric: metric)
                    let x = localUsageWeeklyTrendPointX(
                        index: hoveredIndex,
                        count: count,
                        width: proxy.size.width
                    )
                    let y = localUsageTrendY(value: value, maxValue: maxValue, height: proxy.size.height)

                    Rectangle()
                        .fill(settingsTrendPrimaryColor.opacity(0.18))
                        .frame(width: 1, height: proxy.size.height)
                        .position(x: x, y: proxy.size.height / 2)

                    Circle()
                        .fill(localUsageTrendBarColor(value: value, isHovered: true))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(settingsPopoverFillColor, lineWidth: 2)
                        )
                        .position(x: x, y: y)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            if let point = localUsageWeeklyTrendPoint(
                                atX: location.x,
                                points: points,
                                width: proxy.size.width
                            ) {
                                localUsageTrendHoveredWeeklyPointID = point.id
                            }
                        case .ended:
                            localUsageTrendHoveredWeeklyPointID = nil
                        }
                    }

                if let hoveredPoint = points.first(where: { $0.id == localUsageTrendHoveredWeeklyPointID }),
                   let hoveredIndex = points.firstIndex(where: { $0.id == hoveredPoint.id }) {
                    let tooltipWidth = localUsageTrendTooltipWidth
                    let centerX = localUsageWeeklyTrendPointX(
                        index: hoveredIndex,
                        count: count,
                        width: proxy.size.width
                    )
                    let tooltipX = min(
                        max(tooltipWidth / 2, centerX),
                        max(tooltipWidth / 2, proxy.size.width - tooltipWidth / 2)
                    )

                    localUsageTrendTooltip(point: hoveredPoint, timeStyle: .daily)
                        .frame(width: tooltipWidth, alignment: .leading)
                        .position(x: tooltipX, y: 17)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.12), value: localUsageTrendHoveredWeeklyPointID)
        }
        .frame(height: 50)
    }

    private func localUsageWeeklyTrendPoint(
        atX x: CGFloat,
        points: [LocalUsageTrendPoint],
        width: CGFloat
    ) -> LocalUsageTrendPoint? {
        guard !points.isEmpty else { return nil }
        let safeWidth = max(width, 1)
        let clampedX = min(max(0, x), safeWidth.nextDown)
        let index = min(
            points.count - 1,
            max(0, Int(clampedX / safeWidth * CGFloat(points.count)))
        )
        return points[index]
    }

    private func localUsageWeeklyTrendPointX(
        index: Int,
        count: Int,
        width: CGFloat
    ) -> CGFloat {
        let safeCount = max(count, 1)
        let stepX = max(width, 1) / CGFloat(safeCount)
        return stepX * (CGFloat(index) + 0.5)
    }

    private func localUsageTrendDisplayMetric(points: [LocalUsageTrendPoint]) -> LocalTrendDisplayMetric {
        if points.contains(where: { $0.totalTokens > 0 }) {
            return .tokens
        }
        return .responses
    }

    private func localUsageTrendValue(_ point: LocalUsageTrendPoint, metric: LocalTrendDisplayMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(max(0, point.totalTokens))
        case .responses:
            return Double(max(0, point.responses))
        }
    }

    private func localUsageTrendY(value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let drawableHeight = max(8, height - 6)
        let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
        return height - max(3, drawableHeight * ratio + 3)
    }

    private func localUsageWeeklyLabel(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: date)
        if viewModel.language == .zhHans {
            switch weekday {
            case 2: return "周一"
            case 3: return "周二"
            case 4: return "周三"
            case 5: return "周四"
            case 6: return "周五"
            case 7: return "周六"
            default: return "周天"
            }
        }
        switch weekday {
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "Sun"
        }
    }

    private func localUsageHourlyLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func localUsageTrendSummaryCapsule(_ summary: LocalUsageSummary?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if let summary {
                HStack(spacing: 16) {
                    localUsageTrendSummaryItem(
                        label: viewModel.localizedText("今日", "Today"),
                        period: summary.today
                    )
                    localUsageTrendSummaryItem(
                        label: viewModel.localizedText("昨日", "Yesterday"),
                        period: summary.yesterday
                    )
                }

                Spacer(minLength: 0)

                localUsageTrendSummaryItem(
                    label: viewModel.localizedText("近30日", "Last 30d"),
                    period: summary.last30Days
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(settingsRowStrokeColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func localUsageTrendSummaryItem(label: String, period: LocalUsagePeriodSummary) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(settingsHintColor)

            Text(LocalTrendValueFormatter.metricValueText(value: period.totalTokens, metric: .tokens, language: viewModel.language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            localUsageTrendSummaryDivider

            Text(localUsageTrendResponseText(period.responses))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .allowsTightening(true)
    }

    private var localUsageTrendSummaryDivider: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(settingsRowStrokeColor)
            .frame(width: 1, height: 8)
    }

    private func localUsageTrendSummaryValueText(_ period: LocalUsagePeriodSummary) -> String {
        let tokens = LocalTrendValueFormatter.metricValueText(value: period.totalTokens, metric: .tokens, language: viewModel.language)
        let responses = localUsageTrendResponseText(period.responses)
        return "\(tokens) | \(responses)"
    }

    private func localUsageTrendResponseText(_ value: Int) -> String {
        let compact = LocalTrendValueFormatter.compactNumber(max(0, value), language: viewModel.language)
        switch viewModel.language {
        case .zhHans:
            if let last = compact.last, last == "万" || last == "亿" {
                let number = String(compact.dropLast())
                return "\(number) \(last)次"
            }
            return "\(compact) 次"
        case .en:
            return "\(compact) req"
        }
    }

    private func localUsageTrendHasData(_ summary: LocalUsageSummary) -> Bool {
        if summary.today.totalTokens > 0 || summary.today.responses > 0 { return true }
        if summary.yesterday.totalTokens > 0 || summary.yesterday.responses > 0 { return true }
        if summary.last30Days.totalTokens > 0 || summary.last30Days.responses > 0 { return true }
        if summary.hourly24.contains(where: { $0.totalTokens > 0 || $0.responses > 0 }) { return true }
        if summary.daily7.contains(where: { $0.totalTokens > 0 || $0.responses > 0 }) { return true }
        return false
    }

    private func localUsageTrendChartStatus(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        summary: LocalUsageSummary?,
        loading: Bool,
        error: String?,
        hasData: Bool
    ) -> LocalUsageTrendChartStatus? {
        if loading {
            return LocalUsageTrendChartStatus(
                text: viewModel.localizedText("加载中...", "Loading..."),
                color: settingsMutedHintColor
            )
        }
        if let error, !error.isEmpty {
            return LocalUsageTrendChartStatus(
                text: error,
                color: Color(hex: 0xD05757)
            )
        }
        if !hasData {
            if provider.type == .codex, scope == .currentAccount {
                if let diagnostics = summary?.diagnostics,
                   diagnostics.unattributedResponses > 0 || diagnostics.unattributedTokens > 0 {
                    let unattributedResponses = formattedSettingsInteger(diagnostics.unattributedResponses)
                    let unattributedTokens = formattedSettingsInteger(diagnostics.unattributedTokens)
                    let text = viewModel.localizedText(
                        "当前账号暂无可归属事件（未归属 \(unattributedResponses) 条/\(unattributedTokens) Token）",
                        "No attributable events for current account (Unattributed \(unattributedResponses)/\(unattributedTokens) tokens)"
                    )
                    return LocalUsageTrendChartStatus(
                        text: text,
                        color: settingsMutedHintColor
                    )
                }
                return LocalUsageTrendChartStatus(
                    text: viewModel.localizedText("当前账号暂无可归属事件", "No attributable events for current account"),
                    color: settingsMutedHintColor
                )
            }
            let noDataText = provider.type == .gemini
                ? localUsageTrendEmptyHintText(for: provider)
                : viewModel.localizedText("暂无数据", "No data")
            return LocalUsageTrendChartStatus(
                text: noDataText,
                color: settingsMutedHintColor
            )
        }
        return nil
    }

    private func localUsageWeeklyDisplayPoints(_ points: [LocalUsageTrendPoint]) -> [LocalUsageTrendPoint] {
        guard points.count == 7 else { return points }
        return points.sorted { lhs, rhs in
            localUsageWeekdayOrder(lhs.startAt) < localUsageWeekdayOrder(rhs.startAt)
        }
    }

    private func localUsageWeekdayOrder(_ date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        switch calendar.component(.weekday, from: date) {
        case 2: return 0
        case 3: return 1
        case 4: return 2
        case 5: return 3
        case 6: return 4
        case 7: return 5
        default: return 6
        }
    }

    @ViewBuilder
    private func localUsageTrendAccountSelector(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let resolved = options.first(where: { $0.id == selectedAccountKey }) ?? options.first
        let isExpanded = localUsageTrendExpandedAccountSelectorProviderID == providerID
        let selectorText = localUsageTrendTrimmed(resolved?.selectorLabel)
            ?? viewModel.localizedText("请选择账号", "Select account")

        Button {
            localUsageTrendExpandedAccountSelectorProviderID = isExpanded ? nil : providerID
        } label: {
            HStack(spacing: 8) {
                Text(selectorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
                    .frame(width: 14, height: 14, alignment: .center)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsControlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(settingsControlStrokeColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: localUsageTrendAccountSelectorExpandedBinding(providerID: providerID),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            localUsageTrendAccountSelectorPopover(
                providerID: providerID,
                selectedAccountKey: selectedAccountKey,
                options: options
            )
        }
    }

    private func localUsageTrendAccountSelectorExpandedBinding(providerID: String) -> Binding<Bool> {
        Binding(
            get: { localUsageTrendExpandedAccountSelectorProviderID == providerID },
            set: { isPresented in
                if isPresented {
                    localUsageTrendExpandedAccountSelectorProviderID = providerID
                } else if localUsageTrendExpandedAccountSelectorProviderID == providerID {
                    localUsageTrendExpandedAccountSelectorProviderID = nil
                }
            }
        )
    }

    private func localUsageTrendAccountSelectorPopover(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let selectedID = selectedAccountKey ?? options.first?.id
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                Button {
                    localUsageTrendSelectedAccountKeys[providerID] = option.id
                    localUsageTrendExpandedAccountSelectorProviderID = nil
                } label: {
                    HStack(spacing: 8) {
                        Text(option.label)
                            .font(.system(size: 12, weight: option.id == selectedID ? .semibold : .regular))
                            .foregroundStyle(option.id == selectedID ? settingsTitleColor : settingsBodyColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if option.id == selectedID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(settingsAccentBlue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(option.id == selectedID ? settingsPopoverSelectedFillColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(settingsPopoverFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(settingsControlStrokeColor, lineWidth: 1)
        )
    }

    private func localUsageTrendSummaryText(_ summary: LocalUsageSummary) -> String {
        let today = "\(viewModel.localizedText("今日", "Today")) \(localUsageTrendSummaryValueText(summary.today))"
        let yesterday = "\(viewModel.localizedText("昨日", "Yesterday")) \(localUsageTrendSummaryValueText(summary.yesterday))"
        let last30 = "\(viewModel.localizedText("近30日", "Last 30d")) \(localUsageTrendSummaryValueText(summary.last30Days))"
        return "\(today) · \(yesterday) · \(last30)"
    }

    private func localUsageTrendDiagnosticText(_ summary: LocalUsageSummary) -> String? {
        guard let diagnostics = summary.diagnostics else { return nil }
        let latestText = localUsageTrendDiagnosticTimeText(diagnostics.latestEventAt)
        let modeText = localUsageTrendDiagnosticSourceText(diagnostics.source)
        let recoveredResponses = formattedSettingsInteger(diagnostics.recoveredByConversationResponses)
        let recoveredTokens = formattedSettingsInteger(diagnostics.recoveredByConversationTokens)
        let unattributedResponses = formattedSettingsInteger(diagnostics.unattributedResponses)
        let unattributedTokens = formattedSettingsInteger(diagnostics.unattributedTokens)
        if viewModel.language == .zhHans {
            return "匹配事件 \(formattedSettingsInteger(diagnostics.matchedRows)) 条 · 可归属 \(formattedSettingsInteger(diagnostics.attributableEvents)) 条 · 会话回填 \(recoveredResponses) 条/\(recoveredTokens) Token · 未归属 \(unattributedResponses) 条/\(unattributedTokens) Token · 最近事件 \(latestText) · 口径 \(modeText)"
        }
        return "Matched \(formattedSettingsInteger(diagnostics.matchedRows)) · Attributable \(formattedSettingsInteger(diagnostics.attributableEvents)) · Recovered \(recoveredResponses)/\(recoveredTokens) tokens · Unattributed \(unattributedResponses)/\(unattributedTokens) tokens · Latest \(latestText) · Mode \(modeText)"
    }

    private func localUsageTrendDiagnosticSourceText(_ source: LocalUsageTrendDiagnosticsSource) -> String {
        switch source {
        case .strict:
            return viewModel.localizedText("严格", "strict")
        case .approximate:
            return viewModel.localizedText("近似", "approx")
        case .sessions:
            return viewModel.localizedText("会话", "sessions")
        }
    }

    private func localUsageTrendDiagnosticTimeText(_ date: Date?) -> String {
        guard let date else {
            return viewModel.localizedText("无", "n/a")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.language == .zhHans ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = viewModel.language == .zhHans ? "MM-dd HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }

    private func localUsageTrendDataSourceText(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        summary: LocalUsageSummary?
    ) -> String {
        _ = summary
        switch provider.type {
        case .codex:
            if scope == .allAccounts {
                return viewModel.localizedText(
                    "数据来源：本地 ~/.codex/sessions（仅本地 Token，不等价于官方剩余额度）",
                    "Data source: local ~/.codex/sessions (local token usage only, not official remaining quota)."
                )
            }
            return viewModel.localizedText(
                "数据来源：本地 ~/.codex/logs_2.sqlite（当前账号可归属事件；缺失身份会按会话回填，仍无法归属会单独提示，仅本地 Token，不等价于官方剩余额度）",
                "Data source: local ~/.codex/logs_2.sqlite attributable events for current account; missing identity is recovered by conversation when possible, and still-unattributed events are shown separately (local token usage only, not official remaining quota)."
            )
        case .claude:
            if scope == .allAccounts {
                return viewModel.localizedText(
                    "数据来源：本地 ~/.claude/projects + 已绑定 CLAUDE_CONFIG_DIR/projects（仅本地 Token，不等价于官方剩余额度）",
                    "Data source: local ~/.claude/projects + bound CLAUDE_CONFIG_DIR/projects (local token usage only, not official remaining quota)."
                )
            }
            return viewModel.localizedText(
                "数据来源：当前账号 CLAUDE_CONFIG_DIR/projects（目录不可用时回退 ~/.claude/projects，仅本地 Token）",
                "Data source: current account CLAUDE_CONFIG_DIR/projects (fallback to ~/.claude/projects when missing, local token usage only)."
            )
        case .kimi:
            return viewModel.localizedText(
                "数据来源：本地 ~/.kimi/sessions/**/wire.jsonl（仅本地 Token，不等价于官方剩余额度）",
                "Data source: local ~/.kimi/sessions/**/wire.jsonl (local token usage only, not official remaining quota)."
            )
        case .gemini:
            return viewModel.localizedText(
                "数据来源：本地 ~/.gemini（当前未发现稳定 token 事件流，后续补齐）",
                "Data source: local ~/.gemini (stable token event stream not found yet; coming later)."
            )
        default:
            return viewModel.localizedText(
                "数据来源：本地日志（仅本地 Token）",
                "Data source: local logs (local token usage only)."
            )
        }
    }

    private func localUsageTrendSupportsCurrentAccountScope(_ providerType: ProviderType) -> Bool {
        switch providerType {
        case .codex, .claude:
            return true
        default:
            return false
        }
    }

    private func localUsageTrendScope(for provider: ProviderDescriptor) -> LocalUsageTrendScope {
        let fallback: LocalUsageTrendScope = localUsageTrendSupportsCurrentAccountScope(provider.type)
            ? .allAccounts
            : .allAccounts
        guard let stored = localUsageTrendScopes[provider.id] else {
            return fallback
        }
        if !localUsageTrendSupportsCurrentAccountScope(provider.type) {
            return .allAccounts
        }
        return stored
    }

    private func localUsageTrendScopeBinding(for provider: ProviderDescriptor) -> Binding<LocalUsageTrendScope> {
        Binding(
            get: { localUsageTrendScope(for: provider) },
            set: { newValue in
                if localUsageTrendSupportsCurrentAccountScope(provider.type) {
                    localUsageTrendScopes[provider.id] = newValue
                } else {
                    localUsageTrendScopes[provider.id] = .allAccounts
                }
            }
        )
    }

    private struct LocalUsageTrendAccountOption: Identifiable {
        var id: String
        var label: String
        var selectorLabel: String
        var codexIdentity: CodexTrendIdentityContext?
        var claudeConfigDir: String?
    }

    private func localUsageTrendSelectedAccountKey(
        providerID: String,
        options: [LocalUsageTrendAccountOption]
    ) -> String {
        guard !options.isEmpty else { return "" }
        if let stored = localUsageTrendSelectedAccountKeys[providerID],
           options.contains(where: { $0.id == stored }) {
            return stored
        }
        return options[0].id
    }

    private func localUsageTrendSelectedAccountKeyBinding(
        providerID: String,
        options: [LocalUsageTrendAccountOption]
    ) -> Binding<String> {
        Binding(
            get: {
                localUsageTrendSelectedAccountKey(
                    providerID: providerID,
                    options: options
                )
            },
            set: { newValue in
                localUsageTrendSelectedAccountKeys[providerID] = newValue
            }
        )
    }

    private func localUsageTrendAccountOptions(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> [LocalUsageTrendAccountOption] {
        switch provider.type {
        case .codex:
            return localUsageTrendCodexAccountOptions(snapshot: snapshot)
        case .claude:
            return localUsageTrendClaudeAccountOptions(snapshot: snapshot)
        default:
            return []
        }
    }

    private func localUsageTrendCodexAccountOptions(snapshot: UsageSnapshot?) -> [LocalUsageTrendAccountOption] {
        var options: [LocalUsageTrendAccountOption] = []
        var seenIdentityKeys: Set<String> = []

        for profile in viewModel.codexProfilesForSettings() {
            let identity = CodexTrendIdentityContext(
                accountID: profile.accountId,
                email: profile.accountEmail,
                identityKey: profile.identityKey
            )
            guard identity.accountID != nil || identity.email != nil || identity.identityKey != nil else {
                continue
            }
            let identityKey = identity.cacheIdentity
            guard !seenIdentityKeys.contains(identityKey) else { continue }
            seenIdentityKeys.insert(identityKey)

            let title = localUsageTrendCodexAccountLabel(profile: profile, identity: identity)
            options.append(
                LocalUsageTrendAccountOption(
                    id: "codex:\(identityKey)",
                    label: title,
                    selectorLabel: localUsageTrendCodexSelectorLabel(profile: profile, identity: identity),
                    codexIdentity: identity,
                    claudeConfigDir: nil
                )
            )
        }

        if let snapshotIdentity = codexLocalTrendIdentityContext(from: snapshot) {
            let snapshotKey = snapshotIdentity.cacheIdentity
            if !seenIdentityKeys.contains(snapshotKey) {
                let label = localUsageTrendCurrentSnapshotLabel(snapshot: snapshot)
                options.insert(
                    LocalUsageTrendAccountOption(
                        id: "codex:current:\(snapshotKey)",
                        label: label,
                        selectorLabel: localUsageTrendCurrentSnapshotSelectorLabel(snapshot: snapshot),
                        codexIdentity: snapshotIdentity,
                        claudeConfigDir: nil
                    ),
                    at: 0
                )
            }
        }

        return options
    }

    private func localUsageTrendClaudeAccountOptions(snapshot: UsageSnapshot?) -> [LocalUsageTrendAccountOption] {
        var options: [LocalUsageTrendAccountOption] = []
        var seenIDs: Set<String> = []

        for profile in viewModel.claudeProfilesForSettings() {
            let configDir = localUsageTrendTrimmed(profile.configDir)
            let key = "claude:\(configDir ?? "default")"
            guard !seenIDs.contains(key) else { continue }
            seenIDs.insert(key)
            options.append(
                LocalUsageTrendAccountOption(
                    id: key,
                    label: localUsageTrendClaudeAccountLabel(profile: profile, configDir: configDir),
                    selectorLabel: localUsageTrendClaudeSelectorLabel(profile: profile, configDir: configDir),
                    codexIdentity: nil,
                    claudeConfigDir: configDir
                )
            )
        }

        let snapshotConfigDir = localUsageTrendTrimmed(snapshot?.rawMeta["claude.configDir"])
        if let snapshotConfigDir {
            let snapshotKey = "claude:\(snapshotConfigDir)"
            if !seenIDs.contains(snapshotKey) {
                options.insert(
                    LocalUsageTrendAccountOption(
                        id: snapshotKey,
                        label: viewModel.localizedText("当前目录", "Current Directory"),
                        selectorLabel: localUsageTrendTrimmed(snapshot?.accountLabel)
                            ?? viewModel.localizedText("当前目录", "Current Directory"),
                        codexIdentity: nil,
                        claudeConfigDir: snapshotConfigDir
                    ),
                    at: 0
                )
            }
        } else if options.isEmpty {
            options.append(
                LocalUsageTrendAccountOption(
                    id: "claude:default",
                    label: viewModel.localizedText(
                        "默认目录 (~/.claude/projects)",
                        "Default Directory (~/.claude/projects)"
                    ),
                    selectorLabel: viewModel.localizedText("默认目录", "Default"),
                    codexIdentity: nil,
                    claudeConfigDir: nil
                )
            )
        }

        return options
    }

    private func localUsageTrendCodexAccountLabel(
        profile: CodexAccountProfile,
        identity: CodexTrendIdentityContext
    ) -> String {
        let displayName = localUsageTrendTrimmed(profile.displayName) ?? "Codex \(profile.slotID.rawValue)"
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return "\(displayName) · \(email)"
        }
        if let accountID = localUsageTrendShortID(identity.accountID) {
            return "\(displayName) · \(accountID)"
        }
        return displayName
    }

    private func localUsageTrendCodexSelectorLabel(
        profile: CodexAccountProfile,
        identity: CodexTrendIdentityContext
    ) -> String {
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return email
        }
        if let accountID = localUsageTrendShortID(identity.accountID) {
            return accountID
        }
        return localUsageTrendTrimmed(profile.displayName) ?? "Codex \(profile.slotID.rawValue)"
    }

    private func localUsageTrendClaudeAccountLabel(profile: ClaudeAccountProfile, configDir: String?) -> String {
        let displayName = localUsageTrendTrimmed(profile.displayName) ?? "Claude \(profile.slotID.rawValue)"
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return "\(displayName) · \(email)"
        }
        if configDir == nil {
            return "\(displayName) · \(viewModel.localizedText("默认目录", "Default"))"
        }
        return displayName
    }

    private func localUsageTrendClaudeSelectorLabel(profile: ClaudeAccountProfile, configDir: String?) -> String {
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return email
        }
        if configDir == nil {
            return viewModel.localizedText("默认目录", "Default")
        }
        return localUsageTrendTrimmed(profile.displayName) ?? "Claude \(profile.slotID.rawValue)"
    }

    private func localUsageTrendCurrentSnapshotLabel(snapshot: UsageSnapshot?) -> String {
        let base = viewModel.localizedText("当前账号", "Current Account")
        if let label = localUsageTrendTrimmed(snapshot?.accountLabel) {
            return "\(base) · \(label)"
        }
        return base
    }

    private func localUsageTrendCurrentSnapshotSelectorLabel(snapshot: UsageSnapshot?) -> String {
        localUsageTrendTrimmed(snapshot?.accountLabel)
            ?? viewModel.localizedText("当前账号", "Current Account")
    }

    private func localUsageTrendShortID(_ value: String?) -> String? {
        guard let value = localUsageTrendTrimmed(value) else { return nil }
        guard value.count > 14 else { return value }
        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private struct LocalUsageTrendIdentityContext {
        var cacheIdentity: String
        var codexIdentity: CodexTrendIdentityContext?
        var claudeCurrentConfigDir: String?
        var claudeAllConfigDirs: [String]
    }

    private func localUsageTrendIdentityContext(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        selectedAccountKey: String,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> LocalUsageTrendIdentityContext {
        switch provider.type {
        case .codex:
            let identity = accountOptions.first(where: { $0.id == selectedAccountKey })?.codexIdentity
                ?? codexLocalTrendIdentityContext(from: snapshot)
            return LocalUsageTrendIdentityContext(
                cacheIdentity: identity?.cacheIdentity ?? "unknown",
                codexIdentity: identity,
                claudeCurrentConfigDir: nil,
                claudeAllConfigDirs: []
            )
        case .claude:
            let selectedConfigDir = accountOptions.first(where: { $0.id == selectedAccountKey })?.claudeConfigDir
            let currentConfigDir = localUsageTrendTrimmed(selectedConfigDir)
                ?? localUsageTrendTrimmed(snapshot?.rawMeta["claude.configDir"])
            let allConfigDirs = Array(
                Set(
                    accountOptions.compactMap { localUsageTrendTrimmed($0.claudeConfigDir) }
                )
            )
            .sorted()
            let currentKey = currentConfigDir ?? "default"
            let allKey = allConfigDirs.joined(separator: ",")
            return LocalUsageTrendIdentityContext(
                cacheIdentity: "current=\(currentKey)|all=\(allKey)",
                codexIdentity: nil,
                claudeCurrentConfigDir: currentConfigDir,
                claudeAllConfigDirs: allConfigDirs
            )
        default:
            return LocalUsageTrendIdentityContext(
                cacheIdentity: "global",
                codexIdentity: nil,
                claudeCurrentConfigDir: nil,
                claudeAllConfigDirs: []
            )
        }
    }

    private func localUsageTrendEffectiveIdentityCacheKey(
        scope: LocalUsageTrendScope,
        identityCacheKey: String
    ) -> String {
        if scope == .allAccounts {
            return "all"
        }
        return identityCacheKey
    }

    private func localUsageTrendQueryKey(
        providerID: String,
        scope: LocalUsageTrendScope,
        identityCacheKey: String
    ) -> String {
        "\(providerID)|\(scope.rawValue)|\(identityCacheKey)"
    }

    private func localUsageTrendDisplaySummary(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        identityCacheKey: String,
        strictSummary: LocalUsageSummary?
    ) -> LocalUsageSummary? {
        _ = provider
        _ = scope
        _ = identityCacheKey
        return strictSummary
    }

    private func localUsageTrendTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func codexLocalTrendIdentityContext(from snapshot: UsageSnapshot?) -> CodexTrendIdentityContext? {
        guard let snapshot else { return nil }
        let accountID = localUsageTrendTrimmed(snapshot.rawMeta["codex.accountId"])
            ?? localUsageTrendTrimmed(snapshot.rawMeta["codex.teamId"])
        let email = localUsageTrendTrimmed(snapshot.accountLabel)
            ?? localUsageTrendTrimmed(snapshot.rawMeta["codex.accountLabel"])
        let identityKey = localUsageTrendTrimmed(snapshot.rawMeta["codex.identityKey"])

        let context = CodexTrendIdentityContext(
            accountID: accountID,
            email: email,
            identityKey: identityKey
        )
        if context.accountID == nil, context.email == nil, context.identityKey == nil {
            return nil
        }
        return context
    }

    private func isClaudeCurrentConfigDirMissing(configDir: String?) -> Bool {
        guard let configDir = localUsageTrendTrimmed(configDir) else {
            return false
        }
        let projectsPath = URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
        return !FileManager.default.fileExists(atPath: projectsPath)
    }

    private func pruneLocalUsageTrendCaches(now: Date = Date()) {
        _ = RuntimeBoundedState.pruneLocalUsageTrendCaches(
            summaries: &localUsageTrendSummaries,
            errors: &localUsageTrendErrors,
            queryLastRefreshedAt: &localUsageTrendQueryLastRefreshedAt,
            loadingQueryKeys: &localUsageTrendLoadingQueryKeys,
            now: now
        )
    }

    private func storeLocalUsageTrendSummary(_ summary: LocalUsageSummary, for queryKey: String, refreshedAt: Date = Date()) {
        localUsageTrendSummaries[queryKey] = RuntimeBoundedState.slimmedLocalUsageSummaryForCache(summary)
        localUsageTrendErrors.removeValue(forKey: queryKey)
        localUsageTrendQueryLastRefreshedAt[queryKey] = refreshedAt
        pruneLocalUsageTrendCaches(now: refreshedAt)
    }

    private func storeLocalUsageTrendError(_ message: String, for queryKey: String, refreshedAt: Date = Date()) {
        localUsageTrendErrors[queryKey] = message
        localUsageTrendQueryLastRefreshedAt[queryKey] = refreshedAt
        pruneLocalUsageTrendCaches(now: refreshedAt)
    }

    private func refreshLocalUsageTrendIfNeeded(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        force: Bool = false
    ) {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let queryKey = localUsageTrendQueryKey(
            providerID: provider.id,
            scope: scope,
            identityCacheKey: identityCacheKey
        )

        guard provider.type != .gemini else { return }
        pruneLocalUsageTrendCaches()
        guard !localUsageTrendLoadingQueryKeys.contains(queryKey) else { return }

        let now = Date()
        if !force,
           let lastRefreshedAt = localUsageTrendQueryLastRefreshedAt[queryKey],
           now.timeIntervalSince(lastRefreshedAt) < localUsageTrendRefreshTTL {
            return
        }

        localUsageTrendLoadingQueryKeys.insert(queryKey)
        localUsageTrendErrors.removeValue(forKey: queryKey)

        Task { @MainActor in
            let providerType = provider.type
            let scopeForRequest = scope
            let codexIdentityForRequest = identityContext.codexIdentity
            let claudeCurrentConfigDirForRequest = identityContext.claudeCurrentConfigDir
            let claudeAllConfigDirsForRequest = identityContext.claudeAllConfigDirs

            let result = await Task.detached(priority: .utility) {
                Result<LocalUsageSummary, Error> {
                    switch providerType {
                    case .codex:
                        let codexScope: CodexTrendScope = scopeForRequest == .currentAccount
                            ? .currentAccount
                            : .allAccounts
                        let codexSummary = try CodexLocalUsageService().fetchSummary(
                            scope: codexScope,
                            currentIdentity: codexIdentityForRequest
                        )
                        return LocalUsageSummary(codex: codexSummary)
                    case .claude:
                        return try ClaudeLocalUsageService().fetchSummary(
                            scope: scopeForRequest,
                            currentConfigDir: claudeCurrentConfigDirForRequest,
                            allConfigDirs: claudeAllConfigDirsForRequest
                        )
                    case .kimi:
                        return try KimiLocalUsageService().fetchSummary(scope: .allAccounts)
                    default:
                        throw LocalUsageTrendError.unsupportedProvider(providerType.rawValue)
                    }
                }
            }.value

            localUsageTrendLoadingQueryKeys.remove(queryKey)
            let refreshedAt = Date()
            switch result {
            case .success(let summary):
                storeLocalUsageTrendSummary(summary, for: queryKey, refreshedAt: refreshedAt)
            case .failure(let error):
                storeLocalUsageTrendError(error.localizedDescription, for: queryKey, refreshedAt: refreshedAt)
            }
        }
    }

    private enum LocalUsageTrendError: LocalizedError {
        case unsupportedProvider(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider(let provider):
                return "Unsupported local trend provider: \(provider)"
            }
        }
    }

    private func isoDateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func detailedValueOrPlaceholder(_ value: String?) -> String {
        guard let value else { return "-" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func maskedDetailedValue(forKey key: String, rawValue: String) -> String {
        let normalized = detailedValueOrPlaceholder(rawValue)
        guard normalized != "-" else { return normalized }
        guard isSensitiveDetailedKey(key) else { return normalized }
        return maskedSensitiveText(normalized)
    }

    private func isSensitiveDetailedKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let fragments = [
            "token",
            "cookie",
            "auth",
            "secret",
            "key",
            "password",
            "session",
            "bearer",
            "jwt",
            "refresh",
            "access"
        ]
        return fragments.contains { lower.contains($0) }
    }

    private func maskedSensitiveText(_ text: String) -> String {
        guard text.count > 6 else {
            return String(repeating: "*", count: max(1, text.count))
        }
        let prefixCount = min(3, text.count)
        let suffixCount = min(3, max(0, text.count - prefixCount))
        let prefix = String(text.prefix(prefixCount))
        let suffix = String(text.suffix(suffixCount))
        let maskCount = max(4, text.count - prefixCount - suffixCount)
        return prefix + String(repeating: "*", count: maskCount) + suffix
    }

    private func officialMonitorSubtitle(snapshot: UsageSnapshot?) -> String? {
        guard viewModel.showOfficialAccountEmailInMenuBar else { return nil }
        guard let label = OfficialValueParser.nonPlaceholderString(snapshot?.accountLabel) else {
            return nil
        }
        return label
    }

    private func officialMonitorPlanType(providerType: ProviderType, snapshot: UsageSnapshot?) -> String? {
        PlanTypeDisplayFormatter.resolvedPlanType(
            providerType: providerType,
            extrasPlanType: snapshot?.extras["planType"],
            rawPlanType: snapshot?.rawMeta["planType"]
        )
    }

    @ViewBuilder
    private func settingsModelTitleWithPlanType(title: String, planType: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)

            if let planType, !planType.isEmpty {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(settingsRowStrokeColor)
                    .frame(width: 1, height: 8)

                Text(planType)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                settingsUsesLightAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.80),
                                Color(red: 1.0, green: 0.74, blue: 0.18, opacity: settingsUsesLightAppearance ? 0.95 : 0.80)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func officialConfigSection(_ provider: ProviderDescriptor) -> some View {
        let supportedSourceModes = provider.supportedOfficialSourceModes
        let supportedWebModes = provider.supportedOfficialWebModes
        let supportsManualInput = provider.supportsOfficialManualCookieInput
        let supportsBearerCredentialInput = supportsOfficialBearerCredentialInput(provider)
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                officialQuotaDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.quotaDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode)
            },
            set: { officialQuotaDisplayModeInputs[provider.id] = $0 }
        )
        let traeValueDisplayBinding: Binding<OfficialTraeValueDisplayMode> = Binding(
            get: {
                officialTraeValueDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.traeValueDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).traeValueDisplayMode
                        ?? .percent)
            },
            set: { officialTraeValueDisplayModeInputs[provider.id] = $0 }
        )
        let sourceBinding: Binding<OfficialSourceMode> = Binding(
            get: {
                let current = officialSourceModeInputs[provider.id] ?? (provider.officialConfig?.sourceMode ?? .auto)
                return supportedSourceModes.contains(current) ? current : (supportedSourceModes.first ?? .auto)
            },
            set: { officialSourceModeInputs[provider.id] = $0 }
        )
        let webBinding: Binding<OfficialWebMode> = Binding(
            get: {
                let current = officialWebModeInputs[provider.id] ?? (provider.officialConfig?.webMode ?? .disabled)
                return supportedWebModes.contains(current) ? current : (supportedWebModes.first ?? .disabled)
            },
            set: { officialWebModeInputs[provider.id] = $0 }
        )

        VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
            if provider.type == .opencodeGo {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    if supportedWebModes.count > 1 {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }

                        officialConfigRow(title: viewModel.text(.webMode)) {
                            officialSegmentControl(
                                selection: webBinding,
                                options: supportedWebModes,
                                label: webModeLabel
                            )
                        }
                    } else {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }
                    }

                    officialConfigHintText(officialSourceHintText(for: provider))
                    officialUsagePreferenceSection(quotaDisplayBinding)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedWorkspaceID = viewModel.hasToken(for: provider)
                            let savedWorkspaceLength = viewModel.savedTokenLength(for: provider)

                            Text("Workspace ID")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 82, alignment: .leading)

                            relayProminentTextField(
                                hasSavedWorkspaceID
                                ? maskedSecretDots(length: savedWorkspaceLength)
                                : viewModel.localizedText("粘贴 wrk_... (必填)", "Paste wrk_... (Required)"),
                                text: Binding(
                                    get: { officialWorkspaceInputs[provider.id, default: ""] },
                                    set: { officialWorkspaceInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialWorkspaceInputs[provider.id, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = viewModel.saveToken(raw, for: provider)
                                }
                                viewModel.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialWorkspaceInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            let hasSavedManualCookie = viewModel.hasOfficialManualCookie(for: provider)
                            let savedManualCookieLength = viewModel.savedOfficialManualCookieLength(for: provider)

                            Text("Cookie")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 82, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedManualCookie
                                ? maskedSecretDots(length: savedManualCookieLength)
                                : viewModel.localizedText("auth=... (可选，自动导入可留空)", "auth=... (Optional when auto import is enabled)"),
                                text: Binding(
                                    get: { officialCookieInputs[provider.id, default: ""] },
                                    set: { officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialCookieInputs[provider.id, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = viewModel.saveOfficialManualCookie(raw, providerID: provider.id)
                                }
                                viewModel.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialCookieInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if provider.type == .trae {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedToken = viewModel.hasToken(for: provider)
                            let savedTokenLength = viewModel.savedTokenLength(for: provider)

                            Text(viewModel.language == .zhHans ? "凭证信息" : "Credential")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 60, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedToken
                                ? maskedSecretDots(length: savedTokenLength)
                                : viewModel.localizedText("粘贴 Cloud-IDE-JWT / JWT", "Paste Cloud-IDE-JWT / JWT"),
                                text: Binding(
                                    get: { officialCookieInputs[provider.id, default: ""] },
                                    set: { officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = viewModel.saveToken(raw, for: provider)
                                }
                                viewModel.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: .auto,
                                    webMode: .disabled,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                                    traeValueDisplayMode: traeValueDisplayBinding.wrappedValue
                                )
                                officialCookieInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        officialConfigHintText(
                            viewModel.localizedText(
                                "获取说明：登录 trae.ai 后打开开发者工具 Network，刷新页面，复制 /trae/api/v1/pay/ide_user_ent_usage 请求头 Authorization（Cloud-IDE-JWT ...）粘贴到上方。",
                                "How to get token: sign in to trae.ai, open DevTools Network, refresh, then copy Authorization from /trae/api/v1/pay/ide_user_ent_usage (Cloud-IDE-JWT ...) and paste above."
                            )
                        )
                    }

                    officialConfigRow(title: viewModel.localizedText("用量显示", "Usage Display")) {
                        officialSegmentControl(
                            selection: traeValueDisplayBinding,
                            options: [.percent, .amount],
                            label: { mode in
                                switch mode {
                                case .percent:
                                    viewModel.localizedText("百分比", "Percent")
                                case .amount:
                                    viewModel.localizedText("数字", "Amount")
                                }
                            }
                        )
                    }

                    officialUsagePreferenceSection(quotaDisplayBinding)
                }
            } else if supportsBearerCredentialInput {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    HStack(spacing: 8) {
                        let hasSavedToken = viewModel.hasToken(for: provider)
                        let savedTokenLength = viewModel.savedTokenLength(for: provider)

                        Text(viewModel.language == .zhHans ? "凭证信息" : "Credential")
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: 60, alignment: .leading)

                        relayProminentSecureField(
                            hasSavedToken
                            ? maskedSecretDots(length: savedTokenLength)
                            : viewModel.localizedText("粘贴 API Key", "Paste API Key"),
                            text: Binding(
                                get: { officialCookieInputs[provider.id, default: ""] },
                                set: { officialCookieInputs[provider.id] = $0 }
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                            let raw = officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !raw.isEmpty {
                                _ = viewModel.saveToken(raw, for: provider)
                            }
                            viewModel.updateOfficialProviderSettings(
                                providerID: provider.id,
                                sourceMode: sourceBinding.wrappedValue,
                                webMode: webBinding.wrappedValue,
                                quotaDisplayMode: quotaDisplayBinding.wrappedValue
                            )
                            officialCookieInputs[provider.id] = ""
                            viewModel.restartPolling()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }
                        officialConfigHintText(officialSourceHintText(for: provider))
                    }

                    officialUsagePreferenceSection(quotaDisplayBinding)
                }
            } else {
                if supportedWebModes.count > 1 {
                    officialConfigRow(title: viewModel.text(.sourceMode)) {
                        officialSegmentControl(
                            selection: sourceBinding,
                            options: supportedSourceModes,
                            label: sourceModeLabel
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.webMode)) {
                            officialSegmentControl(
                                selection: webBinding,
                                options: supportedWebModes,
                                label: webModeLabel
                            )
                        }

                        officialConfigHintText(officialSourceHintText(for: provider))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }

                        officialConfigHintText(officialSourceHintText(for: provider))
                    }
                }

                officialUsagePreferenceSection(quotaDisplayBinding)

                if supportsManualInput {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedManualCookie = viewModel.hasOfficialManualCookie(for: provider)
                            let savedManualCookieLength = viewModel.savedOfficialManualCookieLength(for: provider)

                            Text("Token")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 60, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedManualCookie ? maskedSecretDots(length: savedManualCookieLength) : viewModel.text(.manualCookieHeader),
                                text: Binding(
                                    get: { officialCookieInputs[provider.id, default: ""] },
                                    set: { officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save)) {
                                let raw = officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = viewModel.saveOfficialManualCookie(raw, providerID: provider.id)
                                }
                                viewModel.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialCookieInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onChange(of: sourceBinding.wrappedValue) { _, newValue in
            guard provider.type != .trae, !supportsManualInput else { return }
            viewModel.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: newValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue
            )
        }
        .onChange(of: webBinding.wrappedValue) { _, newValue in
            guard provider.type != .trae, !supportsManualInput else { return }
            viewModel.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: sourceBinding.wrappedValue,
                webMode: newValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue
            )
        }
        .onChange(of: quotaDisplayBinding.wrappedValue) { _, newValue in
            viewModel.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: sourceBinding.wrappedValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: newValue,
                traeValueDisplayMode: provider.type == .trae ? traeValueDisplayBinding.wrappedValue : nil
            )
        }
        .onChange(of: traeValueDisplayBinding.wrappedValue) { _, newValue in
            guard provider.type == .trae else { return }
            viewModel.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: .auto,
                webMode: .disabled,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                traeValueDisplayMode: newValue
            )
        }
    }

    private func officialUsagePreferenceSection(_ quotaDisplayBinding: Binding<OfficialQuotaDisplayMode>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            officialConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
                officialSegmentControl(
                    selection: quotaDisplayBinding,
                    options: [.remaining, .used],
                    label: { mode in
                        switch mode {
                        case .remaining:
                            viewModel.text(.quotaDisplayRemaining)
                        case .used:
                            viewModel.text(.quotaDisplayUsed)
                        }
                    }
                )
            }
            officialConfigHintText(viewModel.text(.claudeQuotaDisplayHint))
        }
    }

    private func officialConfigRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: 60, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
    }

    private func officialConfigHintText(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(settingsHintColor)
            .lineSpacing(settingsHintMultilineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 72)
    }

    private func thirdPartyConfigRow<Content: View>(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: thirdPartyConfigLabelSpacing) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    private func thirdPartyHintText(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(settingsHintColor)
            .lineSpacing(settingsHintMultilineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing)
    }

    private func officialSegmentControl<Option: Identifiable & Equatable>(
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View where Option.ID == String {
        Picker("", selection: Binding(
            get: { selection.wrappedValue.id },
            set: { newValue in
                if let option = options.first(where: { $0.id == newValue }) {
                    selection.wrappedValue = option
                }
            }
        )) {
            ForEach(options, id: \.id) { option in
                Text(label(option)).tag(option.id)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 214, height: 24)
    }

    private var officialShowEmailTitle: String {
        viewModel.language == .zhHans ? "显示邮箱" : "Show Email"
    }

    private var officialShowPlanTypeTitle: String {
        viewModel.language == .zhHans ? "套餐信息" : "Plan Info"
    }

    private var officialStatusBarTitle: String {
        viewModel.language == .zhHans ? "状态栏显示" : "Status Bar"
    }

    private var officialThresholdTitle: String {
        viewModel.language == .zhHans ? "余额阈值" : "Threshold"
    }

    private func maskedSecretDots(length: Int?) -> String {
        let dotCount = max(length ?? 8, 1)
        return String(repeating: "•", count: dotCount)
    }

    private func formattedOfficialThresholdValue(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func setOfficialThresholdValue(_ value: Double, providerID: String) {
        let clamped = min(max(value, 0), 100)
        viewModel.setLowThreshold(clamped, providerID: providerID)
        if focusedThresholdProviderID != providerID {
            officialThresholdInputs[providerID] = formattedOfficialThresholdValue(clamped)
        }
    }

    private func applyOfficialThresholdInput(_ provider: ProviderDescriptor) {
        let key = provider.id
        let rawInput = officialThresholdInputs[key, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            officialThresholdInputs[key] = formattedOfficialThresholdValue(provider.threshold.lowRemaining)
            return
        }

        let normalizedInput = rawInput.replacingOccurrences(of: ",", with: ".")
        guard let parsedValue = Double(normalizedInput) else {
            officialThresholdInputs[key] = formattedOfficialThresholdValue(provider.threshold.lowRemaining)
            return
        }

        let clamped = min(max(parsedValue, 0), 100)
        viewModel.setLowThreshold(clamped, providerID: key)
        officialThresholdInputs[key] = formattedOfficialThresholdValue(clamped)
    }

    private func officialAccountMonitorCard<Content: View>(
        highlightColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .background(
                settingsGlassSurface(cornerRadius: 12, fill: cardBackground)
            )
            .overlay(
                DialogSmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                    .stroke(highlightColor ?? outlineColor, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func codexProfileManagementSection() -> some View {
        // 显式依赖全局刷新时间，确保设置页停留打开时手动刷新也会触发该区域重绘。
        let refreshAnchor = viewModel.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0
        let profiles = viewModel.codexProfilesForSettings()
        let slotsByID = Dictionary(uniqueKeysWithValues: viewModel.codexSlotViewModelsForSettings().map { ($0.slotID, $0) })
        let teamDisplayBySlotID = codexTeamDisplayInfoBySlotID(profiles: profiles)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(profiles, id: \.slotID.rawValue) { profile in
                codexImportedProfileCard(
                    profile: profile,
                    slotViewModel: slotsByID[profile.slotID],
                    teamDisplay: teamDisplayBySlotID[profile.slotID]
                )
            }

            codexImportNextProfileCard(nextSlotID: viewModel.nextCodexProfileSlotID())
        }
        .id(refreshAnchor)
    }

    private func codexImportedProfileCard(
        profile: CodexAccountProfile,
        slotViewModel: CodexSlotViewModel?,
        teamDisplay: CodexTeamDisplayInfo?
    ) -> some View {
        let key = profile.slotID.rawValue
        let snapshot = slotViewModel?.snapshot
        let status = codexSlotStatus(provider: ProviderDescriptor.defaultOfficialCodex(), snapshot: snapshot)
        let metrics = codexQuotaMetrics(provider: ProviderDescriptor.defaultOfficialCodex(), snapshot: snapshot)
        let planType = officialMonitorPlanType(providerType: .codex, snapshot: snapshot)
        let hasError = snapshot?.valueFreshness == .empty
        let updatedAt = snapshot?.updatedAt ?? profile.lastImportedAt
        let trailingInfo = viewModel.language == .zhHans
            ? "更新于 \(settingsElapsedText(from: updatedAt))"
            : "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: updatedAt))"
        let subtitle = profileEmailWithNote(
            email: profile.accountEmail,
            note: profile.note,
            fallback: viewModel.text(.codexProfileEmailUnknown)
        )

        return officialAccountMonitorCard(
            highlightColor: hasError ? Color(hex: 0xD05757) : nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    codexAccountIcon(size: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        settingsModelTitleWithPlanType(
                            title: "Codex \(profile.slotID.rawValue)",
                            planType: planType
                        )
                        Text(subtitle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let teamDisplay {
                            Text(localizedCodexTeamInfoText(teamDisplay))
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
                .frame(height: 24)

                quotaMetricLayout(metrics: metrics, twoByTwo: false)
                    .padding(.top, 8)

                if hasError, let note = snapshot?.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                dividerLine
                    .padding(.top, hasError ? 8 : 10)

                HStack(spacing: 8) {
                    if profile.isCurrentSystemAccount {
                        Text(viewModel.language == .zhHans ? "正在使用" : viewModel.text(.codexCurrentAccount))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0x69BD64))
                    }

                    Text(trailingInfo)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)

                    Spacer(minLength: 8)

                    codexAccountActionButton(codexEditButtonTitle) {
                        openCodexProfileEditor(slotID: profile.slotID, existingProfile: profile)
                    }
                    codexAccountActionButton(codexDeleteButtonTitle, destructive: true) {
                        codexProfilePendingDelete = profile.slotID
                    }
                }
                .padding(.top, 8)

                if let result = codexProfileResult[key], !result.isEmpty {
                    Text(result)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(result.contains(viewModel.text(.codexProfileImportFailed)) ? Color(hex: 0xD05757) : Color(hex: 0x69BD64))
                        .lineLimit(1)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func codexTeamDisplayInfoBySlotID(profiles: [CodexAccountProfile]) -> [CodexSlotID: CodexTeamDisplayInfo] {
        struct TeamRecord {
            var slotID: CodexSlotID
            var email: String
            var teamID: String
        }

        let records: [TeamRecord] = profiles.compactMap { profile in
            guard let email = CodexIdentity.normalizedEmail(profile.accountEmail) else { return nil }
            guard let teamID = CodexIdentity.normalizedAccountID(profile.accountId) else { return nil }
            return TeamRecord(slotID: profile.slotID, email: email, teamID: teamID)
        }

        var teamIDsByEmail: [String: Set<String>] = [:]
        for record in records {
            teamIDsByEmail[record.email, default: []].insert(record.teamID)
        }

        var aliasByEmailAndTeamID: [String: String] = [:]
        for (email, teamIDs) in teamIDsByEmail {
            let sortedTeamIDs = teamIDs.sorted()
            guard sortedTeamIDs.count > 1 else { continue }
            for (index, teamID) in sortedTeamIDs.enumerated() {
                aliasByEmailAndTeamID["\(email)|\(teamID)"] = "Team \(codexTeamAliasToken(index: index))"
            }
        }

        var output: [CodexSlotID: CodexTeamDisplayInfo] = [:]
        for record in records {
            guard let alias = aliasByEmailAndTeamID["\(record.email)|\(record.teamID)"] else {
                continue
            }
            output[record.slotID] = CodexTeamDisplayInfo(alias: alias, teamID: record.teamID)
        }
        return output
    }

    private func localizedCodexTeamInfoText(_ teamDisplay: CodexTeamDisplayInfo) -> String {
        if viewModel.language == .zhHans {
            return "\(teamDisplay.alias) · Team ID: \(teamDisplay.teamID)"
        }
        return "\(teamDisplay.alias) · Team ID: \(teamDisplay.teamID)"
    }

    private func codexTeamAliasToken(index: Int) -> String {
        var value = index
        var token = ""
        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            token = String(Character(scalar)) + token
            value = value / 26 - 1
        } while value >= 0
        return token
    }

    private func codexImportNextProfileCard(nextSlotID: CodexSlotID) -> some View {
        let oauthState = viewModel.oauthImportState(for: .codex)
        let oauthRunning = oauthState?.isRunning ?? false

        return officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    codexAccountIcon(size: 12)
                    Text(viewModel.language == .zhHans ? "导入另一个Codex" : viewModel.text(.codexImportNextProfile))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                dividerLine
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Text(viewModel.text(.codexAuthJSONHowTo))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    codexAccountActionButton(
                        viewModel.localizedText("OAuth 添加", "Add via OAuth"),
                        disabled: oauthRunning
                    ) {
                        viewModel.startOAuthImport(providerType: .codex, slotID: nextSlotID)
                    }
                    codexAccountActionButton(codexAddButtonTitle) {
                        openCodexProfileEditor(slotID: nextSlotID, existingProfile: nil)
                    }
                }
                .padding(.top, 8)

                if let oauthState {
                    Text(oauthImportStateText(oauthState))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(oauthImportStateColor(oauthState))
                        .lineLimit(2)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func claudeProfileManagementSection() -> some View {
        // 显式依赖全局刷新时间，确保设置页停留打开时手动刷新也会触发该区域重绘。
        let refreshAnchor = viewModel.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0
        let profiles = viewModel.claudeProfilesForSettings()
        let slotsByID = Dictionary(uniqueKeysWithValues: viewModel.claudeSlotViewModelsForSettings().map { ($0.slotID, $0) })

        VStack(alignment: .leading, spacing: 8) {
            ForEach(profiles, id: \.slotID.rawValue) { profile in
                claudeImportedProfileCard(
                    profile: profile,
                    slotViewModel: slotsByID[profile.slotID]
                )
            }

            claudeImportNextProfileCard(nextSlotID: viewModel.nextClaudeProfileSlotID())
        }
        .id(refreshAnchor)
    }

    private func claudeImportedProfileCard(
        profile: ClaudeAccountProfile,
        slotViewModel: ClaudeSlotViewModel?
    ) -> some View {
        let key = profile.slotID.rawValue
        let snapshot = slotViewModel?.snapshot
        let status = codexSlotStatus(provider: ProviderDescriptor.defaultOfficialClaude(), snapshot: snapshot)
        let metrics = codexQuotaMetrics(provider: ProviderDescriptor.defaultOfficialClaude(), snapshot: snapshot)
        let planType = officialMonitorPlanType(providerType: .claude, snapshot: snapshot)
        let hasError = snapshot?.valueFreshness == .empty
        let updatedAt = snapshot?.updatedAt ?? profile.lastImportedAt
        let trailingInfo = viewModel.language == .zhHans
            ? "更新于 \(settingsElapsedText(from: updatedAt))"
            : "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: updatedAt))"
        let subtitle = claudeProfileSubtitle(
            profile: profile,
            fallback: viewModel.localizedText("未识别账号", "Account unavailable")
        )

        return officialAccountMonitorCard(
            highlightColor: hasError ? Color(hex: 0xD05757) : nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    claudeAccountIcon(size: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        settingsModelTitleWithPlanType(
                            title: "Claude \(profile.slotID.rawValue)",
                            planType: planType
                        )
                        Text(subtitle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    Text(status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
                .frame(height: 24)

                quotaMetricLayout(metrics: metrics, twoByTwo: true)
                    .padding(.top, 8)

                Text(claudeProfileSourceHint(profile))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 8)

                if hasError, let note = snapshot?.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                dividerLine
                    .padding(.top, hasError ? 8 : 10)

                HStack(spacing: 8) {
                    if profile.isCurrentSystemAccount {
                        Text(viewModel.localizedText("正在使用", "Current"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0x69BD64))
                    }

                    Text(trailingInfo)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)

                    Spacer(minLength: 8)

                    codexAccountActionButton(codexEditButtonTitle) {
                        openClaudeProfileEditor(slotID: profile.slotID, existingProfile: profile)
                    }
                    codexAccountActionButton(codexDeleteButtonTitle, destructive: true) {
                        claudeProfilePendingDelete = profile.slotID
                    }
                }
                .padding(.top, 8)

                if let result = claudeProfileResult[key], !result.isEmpty {
                    Text(result)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle((result.contains("失败") || result.localizedCaseInsensitiveContains("failed")) ? Color(hex: 0xD05757) : Color(hex: 0x69BD64))
                        .lineLimit(1)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func claudeImportNextProfileCard(nextSlotID: CodexSlotID) -> some View {
        let oauthState = viewModel.oauthImportState(for: .claude)
        let oauthRunning = oauthState?.isRunning ?? false

        return officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    claudeAccountIcon(size: 12)
                    Text(viewModel.localizedText("导入另一个 Claude", "Import another Claude account"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                dividerLine
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Text(viewModel.localizedText("支持绑定 CLAUDE_CONFIG_DIR 目录，或手动粘贴完整 .credentials.json。", "Bind a CLAUDE_CONFIG_DIR directory or paste the full .credentials.json."))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    codexAccountActionButton(
                        viewModel.localizedText("OAuth 添加", "Add via OAuth"),
                        disabled: oauthRunning
                    ) {
                        viewModel.startOAuthImport(providerType: .claude, slotID: nextSlotID)
                    }
                    codexAccountActionButton(codexAddButtonTitle) {
                        openClaudeProfileEditor(slotID: nextSlotID, existingProfile: nil)
                    }
                }
                .padding(.top, 8)

                if let oauthState {
                    Text(oauthImportStateText(oauthState))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(oauthImportStateColor(oauthState))
                        .lineLimit(2)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func claudeProfileSourceLabel(_ source: ClaudeProfileSource) -> String {
        switch source {
        case .configDir:
            return viewModel.localizedText("目录绑定", "Config Directory")
        case .manualCredentials:
            return viewModel.localizedText("手动粘贴", "Manual Paste")
        }
    }

    private func claudeProfileSourceHint(_ profile: ClaudeAccountProfile) -> String {
        switch profile.source {
        case .configDir:
            if let configDir = profile.configDir, !configDir.isEmpty {
                return "\(claudeProfileSourceLabel(.configDir)) · \(configDir)"
            }
            return claudeProfileSourceLabel(.configDir)
        case .manualCredentials:
            return claudeProfileSourceLabel(.manualCredentials)
        }
    }

    private func openClaudeProfileEditor(slotID: CodexSlotID, existingProfile: ClaudeAccountProfile?) {
        let key = slotID.rawValue
        claudeProfileEditorSource = existingProfile?.source ?? .configDir
        claudeProfileEditorConfigDir = claudeProfileConfigDirInputs[key] ?? existingProfile?.configDir ?? ""
        claudeProfileEditorJSON = claudeProfileJSONInputs[key] ?? existingProfile?.credentialsJSON ?? ""
        claudeProfileEditorNote = claudeProfileNoteInputs[key] ?? existingProfile?.note ?? ""
        claudeProfileEditor = ClaudeProfileEditorState(
            slotID: slotID,
            title: viewModel.claudeSettingsTitle(for: slotID),
            isNewSlot: existingProfile == nil
        )
    }

    private func saveClaudeProfileEditor() {
        guard let editor = claudeProfileEditor else { return }
        let key = editor.slotID.rawValue
        claudeProfileConfigDirInputs[key] = claudeProfileEditorConfigDir
        claudeProfileJSONInputs[key] = claudeProfileEditorJSON
        claudeProfileNoteInputs[key] = claudeProfileEditorNote
        claudeProfileResult[key] = viewModel.saveClaudeProfile(
            slotID: editor.slotID,
            displayName: "Claude \(editor.slotID.rawValue)",
            note: claudeProfileEditorNote,
            source: claudeProfileEditorSource,
            configDir: claudeProfileEditorConfigDir,
            credentialsJSON: claudeProfileEditorJSON
        )
        claudeProfileEditor = nil
        claudeProfileEditorConfigDir = ""
        claudeProfileEditorJSON = ""
        claudeProfileEditorNote = ""
        claudeProfileEditorSource = .configDir
    }

    private var claudeProfileEditorDialog: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(claudeProfileEditorTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Text(viewModel.localizedText("支持两种导入方式：绑定一个 CLAUDE_CONFIG_DIR 目录，或粘贴完整 .credentials.json。如果手动粘贴缺少 email，建议同时绑定目录读取 claude.json。切换时会同步写回系统默认 Claude 登录。", "You can bind a CLAUDE_CONFIG_DIR directory or paste the full .credentials.json. If manual JSON has no email, also bind the directory so claude.json can be used. Switching also writes to the system Claude credentials."))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    Text(viewModel.localizedText("备注", "Note"))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                        .frame(width: 60, alignment: .leading)

                    TextField(
                        "",
                        text: $claudeProfileEditorNote,
                        prompt: settingsInputPrompt(viewModel.localizedText("例如：工作 / 个人", "e.g. Work / Personal"))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsInputFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )
                }

                officialSegmentControl(
                    selection: $claudeProfileEditorSource,
                    options: ClaudeProfileSource.allCases,
                    label: claudeProfileSourceLabel
                )

                HStack(alignment: .center, spacing: 10) {
                    Text(viewModel.localizedText("目录", "Directory"))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                        .frame(width: 60, alignment: .leading)

                    TextField(
                        "",
                        text: $claudeProfileEditorConfigDir,
                        prompt: settingsInputPrompt("~/.claude-profile")
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsInputFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )
                }

                if claudeProfileEditorSource == .manualCredentials {
                    TextEditor(text: $claudeProfileEditorJSON)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(settingsBodyColor)
                        .frame(height: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(settingsInputFillColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(outlineColor, lineWidth: 1)
                        )
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                settingsCapsuleButton(viewModel.text(.permissionCancel)) {
                    claudeProfileEditor = nil
                    claudeProfileEditorConfigDir = ""
                    claudeProfileEditorJSON = ""
                    claudeProfileEditorNote = ""
                    claudeProfileEditorSource = .configDir
                }
                settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                    saveClaudeProfileEditor()
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            settingsGlassSurface(cornerRadius: 16, fill: panelBackground)
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    private var claudeProfileEditorTitle: String {
        guard let editor = claudeProfileEditor else { return "" }
        if viewModel.language == .zhHans {
            return editor.isNewSlot ? "添加 \(editor.title) 凭证" : "编辑 \(editor.title) 凭证"
        }
        return editor.isNewSlot ? "Add \(editor.title) credentials" : "Edit \(editor.title) credentials"
    }

    private var oauthImportProgressDialog: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(oauthImportDialogTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                if let state = activeOAuthImportDialogState {
                    Text(oauthImportStateText(state))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(oauthImportStateColor(state))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = state.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                settingsCapsuleButton(viewModel.text(.permissionCancel)) {
                    guard let state = activeOAuthImportDialogState else { return }
                    viewModel.cancelOAuthImport(providerType: oauthProviderType(for: state.provider))
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            settingsGlassSurface(cornerRadius: 16, fill: panelBackground)
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    private var oauthImportDialogTitle: String {
        guard let state = activeOAuthImportDialogState else { return "" }
        switch state.provider {
        case .codex:
            return viewModel.localizedText("Codex OAuth 添加中", "Adding Codex via OAuth")
        case .claude:
            return viewModel.localizedText("Claude OAuth 添加中", "Adding Claude via OAuth")
        }
    }

    private func oauthProviderType(for provider: OAuthImportProvider) -> ProviderType {
        switch provider {
        case .codex:
            return .codex
        case .claude:
            return .claude
        }
    }

    private func oauthImportStateText(_ state: OAuthImportState) -> String {
        switch state.phase {
        case .launching:
            return viewModel.localizedText("正在启动官方 CLI 登录流程…", "Launching official CLI login…")
        case .waitingForBrowser:
            return viewModel.localizedText("请在浏览器完成授权，完成后将自动导入本地账号。", "Complete authorization in your browser. The local account will be imported automatically.")
        case .waitingForDevice:
            return viewModel.localizedText("浏览器回调失败，已自动回退到 Device Code 登录。", "Browser callback failed. Automatically switched to Device Code login.")
        case .verifying:
            return viewModel.localizedText("正在读取并校验本地凭据…", "Reading and validating local credentials…")
        case .succeeded:
            return viewModel.localizedText("OAuth 导入成功。", "OAuth import succeeded.")
        case .failed:
            return viewModel.localizedText("OAuth 导入失败。", "OAuth import failed.")
        case .cancelled:
            return viewModel.localizedText("OAuth 导入已取消。", "OAuth import cancelled.")
        }
    }

    private func oauthImportStateColor(_ state: OAuthImportState) -> Color {
        switch state.phase {
        case .failed:
            return Color(hex: 0xD05757)
        case .succeeded:
            return Color(hex: 0x69BD64)
        default:
            return settingsBodyColor
        }
    }

    @ViewBuilder
    private func quotaMetricLayout(
        metrics: [CodexQuotaMetricDisplay],
        twoByTwo: Bool
    ) -> some View {
        if twoByTwo {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(metricsForRow(metrics: metrics, row: row), id: \.id) { metric in
                            codexQuotaMetricView(metric)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 24) {
                ForEach(metrics.prefix(2)) { metric in
                    codexQuotaMetricView(metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func metricsForRow(metrics: [CodexQuotaMetricDisplay], row: Int) -> [CodexQuotaMetricDisplay] {
        let start = row * 2
        guard start < metrics.count else { return [] }
        let end = min(start + 2, metrics.count)
        return Array(metrics[start..<end])
    }

    private func codexQuotaMetricView(_ metric: CodexQuotaMetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(0)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(settingsHintColor)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                    }

                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsMutedHintColor)
                        .monospacedDigit()
                        .lineSpacing(0)
                        .frame(minWidth: 42, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 5) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)
                    .lineSpacing(0)
                    .frame(width: MetricValueLayoutFormatter.metricValueColumnWidth, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsQuotaTrackColor)
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, proxy.size.width * percent / 100))
                        }
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func codexAccountActionButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(destructive ? Color(hex: 0xD05757) : settingsAccentBlue)
        .disabled(disabled)
    }

    private func codexAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_codex_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func claudeAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_claude_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func openCodexProfileEditor(slotID: CodexSlotID, existingProfile: CodexAccountProfile?) {
        let key = slotID.rawValue
        codexProfileEditorJSON = codexProfileJSONInputs[key] ?? existingProfile?.authJSON ?? ""
        codexProfileEditorNote = codexProfileNoteInputs[key] ?? existingProfile?.note ?? ""
        codexProfileEditor = CodexProfileEditorState(
            slotID: slotID,
            title: viewModel.codexSettingsTitle(for: slotID),
            isNewSlot: existingProfile == nil
        )
    }

    private func saveCodexProfileEditor() {
        guard let editor = codexProfileEditor else { return }
        let key = editor.slotID.rawValue
        codexProfileJSONInputs[key] = codexProfileEditorJSON
        codexProfileNoteInputs[key] = codexProfileEditorNote
        codexProfileResult[key] = viewModel.saveCodexProfile(
            slotID: editor.slotID,
            displayName: "Codex \(editor.slotID.rawValue)",
            note: codexProfileEditorNote,
            authJSON: codexProfileEditorJSON
        )
        codexProfileEditor = nil
        codexProfileEditorJSON = ""
        codexProfileEditorNote = ""
    }

    private var codexProfileEditorDialog: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(codexProfileEditorTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Text(viewModel.text(.codexAuthJSONHowTo))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    Text(viewModel.localizedText("备注", "Note"))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                        .frame(width: 60, alignment: .leading)

                    TextField(
                        "",
                        text: $codexProfileEditorNote,
                        prompt: settingsInputPrompt(viewModel.localizedText("例如：工作 / 个人", "e.g. Work / Personal"))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsInputFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )
                }

                TextEditor(text: $codexProfileEditorJSON)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(settingsBodyColor)
                    .frame(height: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settingsInputFillColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                settingsCapsuleButton(viewModel.text(.permissionCancel)) {
                    codexProfileEditor = nil
                    codexProfileEditorJSON = ""
                    codexProfileEditorNote = ""
                }
                settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                    saveCodexProfileEditor()
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            settingsGlassSurface(cornerRadius: 16, fill: panelBackground)
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    private var codexProfileEditorTitle: String {
        guard let editor = codexProfileEditor else { return "" }
        if viewModel.language == .zhHans {
            return editor.isNewSlot ? "添加 \(editor.title) auth.json" : "编辑 \(editor.title) auth.json"
        }
        return editor.isNewSlot ? "Add \(editor.title) auth.json" : "Edit \(editor.title) auth.json"
    }

    private func profileEmailWithNote(email: String?, note: String?, fallback: String) -> String {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = (trimmedEmail?.isEmpty == false ? trimmedEmail! : fallback)
        guard let trimmedNote, !trimmedNote.isEmpty else {
            return resolvedEmail
        }
        return "\(resolvedEmail) · \(trimmedNote)"
    }

    private func claudeProfileSubtitle(profile: ClaudeAccountProfile, fallback: String) -> String {
        if let email = profile.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        if let note = profile.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }
        if let fingerprint = claudeShortFingerprint(profile.credentialFingerprint) {
            return viewModel.localizedText("指纹 \(fingerprint)", "Fingerprint \(fingerprint)")
        }
        return fallback
    }

    private func claudeShortFingerprint(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(8)).lowercased()
    }

    private func codexSlotStatus(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> (text: String, color: Color) {
        guard let snapshot else {
            return (viewModel.language == .zhHans ? "未知" : "Unknown", settingsHintColor)
        }
        if snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return (viewModel.language == .zhHans ? "认证故障" : "Auth Error", Color(hex: 0xD05757))
            case .endpointMisconfigured:
                return (viewModel.language == .zhHans ? "配置异常" : "Config Error", Color(hex: 0xD05757))
            case .rateLimited:
                return (viewModel.language == .zhHans ? "限流" : "Rate Limited", Color(hex: 0xE88B2D))
            case .unreachable:
                return (viewModel.language == .zhHans ? "连接失败" : "Disconnected", Color(hex: 0xD05757))
            case .ok:
                return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
            }
        }

        let availablePercents = codexQuotaMetrics(provider: provider, snapshot: snapshot).compactMap(\.percent)
        guard let minimum = availablePercents.min() else {
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        }
        if minimum > 30 {
            return (viewModel.text(.statusSufficient), Color(hex: 0x69BD64))
        }
        if minimum > 10 {
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        }
        return (viewModel.text(.statusExhausted), Color(hex: 0xD05757))
    }

    private func codexQuotaMetrics(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> [CodexQuotaMetricDisplay] {
        if provider.type == .claude {
            if let snapshot, !snapshot.quotaWindows.isEmpty {
                return claudeCodexQuotaMetrics(provider: provider, snapshot: snapshot)
            }
            return claudeCodexQuotaPlaceholderMetrics(provider: provider)
        }

        let windows: [UsageQuotaWindow]
        if let snapshot, !snapshot.quotaWindows.isEmpty {
            windows = snapshot.quotaWindows
                .sorted { codexQuotaRank($0.kind) < codexQuotaRank($1.kind) }
        } else {
            switch provider.type {
            case .trae:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-dollar",
                        title: traeQuotaMetricTitle(baseTitle: "Dollar"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-autocomplete",
                        title: traeQuotaMetricTitle(baseTitle: "Autocomplete"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .copilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-premium",
                        title: "Premium",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-chat",
                        title: "Chat",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .microsoftCopilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d7",
                        title: "D7",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d30",
                        title: "D30",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .openrouterCredits:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-credits",
                        title: "Credits",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .openrouterAPI:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-limit",
                        title: "Limit",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .ollamaCloud:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-session",
                        title: viewModel.localizedText("会话", "Session"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            default:
                windows = [
                    UsageQuotaWindow(
                        id: "codex-placeholder-session",
                        title: viewModel.text(.quotaFiveHour),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "codex-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            }
        }

        return windows.prefix(2).map { window in
            let remainingPercent = max(0, min(100, window.remainingPercent))
            let displayPercent = provider.displaysUsedQuota
                ? max(0, min(100, window.usedPercent))
                : remainingPercent
            return CodexQuotaMetricDisplay(
                id: window.id,
                title: codexQuotaDisplayTitle(window, provider: provider),
                valueText: codexQuotaValueText(
                    window: window,
                    provider: provider,
                    snapshot: snapshot,
                    displayPercent: displayPercent
                ),
                resetText: codexResetCountdownText(to: window.resetAt),
                percent: displayPercent,
                barColor: codexQuotaBarColor(remainingPercent: remainingPercent)
            )
        }
    }

    private func claudeCodexQuotaPlaceholderMetrics(provider: ProviderDescriptor) -> [CodexQuotaMetricDisplay] {
        [
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-session",
                title: usagePreferredQuotaTitle(
                    viewModel.text(.quotaFiveHour),
                    provider: provider
                ),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0)
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-all",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("全部模型", "All models"),
                    provider: provider
                ),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0)
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-sonnet",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-design",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Claude Design", "Claude Design"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        ]
    }

    private func claudeCodexQuotaMetrics(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot
    ) -> [CodexQuotaMetricDisplay] {
        let windows = snapshot.quotaWindows
        return [
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-session",
                title: viewModel.text(.quotaFiveHour),
                window: windows.first(where: { $0.kind == .session }),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-all",
                title: viewModel.localizedText("全部模型", "All models"),
                window: windows.first(where: { $0.kind == .weekly }),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-sonnet",
                title: viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                window: windows.first(where: isClaudeSonnetWindow(_:)),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-design",
                title: viewModel.localizedText("Claude Design", "Claude Design"),
                window: windows.first(where: isClaudeDesignWindow(_:)),
                snapshot: snapshot
            )
        ]
    }

    private func claudeCodexQuotaMetric(
        provider: ProviderDescriptor,
        id: String,
        title: String,
        window: UsageQuotaWindow?,
        snapshot: UsageSnapshot
    ) -> CodexQuotaMetricDisplay {
        guard let window else {
            return CodexQuotaMetricDisplay(
                id: id,
                title: usagePreferredQuotaTitle(title, provider: provider),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        }

        let remainingPercent = max(0, min(100, window.remainingPercent))
        let displayPercent = provider.displaysUsedQuota
            ? max(0, min(100, window.usedPercent))
            : remainingPercent
        return CodexQuotaMetricDisplay(
            id: id,
            title: usagePreferredQuotaTitle(title, provider: provider),
            valueText: codexQuotaValueText(
                window: window,
                provider: provider,
                snapshot: snapshot,
                displayPercent: displayPercent
            ),
            resetText: codexResetCountdownText(to: window.resetAt),
            percent: displayPercent,
            barColor: codexQuotaBarColor(remainingPercent: remainingPercent),
            isAvailable: true
        )
    }

    private func codexQuotaBarColor(remainingPercent: Double?) -> Color {
        guard let remainingPercent else {
            return .clear
        }
        if remainingPercent > 30 {
            return Color(hex: 0x69BD64)
        }
        if remainingPercent > 10 {
            return Color(hex: 0xE88B2D)
        }
        return Color(hex: 0xD05757)
    }

    private func isClaudeSonnetWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("sonnet")
            || normalizedTitle.contains("sonnet")
    }

    private func isClaudeDesignWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("design")
            || normalizedTitle.contains("design")
    }

    private func codexQuotaDisplayTitle(_ window: UsageQuotaWindow, provider: ProviderDescriptor) -> String {
        let baseTitle: String
        if provider.type == .trae {
            baseTitle = traeQuotaMetricTitle(baseTitle: window.title)
            return usagePreferredQuotaTitle(baseTitle, provider: provider)
        }
        switch window.kind {
        case .session:
            if provider.type == .ollamaCloud {
                baseTitle = viewModel.localizedText("会话", "Session")
            } else {
                baseTitle = viewModel.text(.quotaFiveHour)
            }
        case .weekly, .modelWeekly:
            baseTitle = viewModel.text(.quotaWeekly)
        default:
            baseTitle = window.title
        }
        return usagePreferredQuotaTitle(baseTitle, provider: provider)
    }

    private func usagePreferredQuotaTitle(_ baseTitle: String, provider: ProviderDescriptor) -> String {
        guard provider.displaysUsedQuota else { return baseTitle }
        switch viewModel.language {
        case .zhHans:
            return "\(baseTitle)已用"
        case .en:
            return "\(baseTitle) used"
        }
    }

    private func codexQuotaValueText(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        displayPercent: Double
    ) -> String {
        if provider.type == .trae, provider.traeDisplaysAmount {
            if let amount = traeAmountValue(
                window: window,
                snapshot: snapshot,
                displaysUsedQuota: provider.displaysUsedQuota
            ),
               let kind = TraeMetricKind.detect(id: window.id, title: window.title) {
                return TraeValueDisplayFormatter.format(
                    amount,
                    kind: kind,
                    maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
                )
            }
            return "-"
        }
        return "\(Int(displayPercent.rounded()))%"
    }

    private func traeAmountValue(
        window: UsageQuotaWindow,
        snapshot: UsageSnapshot?,
        displaysUsedQuota: Bool
    ) -> Double? {
        guard let snapshot else { return nil }
        let primaryKey: String?
        let fallbackKey: String?
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if window.id.lowercased().contains("autocomplete") || normalizedTitle.contains("autocomplete") || normalizedTitle.contains("自动补全") {
            primaryKey = displaysUsedQuota ? "autocompleteUsed" : "autocompleteRemaining"
            fallbackKey = displaysUsedQuota ? "autocompleteRemaining" : nil
        } else if window.id.lowercased().contains("dollar") || normalizedTitle.contains("dollar") || normalizedTitle.contains("美元") {
            primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
            fallbackKey = displaysUsedQuota ? "dollarRemaining" : nil
        } else {
            primaryKey = nil
            fallbackKey = nil
        }
        guard let key = primaryKey else { return nil }
        let resolvedRaw = snapshot.extras[key] ?? fallbackKey.flatMap { snapshot.extras[$0] }
        guard let raw = resolvedRaw else { return nil }
        return Double(raw)
    }

    private func traeQuotaMetricTitle(baseTitle: String) -> String {
        let normalized = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("autocomplete") || normalized.contains("自动补全") {
            return viewModel.localizedText("自动补全", "Autocomplete")
        }
        if normalized.contains("dollar") || normalized.contains("美元") {
            return viewModel.localizedText("美元余额", "Dollar Balance")
        }
        return baseTitle
    }

    private func codexQuotaRank(_ kind: UsageQuotaKind) -> Int {
        switch kind {
        case .session: return 0
        case .weekly: return 1
        case .reviews: return 2
        case .modelWeekly: return 3
        case .credits: return 4
        case .extraUsage: return 5
        case .custom: return 6
        }
    }

    private func codexResetCountdownText(to target: Date?) -> String {
        Self.codexCountdownText(to: target, now: settingsNow, language: viewModel.language)
    }

    static func codexCountdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        CountdownFormatter.text(to: target, now: now, placeholder: "--:--:--", language: language)
    }

    private var codexEditButtonTitle: String {
        viewModel.language == .zhHans ? "编辑" : "Edit"
    }

    private var codexDeleteButtonTitle: String {
        viewModel.language == .zhHans ? "删除账号" : "Delete"
    }

    private var codexAddButtonTitle: String {
        viewModel.language == .zhHans ? "添加" : "Add"
    }

    private func sourceModeLabel(_ mode: OfficialSourceMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .api: return "API"
        case .cli: return "CLI"
        case .web: return "Web"
        }
    }

    private func officialSourceHintText(for provider: ProviderDescriptor) -> String {
        if provider.type == .kiro {
            return viewModel.localizedText(
                "默认会自动发现本地 CLI 或 Kiro IDE 登录态；当 CLI 不可用时会回退读取 IDE 缓存。",
                "Local Kiro CLI sessions are auto-discovered by default. When CLI is unavailable, the app falls back to Kiro IDE cache."
            )
        }
        if provider.type == .copilot {
            return viewModel.localizedText(
                "默认按顺序自动读取 COPILOT_GITHUB_TOKEN、GH_TOKEN、GITHUB_TOKEN、Copilot CLI 钥匙串与 GitHub CLI 登录态；当前仅支持 API 检测。",
                "Automatically checks COPILOT_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN, Copilot CLI keychain, and GitHub CLI login in order. API detection only."
            )
        }
        if provider.type == .openrouterCredits {
            return viewModel.localizedText(
                "OpenRouter Credits 需要管理密钥（Management Key），用于读取 /credits 的总额度数据。",
                "OpenRouter Credits requires a Management Key to read total credit usage from /credits."
            )
        }
        if provider.type == .opencodeGo {
            return viewModel.localizedText(
                "Workspace ID 请从 opencode.ai 的 workspace URL 中复制 wrk_...；Cookie 可开启浏览器自动导入 auth，或手动粘贴。若远端接口 hash 变更，可用环境变量 OPENCODE_USAGE_ENDPOINT_ID 覆盖。",
                "Copy Workspace ID (wrk_...) from the opencode.ai workspace URL. Cookie can be auto-imported from browser auth or pasted manually. If endpoint hash changes, override with OPENCODE_USAGE_ENDPOINT_ID."
            )
        }
        if provider.type == .openrouterAPI {
            return viewModel.localizedText(
                "OpenRouter API 使用普通 API Key，读取 /key 的 limit 与 remaining。",
                "OpenRouter API uses a regular API key to read limit and remaining from /key."
            )
        }
        if provider.type == .ollamaCloud {
            return viewModel.localizedText(
                "默认从浏览器自动导入 ollama.com 的 __Secure-session Cookie，也可切到手动模式粘贴。",
                "By default, __Secure-session is auto-imported from ollama.com browser cookies. You can switch to manual mode and paste it."
            )
        }
        return viewModel.text(.officialAutoDiscoveryHint)
    }

    private func supportsOfficialBearerCredentialInput(_ provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        guard provider.auth.kind == .bearer else { return false }
        switch provider.type {
        case .openrouterCredits, .openrouterAPI:
            return true
        default:
            return false
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
        handlePermissionAction(prompt)
    }

    private func handlePermissionAction(_ prompt: PermissionPrompt?) {
        switch prompt {
        case .notifications:
            if !viewModel.hasNotificationPermission {
                viewModel.requestNotificationPermission()
            }
            viewModel.openNotificationSettings()
            permissionResultMessage[PermissionPrompt.notifications.id] = viewModel.hasNotificationPermission
                ? (viewModel.language == .zhHans ? "已打开系统通知设置" : "Opened Notification settings.")
                : viewModel.text(.permissionNotificationsRequested)
            permissionResultIsError[PermissionPrompt.notifications.id] = false
        case .keychain:
            if !viewModel.secureStorageReady {
                let ok = viewModel.prepareSecureStorageAccess()
                permissionResultMessage[PermissionPrompt.keychain.id] = ok
                    ? viewModel.text(.permissionKeychainReady)
                    : viewModel.text(.permissionKeychainFailed)
                permissionResultIsError[PermissionPrompt.keychain.id] = !ok
            } else {
                permissionResultMessage[PermissionPrompt.keychain.id] = viewModel.text(.permissionKeychainReady)
                permissionResultIsError[PermissionPrompt.keychain.id] = false
            }
        case .fullDisk:
            viewModel.openFullDiskAccessSettings()
            permissionResultMessage[PermissionPrompt.fullDisk.id] = viewModel.text(.permissionFullDiskRequested)
            permissionResultIsError[PermissionPrompt.fullDisk.id] = false
        case .autoDiscovery:
            startAutoDiscoveryScan()
        case .resetLocalData:
            viewModel.resetLocalAppData()
            seedInputsFromConfig()
            syncSelection()
            selectedSettingsTab = .overview
            permissionResultMessage[PermissionPrompt.resetLocalData.id] = viewModel.text(.resetLocalDataDone)
            permissionResultIsError[PermissionPrompt.resetLocalData.id] = false
        case .none:
            break
        }
        viewModel.refreshPermissionStatusesNow()
    }

    private func startAutoDiscoveryScan() {
        guard !autoDiscoveryScanning else { return }
        autoDiscoveryScanning = true
        permissionResultMessage[PermissionPrompt.autoDiscovery.id] = nil
        permissionResultIsError[PermissionPrompt.autoDiscovery.id] = false

        Task { @MainActor in
            let result = await viewModel.discoverLocalProviders()
            permissionResultMessage[PermissionPrompt.autoDiscovery.id] = result
            permissionResultIsError[PermissionPrompt.autoDiscovery.id] = false
            autoDiscoveryScanning = false
        }
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
        let showTokenCredential = tokenChannelEnabled
        let showBalanceCredential = accountChannelEnabled
        let defaultUserID = relayViewConfig?.accountBalance?.userID
            ?? selectedTemplate.balanceRequest.userID
            ?? ""
        let showUserIDField = showBalanceCredential && relayTemplateNeedsManualUserID(selectedTemplate)
        let currentBaseURL = baseURLInputs[provider.id] ?? (provider.baseURL ?? "")
        let usesGenericTemplate = (selectedRelayTemplateInputs[provider.id] ?? providerAdapterID) == "generic-newapi"
        let showNameField = true
        let showBaseURLField = usesGenericTemplate || !simpleMode || requiresBaseURLInput(for: selectedTemplate, currentBaseURL: currentBaseURL)
        let tokenSaveButtonTitle = viewModel.language == .zhHans ? "保存" : "Save"
        let quotaCredentialTemplate = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer")
        let balanceAuthHeader = authHeaderInputs[provider.id]
            ?? relayViewConfig?.accountBalance?.authHeader
            ?? selectedTemplate.balanceRequest.authHeader
            ?? "Authorization"
        let balanceAuthScheme = authSchemeInputs[provider.id]
            ?? relayViewConfig?.accountBalance?.authScheme
            ?? selectedTemplate.balanceRequest.authScheme
            ?? "Bearer"
        let balanceCredentialTemplate = relayCredentialTemplate(authHeader: balanceAuthHeader, authScheme: balanceAuthScheme)
        let quotaFieldTitle = relayCredentialFieldName(isAccount: false, templateKind: quotaCredentialTemplate.kind)
        let balanceFieldTitle = relayCredentialFieldName(isAccount: true, templateKind: balanceCredentialTemplate.kind)
        let quotaPlaceholder = quotaCredentialTemplate.placeholder
        let balancePlaceholder: String = {
            if selectedTemplate.id == "generic-newapi", viewModel.language == .zhHans {
                return "粘帖Access Token"
            }
            return balanceCredentialTemplate.placeholder
        }()
        let quotaHintLines = relayCredentialHintLines(
            for: provider,
            template: quotaCredentialTemplate,
            setupHint: relaySetupHint(for: selectedTemplate, field: .quotaAuth)
        )
        let balanceHintLines: [String] = {
            if selectedTemplate.id == "generic-newapi", viewModel.language == .zhHans {
                return ["这里填写Access Token通过个人设置-安全设置-系统访问令牌, 生成令牌"]
            }
            return relayCredentialHintLines(
                for: provider,
                template: balanceCredentialTemplate,
                setupHint: relaySetupHint(for: selectedTemplate, field: .balanceAuth)
            )
        }()
        let credentialModeBinding = Binding<RelayCredentialMode>(
            get: {
                relayCredentialModeInputs[provider.id]
                    ?? provider.relayConfig?.balanceCredentialMode
                    ?? .manualPreferred
            },
            set: { relayCredentialModeInputs[provider.id] = $0 }
        )
        let contentLeading = thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing
        let persistRelaySettings: () -> Void = {
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
                unit: unitInputs[provider.id] ?? (relayViewConfig?.accountBalance?.unit ?? "quota"),
                quotaDisplayMode: thirdPartyQuotaDisplayModeInputs[provider.id]
                    ?? provider.relayConfig?.quotaDisplayMode
                    ?? .remaining
            )
        }

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                if let currentPreset, selectedRelayTemplateInputs[provider.id] == nil, !usesGenericTemplate {
                    thirdPartyConfigRow(title: viewModel.text(.relayTemplate)) {
                        Text(currentPreset.displayName)
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    thirdPartyConfigRow(title: viewModel.text(.relayTemplate)) {
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

                if simpleMode, !showBaseURLField, let suggestedBaseURL = suggestedBaseURL(for: selectedTemplate) {
                    thirdPartyHintText("Base URL: \(suggestedBaseURL)")
                }
            }

            if showBaseURLField {
                thirdPartyConfigRow(title: "Base URL") {
                    HStack(spacing: 8) {
                        relayProminentTextField(viewModel.text(.baseURL), text: Binding(
                            get: { baseURLInputs[provider.id] ?? (provider.baseURL ?? "") },
                            set: { baseURLInputs[provider.id] = $0 }
                        ))
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                            persistRelaySettings()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showNameField {
                thirdPartyConfigRow(title: viewModel.text(.providerName)) {
                    HStack(spacing: 8) {
                        relayProminentTextField(viewModel.text(.providerName), text: Binding(
                            get: { providerNameInputs[provider.id] ?? provider.name },
                            set: { providerNameInputs[provider.id] = $0 }
                        ))
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                            persistRelaySettings()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showUserIDField {
                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: viewModel.text(.userID)) {
                        HStack(spacing: 8) {
                            relayProminentTextField(viewModel.text(.userID), text: Binding(
                                get: { userIDInputs[provider.id] ?? defaultUserID },
                                set: { userIDInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                persistRelaySettings()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let userIDHint = relaySetupHint(for: selectedTemplate, field: .userID) {
                        thirdPartyHintText(userIDHint)
                    }
                }
            }

            if showBalanceCredential {
                let hasSavedBalanceToken = accountAuth.map { viewModel.hasToken(auth: $0) } ?? false
                let savedBalanceTokenLength = accountAuth.flatMap { viewModel.savedTokenLength(auth: $0) }

                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: balanceFieldTitle) {
                        HStack(spacing: 8) {
                            relayProminentSecureField(hasSavedBalanceToken ? maskedSecretDots(length: savedBalanceTokenLength) : balancePlaceholder, text: Binding(
                                get: { systemTokenInputs[provider.id, default: ""] },
                                set: { systemTokenInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                guard let accountAuth else { return }
                                let token = systemTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !token.isEmpty else { return }
                                _ = viewModel.saveToken(token, auth: accountAuth)
                                systemTokenInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(balanceHintLines, id: \.self) { line in
                        thirdPartyHintText(line)
                    }
                }
            }

            if showTokenCredential {
                let hasSavedToken = viewModel.hasToken(for: provider)
                let savedTokenLength = viewModel.savedTokenLength(for: provider)

                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: quotaFieldTitle) {
                        HStack(spacing: 8) {
                            relayProminentSecureField(hasSavedToken ? maskedSecretDots(length: savedTokenLength) : quotaPlaceholder, text: Binding(
                                get: { tokenInputs[provider.id, default: ""] },
                                set: { tokenInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                let token = tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !token.isEmpty else { return }
                                _ = viewModel.saveToken(token, for: provider)
                                tokenInputs[provider.id] = ""
                                viewModel.restartPolling()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(quotaHintLines, id: \.self) { line in
                        thirdPartyHintText(line)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                thirdPartyConfigRow(title: viewModel.text(.credentialMode)) {
                    officialSegmentControl(
                        selection: credentialModeBinding,
                        options: RelayCredentialMode.allCases,
                        label: relayCredentialModeLabel
                    )
                }

                thirdPartyHintText(viewModel.text(.credentialModeHint))
            }

            HStack(spacing: 8) {
                settingsCapsuleButton(viewModel.text(.saveConfig), dismissInputFocus: true) {
                    persistRelaySettings()
                }

                settingsCapsuleButton(viewModel.text(.testConnection)) {
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
                            unit: unitInputs[provider.id] ?? (relayViewConfig?.accountBalance?.unit ?? "quota"),
                            quotaDisplayMode: thirdPartyQuotaDisplayModeInputs[provider.id]
                                ?? provider.relayConfig?.quotaDisplayMode
                                ?? .remaining
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
                    settingsCapsuleButton(viewModel.text(.removeProvider), destructive: true) {
                        viewModel.removeProvider(providerID: provider.id)
                    }
                }
            }
            .padding(.leading, contentLeading)

            if let relayTestResult = relayTestResult[provider.id] {
                relayDiagnosticSection(relayTestResult)
                    .padding(.leading, contentLeading)
            }

            dividerLine
            
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.language == .zhHans ? "连接状态" : "Connection status")
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                relayRuntimeStatusSection(provider, selectedTemplate: selectedTemplate)
            }

            dividerLine

            let advancedExpandedBinding = Binding(
                get: { relayAdvancedExpanded[provider.id] ?? false },
                set: { relayAdvancedExpanded[provider.id] = $0 }
            )

            Button {
                advancedExpandedBinding.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.text(.advancedSettings))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 0)
                    Image(systemName: advancedExpandedBinding.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpandedBinding.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
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

                    let tokenChannelBinding = Binding(
                        get: { tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled },
                        set: { tokenUsageEnabledInputs[provider.id] = $0 }
                    )
                    HStack(spacing: 10) {
                        Text(viewModel.text(.enableTokenChannel))
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)
                        Toggle("", isOn: tokenChannelBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tokenChannelBinding.wrappedValue.toggle()
                    }

                    let accountChannelBinding = Binding(
                        get: { accountEnabledInputs[provider.id] ?? accountChannelEnabled },
                        set: { accountEnabledInputs[provider.id] = $0 }
                    )
                    HStack(spacing: 10) {
                        Text(viewModel.text(.enableAccountChannel))
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)
                        Toggle("", isOn: accountChannelBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        accountChannelBinding.wrappedValue.toggle()
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.authHeader), text: Binding(
                            get: {
                                authHeaderInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.authHeader
                                    ?? selectedTemplate.balanceRequest.authHeader
                                    ?? "Authorization"
                            },
                            set: { authHeaderInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.authScheme), text: Binding(
                            get: {
                                authSchemeInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.authScheme
                                    ?? selectedTemplate.balanceRequest.authScheme
                                    ?? "Bearer"
                            },
                            set: { authSchemeInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.userIDHeader), text: Binding(
                            get: {
                                userHeaderInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.userIDHeader
                                    ?? selectedTemplate.balanceRequest.userIDHeader
                                    ?? "New-Api-User"
                            },
                            set: { userHeaderInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.endpointPath), text: Binding(
                            get: {
                                endpointPathInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.endpointPath
                                    ?? selectedTemplate.balanceRequest.path
                            },
                            set: { endpointPathInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.unit), text: Binding(
                            get: {
                                unitInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.unit
                                    ?? selectedTemplate.extract.unit
                                    ?? "quota"
                            },
                            set: { unitInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.remainingPath), text: Binding(
                            get: {
                                remainingPathInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.remainingJSONPath
                                    ?? selectedTemplate.extract.remaining
                            },
                            set: { remainingPathInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.usedPath), text: Binding(
                            get: {
                                usedPathInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.usedJSONPath
                                    ?? selectedTemplate.extract.used
                                    ?? ""
                            },
                            set: { usedPathInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.limitPath), text: Binding(
                            get: {
                                limitPathInputs[provider.id]
                                    ?? relayViewConfig?.accountBalance?.limitJSONPath
                                    ?? selectedTemplate.extract.limit
                                    ?? ""
                            },
                            set: { limitPathInputs[provider.id] = $0 }
                        ))
                    }

                    relayCompactTextField(viewModel.text(.successPath), text: Binding(
                        get: {
                            successPathInputs[provider.id]
                                ?? relayViewConfig?.accountBalance?.successJSONPath
                                ?? selectedTemplate.extract.success
                                ?? ""
                        },
                        set: { successPathInputs[provider.id] = $0 }
                    ))
                }
                .padding(.top, 8)
                .padding(.leading, contentLeading)
            }
        }
        // detailPane 外层已有 vertical 16；这里留 8 让容器底部总留白约 24。
        .padding(.bottom, 8)
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

    private var unaddedRelayBuiltInPresets: [RelayTemplatePreset] {
        let configuredPresetIDs = Set(
            viewModel.config.providers
                .filter { $0.family == .thirdParty }
                .compactMap { $0.relayConfig?.adapterID }
        )
        return relayBuiltInPresets.filter { !configuredPresetIDs.contains($0.id) }
    }

    private var relayTemplatePresets: [RelayTemplatePreset] {
        RelayAdapterRegistry.shared
            .builtInManifests()
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
            return "GitHub Copilot"
        case .microsoftCopilot:
            return "Microsoft Copilot"
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
            return provider.family == .official ? "Kimi Coding" : "Kimi"
        case .trae:
            return "Trae SOLO"
        case .openrouterCredits:
            return "OpenRouter Credits"
        case .openrouterAPI:
            return "OpenRouter API"
        case .ollamaCloud:
            return "Ollama Cloud"
        case .opencodeGo:
            return "OpenCode Go"
        case .relay, .open, .dragon:
            return provider.name
        }
    }

    private func iconName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "menu_codex_icon"
        case .claude:
            return "menu_claude_icon"
        case .gemini:
            return "menu_gemini_icon"
        case .copilot:
            return "menu_github_copilot_icon"
        case .microsoftCopilot:
            return "menu_microsoft_copilot_icon"
        case .zai:
            return "menu_zai_icon"
        case .amp:
            return "menu_amp_icon"
        case .cursor:
            return "menu_cursor_icon"
        case .jetbrains:
            return "menu_jetbrains_icon"
        case .kiro:
            return "menu_kiro_icon"
        case .windsurf:
            return "menu_windsurf_icon"
        case .kimi:
            return "menu_kimi_icon"
        case .trae:
            return "menu_relay_icon"
        case .openrouterCredits, .openrouterAPI:
            return "menu_openrouter_icon"
        case .ollamaCloud:
            return "menu_ollama_icon"
        case .opencodeGo:
            return "menu_relay_icon"
        case .relay, .open, .dragon:
            if let override = relayModelIconOverrideName(for: provider) {
                return override
            }
            return "menu_relay_icon"
        }
    }

    private func relayModelIconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }
        let relayID = (provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? "").lowercased()
        let relayBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        let host = URL(string: relayBaseURL)?.host?.lowercased() ?? ""
        let providerName = provider.name.lowercased()
        let relaySignals = "\(relayID)|\(host)|\(providerName)"
        if relaySignals.contains("moonshot") || relaySignals.contains("moonsho") || relaySignals.contains("kimi") {
            return "menu_kimi_icon"
        }
        if relaySignals.contains("deepseek") {
            return firstExistingRelayIconName([
                "menu_deepseek_icon",
                "menu_deep_seek_icon"
            ])
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return firstExistingRelayIconName([
                "menu_mimo_icon",
                "menu_xiaomimimo_icon",
                "menu_xiaomi_mimo_icon"
            ])
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return firstExistingRelayIconName([
                "menu_minimax_icon",
                "menu_minimaxi_icon"
            ])
        }
        return nil
    }

    private func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        candidates.first { bundledImage(named: $0) != nil }
    }

    private func fallbackIcon(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "terminal.fill"
        case .kimi:
            return "moon.stars.fill"
        case .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo, .relay, .open, .dragon:
            return "link"
        case .claude, .gemini:
            return "sparkles"
        case .copilot:
            return "chevron.left.forwardslash.chevron.right"
        case .microsoftCopilot:
            return "building.2.crop.circle"
        case .zai:
            return "z.square.fill"
        case .amp:
            return "bolt.fill"
        case .cursor:
            return "cursorarrow.rays"
        case .jetbrains:
            return "brain.head.profile"
        case .kiro:
            return "wand.and.stars.inverse"
        case .windsurf:
            return "wind"
        }
    }

    @ViewBuilder
    private func providerIcon(for provider: ProviderDescriptor, size: CGFloat) -> some View {
        if let image = themedBundledImage(named: iconName(for: provider)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackIcon(for: provider))
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: size, height: size)
        }
    }

    private func themedBundledImage(named name: String) -> NSImage? {
        if settingsUsesLightAppearance,
           let darkImage = bundledImage(named: "\(name)_dark") {
            return darkImage
        }
        return bundledImage(named: name)
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
            if thirdPartyQuotaDisplayModeInputs[provider.id] == nil {
                thirdPartyQuotaDisplayModeInputs[provider.id] = provider.relayConfig?.quotaDisplayMode ?? .remaining
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
            if officialTraeValueDisplayModeInputs[provider.id] == nil {
                officialTraeValueDisplayModeInputs[provider.id] = provider.officialConfig?.traeValueDisplayMode
                    ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).traeValueDisplayMode
                    ?? .percent
            }
            if officialThresholdInputs[provider.id] == nil {
                officialThresholdInputs[provider.id] = formattedOfficialThresholdValue(provider.threshold.lowRemaining)
            }
        }

        for profile in viewModel.codexProfilesForSettings() {
            let key = profile.slotID.rawValue
            if codexProfileJSONInputs[key] == nil {
                codexProfileJSONInputs[key] = profile.authJSON
            }
        }

        for profile in viewModel.claudeProfilesForSettings() {
            let key = profile.slotID.rawValue
            if claudeProfileJSONInputs[key] == nil {
                claudeProfileJSONInputs[key] = profile.credentialsJSON ?? ""
            }
            if claudeProfileConfigDirInputs[key] == nil {
                claudeProfileConfigDirInputs[key] = profile.configDir ?? ""
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
        isAccount _: Bool,
        templateKind: RelayCredentialTemplateKind
    ) -> String {
        let language = viewModel.language
        switch templateKind {
        case .cookie:
            return language == .zhHans ? "凭证信息" : "Credential"
        case .bearer:
            return language == .zhHans ? "凭证信息" : "Credential"
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

    private func relayCredentialHintLines(
        for provider: ProviderDescriptor,
        template: RelayCredentialTemplate,
        setupHint: String?
    ) -> [String] {
        let lookupHint = relayCredentialLookupHint(templateKind: template.kind)
        let rawLines = [template.hint, setupHint, lookupHint].compactMap { $0 }

        var output: [String] = []
        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !shouldStripThirdPartyAccessTokenHint(line, for: provider) else { continue }
            if !output.contains(line) {
                output.append(line)
            }
        }
        return output
    }

    private func shouldStripThirdPartyAccessTokenHint(_ line: String, for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .thirdParty else {
            return false
        }

        let normalized = line.lowercased()
        if line.contains("后台") || line.contains("访问令牌") {
            return true
        }
        if normalized.contains("access token generated") {
            return true
        }
        if normalized.contains("generated by"), normalized.contains("token") {
            return true
        }
        if normalized.contains("dashboard"), normalized.contains("token") {
            return true
        }
        return false
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

    private func formattedSettingsInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    @ViewBuilder
    private func relayDiagnosticSection(_ result: RelayDiagnosticResult) -> some View {
        // “测试连接”结果卡片样式。
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
                .fill(settingsSubtlePanelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func relayRuntimeStatusSection(_ provider: ProviderDescriptor, selectedTemplate: RelayAdapterManifest) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let authSource = viewModel.relayAuthSource(for: provider.id)
        let fetchHealth = viewModel.relayFetchHealth(for: provider.id)
        let freshness = viewModel.relayValueFreshness(for: provider.id)
        let error = viewModel.errors[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHealth = fetchHealth ?? snapshot?.fetchHealth
        let hasError = error?.isEmpty == false
        let summaryStatus = relayProviderSummaryStatus(snapshot: snapshot, hasError: hasError)
        let healthStatus = relayFetchHealthDisplayStatus(
            health: effectiveHealth,
            hasError: hasError
        )

        let balanceValue = snapshot?.remaining ?? snapshot?.limit ?? snapshot?.used
        let balanceText = balanceValue.map(formattedSettingsAmount) ?? "--"
        let updatedText = snapshot.map { "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: $0.updatedAt))" }
            ?? (viewModel.language == .zhHans ? "更新于 --" : "Updated --")
        let freshnessText = freshness.map(relayValueFreshnessLabel) ?? (viewModel.language == .zhHans ? "未知" : "Unknown")
        let sourceValue = authSource?.isEmpty == false ? authSource! : selectedTemplate.displayName
        let sourceLine = viewModel.language == .zhHans
            ? "来源：\(sourceValue)｜\(freshnessText)"
            : "Source: \(sourceValue) | \(freshnessText)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                providerIcon(for: provider, size: 12)
                Text(sidebarDisplayName(for: provider))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(summaryStatus.text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(summaryStatus.color)
                    .lineLimit(1)
            }
            .frame(height: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.text(.balanceLabel))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)

                HStack(spacing: 6) {
                    if let image = bundledImage(named: "menu_balance_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(settingsBodyColor)
                    } else {
                        Image(systemName: "dollarsign.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(settingsBodyColor)
                    }
                    Text(balanceText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                }
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD05757))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dividerLine

            HStack(spacing: 8) {
                Text(healthStatus.text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(healthStatus.color)
                    .lineLimit(1)

                Text(updatedText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(sourceLine)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineLimit(1)
            }
            .frame(height: 10)
        }
        .padding(12)
        .background(
            settingsGlassSurface(cornerRadius: 12, fill: cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func relayProviderSummaryStatus(
        snapshot: UsageSnapshot?,
        hasError: Bool
    ) -> (text: String, color: Color) {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return relayCachedRelayStatus(fetchHealth: snapshot.fetchHealth)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return (viewModel.language == .zhHans ? "认证失效" : "Auth expired", Color(hex: 0xD05757))
            case .endpointMisconfigured:
                return (viewModel.language == .zhHans ? "配置异常" : "Config issue", Color(hex: 0xD05757))
            case .rateLimited:
                return (viewModel.language == .zhHans ? "接口限流" : "Rate limited", Color(hex: 0xE88B2D))
            case .unreachable:
                return (viewModel.text(.statusDisconnected), Color(hex: 0xD05757))
            case .ok:
                break
            }
        }

        if hasError {
            return (viewModel.text(.statusDisconnected), Color(hex: 0xD05757))
        }

        guard let remaining = snapshot?.remaining else {
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        }

        if remaining > 50 {
            return (viewModel.text(.statusSufficient), Color(hex: 0x69BD64))
        }
        if remaining > 0 {
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        }
        return (viewModel.text(.statusExhausted), Color(hex: 0xD05757))
    }

    private func relayCachedRelayStatus(fetchHealth: FetchHealth) -> (text: String, color: Color) {
        switch fetchHealth {
        case .authExpired:
            return (viewModel.language == .zhHans ? "认证失效(缓存)" : "Auth expired (cached)", Color(hex: 0xD05757))
        case .endpointMisconfigured:
            return (viewModel.language == .zhHans ? "配置异常(缓存)" : "Config issue (cached)", Color(hex: 0xD05757))
        case .rateLimited:
            return (viewModel.language == .zhHans ? "限流回退" : "Rate limited (cached)", Color(hex: 0xE88B2D))
        case .unreachable, .ok:
            return (viewModel.language == .zhHans ? "缓存回退" : "Cached fallback", Color(hex: 0xE88B2D))
        }
    }

    private func relayFetchHealthDisplayStatus(
        health: FetchHealth?,
        hasError: Bool
    ) -> (text: String, color: Color) {
        if let health {
            return (relayFetchHealthLabel(health), relayFetchHealthColor(health))
        }
        if hasError {
            return (relayFetchHealthLabel(.unreachable), relayFetchHealthColor(.unreachable))
        }
        return (relayFetchHealthLabel(.ok), relayFetchHealthColor(.ok))
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
        let seconds = max(0, Int(settingsNow.timeIntervalSince(date)))
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

private struct ModernSettingsSidebarTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let selectedFill: Color
    let hoverFill: Color
    let selectedForeground: Color
    let idleForeground: Color
    let mutedForeground: Color
    let selectedStroke: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedForeground : mutedForeground)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? selectedForeground : idleForeground)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? selectedStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered && !isSelected ? 1.01 : 1)
        .animation(
            .spring(
                response: ModernDesignTokens.springResponse,
                dampingFraction: ModernDesignTokens.springDamping
            ),
            value: isHovered
        )
        .animation(
            .spring(
                response: ModernDesignTokens.springResponse,
                dampingFraction: ModernDesignTokens.springDamping
            ),
            value: isSelected
        )
    }

    private var rowFill: Color {
        if isSelected {
            return selectedFill
        }
        return isHovered ? hoverFill : Color.clear
    }
}

#Preview("Settings / General") {
    SettingsView(viewModel: {
        let vm = AppViewModel()
        vm.setLanguage(.zhHans)
        return vm
    }())
    .frame(width: 1416, height: 912)
    .preferredColorScheme(.dark)
}

private struct DialogSmoothRoundedRectangle: InsettableShape {
    // Figma corner smoothing 60%：重置确认弹窗容器使用。
    var cornerRadius: CGFloat
    var smoothing: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat, smoothing: CGFloat) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
        self.insetAmount = 0
    }

    private init(cornerRadius: CGFloat, smoothing: CGFloat, insetAmount: CGFloat) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
        self.insetAmount = insetAmount
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(min(rect.width, rect.height) / 2, cornerRadius))
        guard radius > 0 else { return Path(rect) }

        let s = max(0, min(1, smoothing))
        let circularK: CGFloat = 0.552_284_75
        let squircleK: CGFloat = 0.34
        let k = circularK - (circularK - squircleK) * s
        let cp = radius * k

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + radius),
            control1: CGPoint(x: maxX - cp, y: minY),
            control2: CGPoint(x: maxX, y: minY + cp)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - cp),
            control2: CGPoint(x: maxX - cp, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control1: CGPoint(x: minX + cp, y: maxY),
            control2: CGPoint(x: minX, y: maxY - cp)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addCurve(
            to: CGPoint(x: minX + radius, y: minY),
            control1: CGPoint(x: minX, y: minY + cp),
            control2: CGPoint(x: minX + cp, y: minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        DialogSmoothRoundedRectangle(
            cornerRadius: cornerRadius,
            smoothing: smoothing,
            insetAmount: insetAmount + amount
        )
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
    func relayCompactInput() -> some View {
        self
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    func relayProminentInput() -> some View {
        // Relay 基础输入框样式（与 token 输入框保持一致）。
        self
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}
