import AppKit
import SwiftUI

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
    @State private var officialCookieInputs: [String: String] = [:]
    @State private var codexProfileJSONInputs: [String: String] = [:]
    @State private var codexProfileResult: [String: String] = [:]
    @State private var codexProfilePendingDelete: CodexSlotID?
    @State private var codexProfileEditor: CodexProfileEditorState?
    @State private var codexProfileEditorJSON = ""
    @State private var permissionPrompt: PermissionPrompt?
    @State private var permissionResultMessage: [String: String] = [:]
    @State private var permissionResultIsError: [String: Bool] = [:]
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
    @State private var selectedSettingsTab: SettingsTab = .general
    @State private var selectedGroup: ProviderGroup = .official
    @State private var selectedProviderID: String?
    @State private var settingsNow = Date()

    private let settingsClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - 设置页视觉 Token（改这里可全局影响样式）
    // 整个设置页外层深色圆角容器背景。
    private let panelBackground = Color(hex: 0x232325)
    // 设置页窗口背景渐变起始色（左侧更亮）。
    private let panelGradientStart = Color(hex: 0x2A2B30)
    // 设置页窗口背景渐变结束色（右侧更深）。
    private let panelGradientEnd = Color(hex: 0x1E2025)
    // “通用设置”主内容滚动区域的纯黑底。
    private let cardBackground = Color.black
    // 通用描边色：用于模型面板、卡片边框等 15% 白色描边。
    private let outlineColor = Color.white.opacity(0.15)
    // 内层卡片/黑色内容容器圆角。
    private let cardCornerRadius: CGFloat = 8
    // 分割线颜色（与 15% 白描边风格一致）。
    private let dividerColor = Color.white.opacity(0.15)

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
    private let settingsTitleColor = Color.white.opacity(0.80)
    // 常规正文颜色。
    private let settingsBodyColor = Color.white.opacity(0.80)
    // 次级提示色（55% 白）。
    private let settingsHintColor = Color.white.opacity(0.55)
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
        case general
        case models
        case about

        var id: String { rawValue }
    }

    private struct CodexProfileEditorState: Identifiable {
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
        var percent: Double
        var barColor: Color
    }

    var body: some View {
        // 设置页整体布局：全窗口铺底，让红绿灯直接落在背景上。
        ZStack {
            settingsMainContent
                .blur(radius: showsModalOverlay ? 4 : 0)
                .animation(.easeInOut(duration: 0.16), value: showsModalOverlay)

            if showsResetDataDialog {
                // 重置弹窗遮罩：Figma 参数为白色 15% + Background blur 4。
                Color.white.opacity(0.15)
                    .ignoresSafeArea()

                resetDataConfirmDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsCodexProfileEditorDialog {
                Color.white.opacity(0.15)
                    .ignoresSafeArea()

                codexProfileEditorDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            } else if showsNewAPISiteDialog {
                Color.white.opacity(0.15)
                    .ignoresSafeArea()

                newAPISiteDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
        // 设置内容需要覆盖标题栏区域，避免系统安全区留下顶部分层。
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            seedInputsFromConfig()
            syncSelection()
            viewModel.refreshPermissionStatusesNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissionStatusesNow()
        }
        .onReceive(settingsClock) { value in
            settingsNow = value
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
            LinearGradient(
                colors: [panelGradientStart, panelGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                settingsTabBar

                Group {
                    if selectedSettingsTab == .general {
                        // 通用设置：内容在黑色圆角区域内滚动。
                        ScrollView {
                            topGeneralSection
                                .padding(.top, 16)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 24)
                        }
                        .scrollIndicators(.never)
                        .background(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(cardBackground)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        )
                    } else if selectedSettingsTab == .models {
                        // 模型设置：外层一个黑色容器，内部左右分栏。
                        HStack(spacing: 0) {
                            sidebar
                                .frame(width: 220)
                                .frame(maxHeight: .infinity, alignment: .top)

                            Rectangle()
                                .fill(dividerColor)
                                .frame(width: 1)

                            detailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(cardBackground)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        )
                    } else {
                        // 关于页：单列滚动信息。
                        ScrollView {
                            aboutSection
                        }
                        .scrollIndicators(.never)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            // 预留标题栏高度，避免 tabs 与红绿灯重叠。
            .padding(.top, 44)
        }
    }

    private var showsResetDataDialog: Bool {
        permissionPrompt == .resetLocalData
    }

    private var showsCodexProfileEditorDialog: Bool {
        codexProfileEditor != nil
    }

    private var showsNewAPISiteDialog: Bool {
        isNewAPISiteDialogPresented
    }

    private var showsModalOverlay: Bool {
        showsResetDataDialog || showsCodexProfileEditorDialog || showsNewAPISiteDialog
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
                .foregroundStyle(foreground)
                .lineSpacing(0)
                .frame(width: 110, height: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
    }

    private var settingsTabBar: some View {
        // 顶部三级 tab（通用设置/模型设置/关于）的容器。
        HStack(spacing: 8) {
            settingsTabButton(.general)
            settingsTabButton(.models)
            settingsTabButton(.about)
            Spacer()
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedSettingsTab == tab

        return Button {
            selectedSettingsTab = tab
        } label: {
            Text(settingsTabTitle(tab))
                // tab 文字字号与选中态字重。
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.80))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    // tab 背景：选中是亮底，未选中是 white_15。
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsTabTitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return viewModel.text(.settingsGeneralTab)
        case .models:
            return viewModel.text(.settingsModelsTab)
        case .about:
            return viewModel.text(.settingsAboutTab)
        }
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
        HStack(spacing: 8) {
            modelGroupButton(.official)
            modelGroupButton(.thirdParty)
        }
        .frame(width: 188, height: 20)
    }

    private func modelGroupButton(_ group: ProviderGroup) -> some View {
        let isSelected = selectedGroup == group
        let title = group == .official ? viewModel.text(.officialTab) : viewModel.text(.thirdPartyTab)
        return Button {
            selectedGroup = group
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    private var thirdPartySidebarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(relayBuiltInPresets) { preset in
                        relayPresetSidebarRow(preset)
                    }
                }

                if !customRelayProviders.isEmpty {
                    Spacer()
                        .frame(height: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(customRelayProviders) { provider in
                            sidebarProviderRow(provider)
                        }
                    }
                }

                Spacer()
                    .frame(height: 16)

                dividerLine

                Spacer()
                    .frame(height: 16)

                addNewAPISiteButton
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
    }

    private var officialSidebarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sidebarProviders) { provider in
                    sidebarProviderRow(provider)
                }
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(viewModel.language == .zhHans ? "添加 NewAPI 站点" : "Add NewAPI Site")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarProviderRow(_ provider: ProviderDescriptor) -> some View {
        let isSelected = selectedProviderID == provider.id

        // 左侧“模型列表单行”样式（选中态描边/背景在这里改）。
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { provider.enabled },
                set: { viewModel.setEnabled($0, providerID: provider.id) }
            ))
            .toggleStyle(SettingsModelCheckboxToggleStyle())
            .labelsHidden()

            providerIcon(for: provider, size: 12)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.30) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.30), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProviderID = provider.id
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedProvider {
            // 右侧详情面板：滚动内容区。
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    providerSettingsCard(selectedProvider)
                }
            }
            .scrollIndicators(.never)
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
        // 通用设置主内容：语言、开机启动、权限卡片、扫描、本地重置。
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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(settingsLaunchTitle)
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.launchAtLoginEnabled },
                            set: { viewModel.setLaunchAtLoginEnabled($0) }
                        )
                    )
                    .toggleStyle(FigmaSwitchToggleStyle())
                    .labelsHidden()
                    Spacer(minLength: 0)
                }
                .frame(height: 24)

                Text(settingsLaunchHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .padding(.leading, 60)
                    .lineLimit(1)
            }

            Spacer()
                .frame(height: 24)

            permissionsSection
        }
    }

    private var aboutSection: some View {
        // 关于页主卡内容样式。
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.text(.aboutTitle))
                .font(settingsTitleFont)
                .foregroundStyle(settingsTitleColor)

            aboutRow(label: viewModel.text(.aboutVersion), value: viewModel.currentAppVersion)
            aboutRow(label: viewModel.text(.aboutGitHub), value: AppUpdateService.repositoryURL.absoluteString)

            HStack(spacing: 10) {
                settingsActionButton(viewModel.text(.aboutOpenGitHub)) {
                    viewModel.openRepositoryPage()
                }

                settingsActionButton(viewModel.text(.aboutCheckUpdates)) {
                    viewModel.checkForAppUpdate(force: true)
                }
            }

            if viewModel.updateCheckInFlight {
                Text(viewModel.text(.aboutUpdateChecking))
                    .font(settingsBodyFont)
                    .foregroundStyle(settingsHintColor)
            } else if let error = viewModel.updateCheckErrorMessage,
                      !error.isEmpty {
                Text(viewModel.text(.aboutUpdateFailed))
                    .font(settingsBodyFont)
                    .foregroundStyle(Color(hex: 0xFF5A5A))
            } else if let latest = viewModel.lastCheckedLatestVersion,
                      viewModel.availableUpdate == nil {
                Text(String(format: viewModel.text(.aboutUpdateUpToDate), viewModel.currentAppVersion, latest))
                    .font(settingsBodyFont)
                    .foregroundStyle(Color(hex: 0x51DB42))
            }

            if let update = viewModel.availableUpdate {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.text(.updateAvailableTitle))
                        .font(settingsLabelFont)
                        .foregroundStyle(Color(hex: 0x51DB42))
                    Text(String(format: viewModel.text(.updateAvailableBody), update.latestVersion, viewModel.currentAppVersion))
                        .font(settingsBodyFont)
                        .foregroundStyle(settingsBodyColor)

                    settingsActionButton(viewModel.text(.updateDownloadAction), prominent: true) {
                        viewModel.openLatestReleaseDownload()
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0x51DB42).opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: 0x51DB42).opacity(0.45), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
            Text(value)
                .font(settingsBodyFont)
                .foregroundStyle(settingsHintColor)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var permissionsSection: some View {
        // 权限相关三大块：授权卡片 / 本地扫描 / 重置数据。
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                dividerLine

                HStack(spacing: 16) {
                    permissionStatusTile(
                        title: viewModel.text(.permissionNotificationsTitle),
                        hint: viewModel.text(.permissionNotificationsHint),
                        statusText: notificationPermissionStatusText,
                        statusColor: notificationPermissionStatusColor,
                        buttonTitle: notificationActionTitle,
                        buttonMutedStyle: viewModel.hasNotificationPermission
                    ) {
                        permissionPrompt = .notifications
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
                        permissionPrompt = .keychain
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
                        permissionPrompt = .fullDisk
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

            VStack(alignment: .leading, spacing: 24) {
                dividerLine

                VStack(alignment: .leading, spacing: 12) {
                    permissionActionRow(
                        title: localDiscoveryTitleText,
                        hint: viewModel.text(.localDiscoveryHint),
                        alignCenter: true,
                        buttonTitle: viewModel.text(.localDiscoveryAction)
                    ) {
                        permissionPrompt = .autoDiscovery
                    }

                    Text(localDiscoverySuccessHint)
                        .font(settingsHintFont)
                        .foregroundStyle(Color(hex: 0x69BD64))

                    Text(viewModel.text(.permissionsPrivacyPromise))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xD87E3E))
                        // 橙色声明条：撑满容器宽度。
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: 0xD87E3E), lineWidth: 1)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                dividerLine

                permissionActionRow(
                    title: resetSectionTitle,
                    hint: viewModel.text(.resetLocalDataHint),
                    hintLineSpacing: settingsHintMultilineSpacing,
                    alignCenter: true,
                    buttonTitle: resetActionTitle,
                    destructive: true
                ) {
                    permissionPrompt = .resetLocalData
                }
            }
        }
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
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color.clear)
        )
        .overlay(
            // 权限卡边框颜色：white_30。
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
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
        alignCenter: Bool = false,
        buttonTitle: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // 行级“标题说明 + 右侧按钮”布局（用于扫描、重置区域）。
        let rowAlignment: VerticalAlignment = alignCenter ? .center : .top

        return HStack(alignment: rowAlignment, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
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
            settingsCapsuleButton(buttonTitle, destructive: destructive, action: action)
                // 非居中模式时，按钮略微下移与文字基线对齐。
                .padding(.top, alignCenter ? 0 : 3)
        }
    }

    private var dividerLine: some View {
        // 通用设置里的细分割线样式（与设计稿统一）。
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
    }

    private var languageSegmentControl: some View {
        // 中英文切换分段控件整体外观（背景、尺寸、圆角）。
        HStack(spacing: 0) {
            languageSegmentButton(label: viewModel.text(.chinese), value: .zhHans)
            Rectangle()
                // 中间竖分隔线。
                .fill(Color.white.opacity(0.55))
                .frame(width: 1, height: 14)
            languageSegmentButton(label: viewModel.text(.english), value: .en)
        }
        .frame(width: 140, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func languageSegmentButton(label: String, value: AppLanguage) -> some View {
        let isSelected = viewModel.language == value
        return Button {
            viewModel.setLanguage(value)
        } label: {
            Text(label)
                // 分段项字重、颜色与选中态背景。
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.8) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsCapsuleButton(
        _ title: String,
        destructive: Bool = false,
        textOpacity: Double = 0.80,
        borderOpacity: Double = 0.55,
        action: @escaping () -> Void
    ) -> some View {
        // 设置页统一胶囊按钮（开始扫描/取消授权/重置所有数据等）。
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle((destructive ? Color(hex: 0xD05757) : Color.white).opacity(destructive ? 1 : textOpacity))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke((destructive ? Color(hex: 0xD05757) : Color.white).opacity(destructive ? 1 : borderOpacity), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var resetSectionTitle: String {
        viewModel.language == .zhHans ? "重置本地数据" : viewModel.text(.resetLocalDataTitle)
    }

    private var resetActionTitle: String {
        viewModel.language == .zhHans ? "重置所有数据" : viewModel.text(.resetLocalDataAction)
    }

    private var localDiscoverySuccessHint: String {
        viewModel.language == .zhHans
            ? "扫描到 KIMI / Codex / Gemini ，自动添加到监控"
            : "Detected KIMI / Codex / Gemini and added them to monitoring."
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
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .fill(panelBackground)
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
            .toggleStyle(SettingsModelCheckboxToggleStyle())
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
                .fill(isSelected ? Color.white.opacity(0.30) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.30), lineWidth: 1)
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

        if provider.family == .official {
            officialProviderSettingsCard(provider, snapshot: snapshot, error: error)
        } else {
            thirdPartyProviderSettingsCard(provider, snapshot: snapshot, error: error)
        }
    }

    private func thirdPartyProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(sidebarDisplayName(for: provider))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)

                Toggle("", isOn: Binding(
                    get: { provider.enabled },
                    set: { viewModel.setEnabled($0, providerID: provider.id) }
                ))
                .toggleStyle(FigmaSwitchToggleStyle())
                .labelsHidden()

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .overlay(
                Rectangle()
                    .stroke(outlineColor, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 24) {
                thirdPartyThresholdRow(provider)

                thirdPartyToggleRow(title: officialStatusBarTitle, isOn: Binding(
                    get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                    set: { newValue in
                        if newValue {
                            viewModel.setStatusBarProvider(providerID: provider.id)
                        }
                    }
                ))

                if provider.isRelay {
                    openRelayConfigSection(provider)
                }

                if snapshot != nil || error != nil {
                    dividerLine
                    providerUsageSummarySection(snapshot: snapshot, error: error)
                }
            }
            .padding(.top, 22)
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
            .tint(Color.white.opacity(0.80))

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

    private func thirdPartyToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: thirdPartyConfigLabelSpacing) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(FigmaSwitchToggleStyle())
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private func officialProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(sidebarDisplayName(for: provider))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)

                Toggle("", isOn: Binding(
                    get: { provider.enabled },
                    set: { viewModel.setEnabled($0, providerID: provider.id) }
                ))
                .toggleStyle(FigmaSwitchToggleStyle())
                .labelsHidden()

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .overlay(
                Rectangle()
                    .stroke(outlineColor, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 24) {
                officialThresholdRow(provider)

                officialToggleRow(title: officialStatusBarTitle, isOn: Binding(
                    get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                    set: { newValue in
                        if newValue {
                            viewModel.setStatusBarProvider(providerID: provider.id)
                        }
                    }
                ))

                officialToggleRow(title: officialShowEmailTitle, isOn: Binding(
                    get: { viewModel.showOfficialAccountEmailInMenuBar },
                    set: { viewModel.setShowOfficialAccountEmailInMenuBar($0) }
                ))

                officialConfigSection(provider)
            }
            .padding(.top, 22)

            if provider.type == .codex {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(viewModel.language == .zhHans ? "本机Codex账号" : viewModel.text(.codexProfiles))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                codexProfileManagementSection()
                    .padding(.top, 12)
            } else if snapshot != nil || error != nil {
                providerUsageSummarySection(snapshot: snapshot, error: error)
                    .padding(.top, 16)
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
            .tint(Color.white.opacity(0.80))

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
        HStack(spacing: 0) {
            TextField(
                "",
                text: Binding(
                    get: {
                        officialThresholdInputs[provider.id]
                            ?? formattedOfficialThresholdValue(provider.threshold.lowRemaining)
                    },
                    set: { officialThresholdInputs[provider.id] = $0 }
                ),
                prompt: Text("0.00")
                    .foregroundStyle(settingsHintColor)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(settingsBodyColor)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .focused($focusedThresholdProviderID, equals: provider.id)
            .onSubmit {
                applyOfficialThresholdInput(provider)
            }

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1)

            VStack(spacing: 0) {
                Button {
                    let next = min(100, provider.threshold.lowRemaining + 1)
                    setOfficialThresholdValue(next, providerID: provider.id)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .frame(width: 32, height: 12)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)

                Button {
                    let next = max(0, provider.threshold.lowRemaining - 1)
                    setOfficialThresholdValue(next, providerID: provider.id)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .frame(width: 32, height: 11)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 32)
        }
        .frame(width: 90, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func officialToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .frame(width: 60, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(FigmaSwitchToggleStyle())
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func providerUsageSummarySection(snapshot: UsageSnapshot?, error: String?) -> some View {
        // 详情卡中的“用量摘要”子卡样式。
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
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                officialQuotaDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.quotaDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode)
            },
            set: { officialQuotaDisplayModeInputs[provider.id] = $0 }
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

        VStack(alignment: .leading, spacing: 12) {
            officialConfigRow(title: viewModel.text(.sourceMode)) {
                officialSegmentControl(
                    selection: sourceBinding,
                    options: supportedSourceModes,
                    label: sourceModeLabel
                )
            }

            if supportedWebModes.count > 1 {
                officialConfigRow(title: viewModel.text(.webMode)) {
                    officialSegmentControl(
                        selection: webBinding,
                        options: supportedWebModes,
                        label: webModeLabel
                    )
                }
            }

            Text(viewModel.text(.officialAutoDiscoveryHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
                .lineSpacing(settingsHintMultilineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 72)

            if provider.type == .claude {
                officialConfigRow(title: viewModel.text(.quotaDisplayMode)) {
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

                Text(viewModel.text(.claudeQuotaDisplayHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if provider.supportsOfficialManualCookieInput {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        let hasSavedManualCookie = viewModel.hasOfficialManualCookie(for: provider)

                        Text("Token")
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: 60, alignment: .leading)

                        SecureField("", text: Binding(
                            get: { officialCookieInputs[provider.id, default: ""] },
                            set: { officialCookieInputs[provider.id] = $0 }
                        ), prompt: Text(hasSavedManualCookie ? maskedSecretDots : viewModel.text(.manualCookieHeader))
                            .foregroundStyle(settingsHintColor))
                        .textFieldStyle(.plain)
                        .font(settingsBodyFont)
                        .foregroundStyle(settingsBodyColor)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .stroke(outlineColor, lineWidth: 1)
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
                                quotaDisplayMode: provider.type == .claude ? quotaDisplayBinding.wrappedValue : nil
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

            if !provider.supportsOfficialManualCookieInput {
                HStack {
                    Spacer(minLength: 0)
                    settingsCapsuleButton(viewModel.text(.save)) {
                        viewModel.updateOfficialProviderSettings(
                            providerID: provider.id,
                            sourceMode: sourceBinding.wrappedValue,
                            webMode: webBinding.wrappedValue,
                            quotaDisplayMode: provider.type == .claude ? quotaDisplayBinding.wrappedValue : nil
                        )
                    }
                }
            }
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
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
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
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                officialSegmentButton(
                    title: label(option),
                    isSelected: selection.wrappedValue == option
                ) {
                    selection.wrappedValue = option
                }

                if index < options.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 1, height: 12)
                }
            }
        }
        .padding(1)
        .frame(width: 214, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func officialSegmentButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.80))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.80) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var officialShowEmailTitle: String {
        viewModel.language == .zhHans ? "显示邮箱" : "Show Email"
    }

    private var officialStatusBarTitle: String {
        viewModel.language == .zhHans ? "状态栏显示" : "Status Bar"
    }

    private var officialThresholdTitle: String {
        viewModel.language == .zhHans ? "余额阈值" : "Threshold"
    }

    private var maskedSecretDots: String {
        "••••••••••"
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

    @ViewBuilder
    private func codexProfileManagementSection() -> some View {
        let profiles = viewModel.codexProfilesForSettings()
        let slotsByID = Dictionary(uniqueKeysWithValues: viewModel.codexSlotViewModels().map { ($0.slotID, $0) })

        VStack(alignment: .leading, spacing: 8) {
            ForEach(profiles, id: \.slotID.rawValue) { profile in
                codexImportedProfileCard(
                    profile: profile,
                    slotViewModel: slotsByID[profile.slotID]
                )
            }

            codexImportNextProfileCard(nextSlotID: viewModel.nextCodexProfileSlotID())
        }
    }

    private func codexImportedProfileCard(
        profile: CodexAccountProfile,
        slotViewModel: CodexSlotViewModel?
    ) -> some View {
        let key = profile.slotID.rawValue
        let snapshot = slotViewModel?.snapshot
        let status = codexSlotStatus(snapshot: snapshot)
        let metrics = codexQuotaMetrics(snapshot: snapshot)
        let hasError = snapshot?.valueFreshness == .empty
        let updatedAt = snapshot?.updatedAt ?? profile.lastImportedAt
        let trailingInfo = viewModel.language == .zhHans
            ? "更新于 \(settingsElapsedText(from: updatedAt))"
            : "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: updatedAt))"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                codexAccountIcon(size: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Text(profile.accountEmail ?? viewModel.text(.codexProfileEmailUnknown))
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

            HStack(spacing: 24) {
                ForEach(metrics.prefix(2)) { metric in
                    codexQuotaMetricView(metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hasError ? Color(hex: 0xD05757) : Color.white.opacity(0.30), lineWidth: 1)
        )
    }

    private func codexImportNextProfileCard(nextSlotID: CodexSlotID) -> some View {
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

                codexAccountActionButton(codexAddButtonTitle) {
                    openCodexProfileEditor(slotID: nextSlotID, existingProfile: nil)
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codexQuotaMetricView(_ metric: CodexQuotaMetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(Color.white.opacity(0.40))
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }

                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .monospacedDigit()
                        .frame(minWidth: 42, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }

            HStack(spacing: 8) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)
                    .frame(width: 46, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.30))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(metric.barColor)
                            .frame(width: max(1, proxy.size.width * metric.percent / 100))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func codexAccountActionButton(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle((destructive ? Color(hex: 0xD05757) : Color.white.opacity(0.80)))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(destructive ? Color(hex: 0xD05757) : Color.white.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func codexAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = bundledImage(named: "menu_codex_icon") {
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

    private func openCodexProfileEditor(slotID: CodexSlotID, existingProfile: CodexAccountProfile?) {
        let key = slotID.rawValue
        codexProfileEditorJSON = codexProfileJSONInputs[key] ?? existingProfile?.authJSON ?? ""
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
        codexProfileResult[key] = viewModel.saveCodexProfile(
            slotID: editor.slotID,
            displayName: "Codex \(editor.slotID.rawValue)",
            authJSON: codexProfileEditorJSON
        )
        codexProfileEditor = nil
        codexProfileEditorJSON = ""
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

                TextEditor(text: $codexProfileEditorJSON)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(settingsBodyColor)
                    .frame(height: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
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
                }
                settingsCapsuleButton(viewModel.text(.save)) {
                    saveCodexProfileEditor()
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .fill(panelBackground)
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

    private func codexSlotStatus(snapshot: UsageSnapshot?) -> (text: String, color: Color) {
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

        let minimum = codexQuotaMetrics(snapshot: snapshot).map(\.percent).min() ?? 0
        if minimum > 30 {
            return (viewModel.text(.statusSufficient), Color(hex: 0x69BD64))
        }
        if minimum > 10 {
            return (viewModel.text(.statusTight), Color(hex: 0xE88B2D))
        }
        return (viewModel.text(.statusExhausted), Color(hex: 0xD05757))
    }

    private func codexQuotaMetrics(snapshot: UsageSnapshot?) -> [CodexQuotaMetricDisplay] {
        let windows: [UsageQuotaWindow]
        if let snapshot, !snapshot.quotaWindows.isEmpty {
            windows = snapshot.quotaWindows
                .sorted { codexQuotaRank($0.kind) < codexQuotaRank($1.kind) }
        } else {
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

        return windows.prefix(2).map { window in
            let clamped = max(0, min(100, window.remainingPercent))
            let barColor: Color
            if clamped > 30 {
                barColor = Color(hex: 0x69BD64)
            } else if clamped > 10 {
                barColor = Color(hex: 0xE88B2D)
            } else {
                barColor = Color(hex: 0xD05757)
            }

            return CodexQuotaMetricDisplay(
                id: window.id,
                title: codexQuotaDisplayTitle(window),
                valueText: "\(Int(clamped.rounded()))%",
                resetText: codexResetCountdownText(to: window.resetAt),
                percent: clamped,
                barColor: barColor
            )
        }
    }

    private func codexQuotaDisplayTitle(_ window: UsageQuotaWindow) -> String {
        switch window.kind {
        case .session:
            return viewModel.text(.quotaFiveHour)
        case .weekly, .modelWeekly:
            return viewModel.text(.quotaWeekly)
        default:
            return window.title
        }
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
        guard let target else { return "--:--:--" }
        let interval = max(0, Int(target.timeIntervalSince(settingsNow)))
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
        let usesGenericTemplate = (selectedRelayTemplateInputs[provider.id] ?? providerAdapterID) == "generic-newapi"
        let showNameField = usesGenericTemplate
        let showBaseURLField = usesGenericTemplate || !simpleMode || requiresBaseURLInput(for: selectedTemplate, currentBaseURL: currentBaseURL)
        let credentialModeBinding = Binding<RelayCredentialMode>(
            get: {
                relayCredentialModeInputs[provider.id]
                    ?? provider.relayConfig?.balanceCredentialMode
                    ?? .manualPreferred
            },
            set: { relayCredentialModeInputs[provider.id] = $0 }
        )
        let contentLeading = thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing

        VStack(alignment: .leading, spacing: 10) {
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

            if showNameField {
                thirdPartyConfigRow(title: viewModel.text(.providerName)) {
                    TextField(viewModel.text(.providerName), text: Binding(
                        get: { providerNameInputs[provider.id] ?? provider.name },
                        set: { providerNameInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .relayProminentInput()
                    .frame(maxWidth: 396, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showBaseURLField {
                thirdPartyConfigRow(title: "Base URL") {
                    TextField(viewModel.text(.baseURL), text: Binding(
                        get: { baseURLInputs[provider.id] ?? (provider.baseURL ?? "") },
                        set: { baseURLInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .relayProminentInput()
                    .frame(maxWidth: 396, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if simpleMode {
                if !showBaseURLField, let suggestedBaseURL = suggestedBaseURL(for: selectedTemplate) {
                    thirdPartyHintText("Base URL: \(suggestedBaseURL)")
                }
            }

            if showUserIDField {
                thirdPartyConfigRow(title: viewModel.text(.userID)) {
                    TextField(viewModel.text(.userID), text: Binding(
                        get: { userIDInputs[provider.id] ?? defaultUserID },
                        set: { userIDInputs[provider.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .relayProminentInput()
                    .frame(maxWidth: 396, minHeight: 24, maxHeight: 24, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let userIDHint = relaySetupHint(for: selectedTemplate, field: .userID) {
                    thirdPartyHintText(userIDHint)
                }
            }

            if showBalanceCredential {
                let hasSavedBalanceToken = accountAuth.map { viewModel.hasToken(auth: $0) } ?? false

                thirdPartyConfigRow(title: relayCredentialSectionTitle(isAccount: true, templateKind: balanceTemplate.kind), alignment: .top) {
                    HStack(spacing: 8) {
                        SecureField("", text: Binding(
                            get: { systemTokenInputs[provider.id, default: ""] },
                            set: { systemTokenInputs[provider.id] = $0 }
                        ), prompt: Text(hasSavedBalanceToken ? maskedSecretDots : balanceTemplate.placeholder)
                            .foregroundStyle(settingsHintColor))
                        .textFieldStyle(.plain)
                        .relayProminentInput()
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(relayCredentialSaveLabel(templateKind: balanceTemplate.kind)) {
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

                thirdPartyHintText(balanceTemplate.hint)

                if let balanceSetupHint = relaySetupHint(for: selectedTemplate, field: .balanceAuth) {
                    thirdPartyHintText(balanceSetupHint)
                }

                thirdPartyHintText(relayCredentialLookupHint(templateKind: balanceTemplate.kind))
            }

            if showTokenCredential {
                let hasSavedToken = viewModel.hasToken(for: provider)

                thirdPartyConfigRow(title: relayCredentialSectionTitle(isAccount: false, templateKind: tokenTemplate.kind), alignment: .top) {
                    HStack(spacing: 8) {
                        SecureField("", text: Binding(
                            get: { tokenInputs[provider.id, default: ""] },
                            set: { tokenInputs[provider.id] = $0 }
                        ), prompt: Text(hasSavedToken ? maskedSecretDots : tokenTemplate.placeholder)
                            .foregroundStyle(settingsHintColor))
                        .textFieldStyle(.plain)
                        .relayProminentInput()
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(relayCredentialSaveLabel(templateKind: tokenTemplate.kind)) {
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

                thirdPartyHintText(tokenTemplate.hint)

                if let quotaSetupHint = relaySetupHint(for: selectedTemplate, field: .quotaAuth) {
                    thirdPartyHintText(quotaSetupHint)
                }

                thirdPartyHintText(relayCredentialLookupHint(templateKind: tokenTemplate.kind))
            }

            thirdPartyConfigRow(title: viewModel.text(.credentialMode)) {
                officialSegmentControl(
                    selection: credentialModeBinding,
                    options: RelayCredentialMode.allCases,
                    label: relayCredentialModeLabel
                )
            }

            thirdPartyHintText(viewModel.text(.credentialModeHint))

            HStack(spacing: 8) {
                settingsCapsuleButton(viewModel.text(.saveConfig)) {
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

            Text(viewModel.language == .zhHans ? "连接状态" : "Connection status")
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)

            relayRuntimeStatusSection(provider, selectedTemplate: selectedTemplate)

            dividerLine

            DisclosureGroup(
                isExpanded: Binding(
                    get: { relayAdvancedExpanded[provider.id] ?? false },
                    set: { relayAdvancedExpanded[provider.id] = $0 }
                ),
                content: {
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
                                .toggleStyle(FigmaSwitchToggleStyle())
                                .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        .frame(height: 24)

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
                                .toggleStyle(FigmaSwitchToggleStyle())
                                .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        .frame(height: 24)

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
                            .textFieldStyle(.plain)
                            .relayCompactInput()

                            TextField(viewModel.text(.authScheme), text: Binding(
                                get: {
                                    authSchemeInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.authScheme
                                        ?? selectedTemplate.balanceRequest.authScheme
                                        ?? "Bearer"
                                },
                                set: { authSchemeInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .relayCompactInput()
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
                            .textFieldStyle(.plain)
                            .relayCompactInput()

                            TextField(viewModel.text(.endpointPath), text: Binding(
                                get: {
                                    endpointPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.endpointPath
                                        ?? selectedTemplate.balanceRequest.path
                                },
                                set: { endpointPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .relayCompactInput()
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
                            .textFieldStyle(.plain)
                            .relayCompactInput()

                            TextField(viewModel.text(.remainingPath), text: Binding(
                                get: {
                                    remainingPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.remainingJSONPath
                                        ?? selectedTemplate.extract.remaining
                                },
                                set: { remainingPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .relayCompactInput()
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
                            .textFieldStyle(.plain)
                            .relayCompactInput()

                            TextField(viewModel.text(.limitPath), text: Binding(
                                get: {
                                    limitPathInputs[provider.id]
                                        ?? relayViewConfig?.accountBalance?.limitJSONPath
                                        ?? selectedTemplate.extract.limit
                                        ?? ""
                                },
                                set: { limitPathInputs[provider.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .relayCompactInput()
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
                        .textFieldStyle(.plain)
                        .relayCompactInput()
                    }
                    .padding(.top, 8)
                    .padding(.leading, contentLeading)
                },
                label: {
                    Text(viewModel.text(.advancedSettings))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
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
            return "menu_codex_icon"
        case .claude:
            return "menu_claude_icon"
        case .gemini:
            return "menu_gemini_icon"
        case .copilot:
            return "menu_copilot_icon"
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
        case .relay, .open, .dragon:
            return "menu_relay_icon"
        }
    }

    private func fallbackIcon(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "terminal.fill"
        case .kimi:
            return "moon.stars.fill"
        case .relay, .open, .dragon:
            return "link"
        case .claude, .gemini:
            return "sparkles"
        case .copilot:
            return "chevron.left.forwardslash.chevron.right"
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
                .fill(Color.white.opacity(0.05))
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
                    .foregroundStyle(Color.white)
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
                    .foregroundStyle(Color.white)

                HStack(spacing: 6) {
                    Text("💰")
                        .font(.system(size: 14, weight: .regular))
                    Text(balanceText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
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

#Preview("Settings / General") {
    SettingsView(viewModel: {
        let vm = AppViewModel()
        vm.setLanguage(.zhHans)
        return vm
    }())
    .frame(width: 800, height: 671)
    .preferredColorScheme(.dark)
}

private struct FigmaSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    // 开关轨道：选中/未选中透明度在这里改。
                    .fill(Color.white.opacity(configuration.isOn ? 0.80 : 0.15))
                    .frame(width: 54, height: 24)

                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    // 开关滑块：尺寸、颜色、阴影在这里改。
                    .fill(Color.white)
                    .frame(width: 32, height: 20)
                    .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 0)
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsModelCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(configuration.isOn ? Color.white.opacity(0.80) : Color.white.opacity(0.25))
                    .frame(width: 12, height: 12)

                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
            }
        }
        .buttonStyle(.plain)
    }
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
            .foregroundStyle(Color.white.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    func relayProminentInput() -> some View {
        // Relay 基础输入框样式（与 token 输入框保持一致）。
        self
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}
