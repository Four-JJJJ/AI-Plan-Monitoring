import AppKit
import SwiftUI
import OhMyUsageApplication

private struct MenuCardsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    var onOpenSettings: (() -> Void)?
    @State private var now = Date()
    @State private var onboardingDiscoveryMessage: String?
    @State private var onboardingDiscoveryIsError = false
    @State private var onboardingDiscoveryInFlight = false
    @State private var cardsContentHeight: CGFloat = 0
    @State private var clockTask: Task<Void, Never>?

    // MARK: - Menubar 视觉 Token（改这里可全局影响首页样式）
    // menubar 面板外层背景。
    private let panelBackground = Color(hex: 0x232323)
    // menubar 内部卡片背景。
    private let cardBackground = Color.black
    // 卡片垂直间距。
    private let cardSpacing: CGFloat = 4
    // 状态颜色：健康/警告/错误。
    private let sufficientColor = Color(hex: 0x69BD64)
    private let warningColor = Color(hex: 0xD87E3E)
    private let errorColor = Color(hex: 0xD05757)
    // 顶部操作按钮尺寸与间距（Figma: 16x16，间距 12）。
    private let headerActionIconSize: CGFloat = 16
    private let headerActionSpacing: CGFloat = 12
    private let headerHeight: CGFloat = 16
    private let headerActionIconOpacity: Double = 0.4
    private let updateHintColor = Color(hex: 0x69BD65)
    private let updateErrorColor = Color(hex: 0xD05757)
    // menubar 面板最高 800px，超出后只滚动卡片区。
    private let panelMaxHeight: CGFloat = 800
    private let panelTopPadding: CGFloat = 12
    private let panelBottomPadding: CGFloat = 8
    private let panelHorizontalPadding: CGFloat = 8
    private let panelContentSpacing: CGFloat = 8
    private let cardsViewportCornerRadius: CGFloat = 12

    var body: some View {
        // menubar 主面板布局：顶部 header + 下方卡片列表。
        VStack(alignment: .leading, spacing: panelContentSpacing) {
            header
            cards
        }
        .frame(width: 324)
        .padding(.top, panelTopPadding)
        .padding(.bottom, panelBottomPadding)
        .padding(.horizontal, panelHorizontalPadding)
        .background(
            SmoothRoundedRectangle(cornerRadius: 20, smoothing: 0.6)
                // menubar 外层圆角背景。
                .fill(panelBackground)
        )
        .clipShape(
            SmoothRoundedRectangle(cornerRadius: 20, smoothing: 0.6)
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            restartClockIfNeeded()
        }
        .onDisappear {
            stopClock()
        }
        .onChange(of: viewModel.menuPanelVisible) { _, _ in
            restartClockIfNeeded()
        }
    }

    private var header: some View {
        let presentation = headerPresentation

        // 顶部工具条：更新时间 + 新版本入口 + 刷新/设置/退出三个图标按钮。
        return HStack(spacing: 12) {
            Text(presentation.updatedText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.30))
                .lineSpacing(0)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let update = presentation.update {
                headerUpdateButton(update)
            }

            HStack(spacing: headerActionSpacing) {
                headerIconButton(iconName: "refresh_icon", fallback: "arrow.clockwise") {
                    viewModel.refreshNow()
                }
                headerIconButton(iconName: "settings_icon", fallback: "gearshape") {
                    if let onOpenSettings {
                        onOpenSettings()
                    } else {
                        SettingsWindowController.shared.show(viewModel: viewModel)
                    }
                }
                headerIconButton(iconName: "quit_icon", fallback: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(height: headerHeight)
        // 外层已有 horizontal 8，这里补 12 => 距离外边框 20px。
        .padding(.horizontal, 12)
    }

    private var cards: some View {
        // 卡片流容器：内容不足按实际高度；超过上限时在区内滚动。
        ScrollView {
            VStack(spacing: cardSpacing) {
                if viewModel.shouldShowPermissionGuide {
                    permissionGuideCard
                }

                ForEach(displayProviders) { provider in
                    providerCards(for: provider)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuCardsContentHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollIndicators(.never)
        .frame(height: cardsViewportHeight)
        .clipShape(
            SmoothRoundedRectangle(cornerRadius: cardsViewportCornerRadius, smoothing: 0.6)
        )
        .onPreferenceChange(MenuCardsContentHeightPreferenceKey.self) { height in
            if abs(cardsContentHeight - height) > 0.5 {
                cardsContentHeight = height
            }
        }
    }

    private var cardsViewportHeight: CGFloat {
        let maxHeight = max(
            0,
            panelMaxHeight - panelTopPadding - panelBottomPadding - headerHeight - panelContentSpacing
        )
        let measured = cardsContentHeight > 0 ? cardsContentHeight : maxHeight
        return min(maxHeight, measured)
    }

    private var headerPresentation: MenuDashboardHeaderPresentation {
        MenuDashboardPresenter.headerPresentation(
            lastUpdatedAt: viewModel.lastUpdatedAt,
            language: viewModel.language,
            now: now,
            updatedAgoLabel: viewModel.text(.updatedAgo),
            updateState: viewModel.menuUpdateDisplayState
        )
    }

    private func headerIconButton(iconName: String, fallback: String, action: @escaping () -> Void) -> some View {
        // 顶部图标按钮样式入口（尺寸、图标颜色、点击样式）。
        Button(action: action) {
            BundledIconView(
                name: iconName,
                fallback: fallback,
                size: headerActionIconSize,
                iconOpacity: headerActionIconOpacity
            )
        }
        .buttonStyle(.plain)
        .frame(width: headerActionIconSize, height: headerActionIconSize)
    }

    private func headerUpdateTint(for tone: MenuDashboardHeaderUpdatePresentation.Tone) -> Color {
        switch tone {
        case .neutral, .positive:
            return updateHintColor
        case .negative:
            return updateErrorColor
        }
    }

    private func headerUpdateButton(_ update: MenuDashboardHeaderUpdatePresentation) -> some View {
        let tint = headerUpdateTint(for: update.tone)

        return HStack(spacing: 4) {
            BundledIconView(
                name: "settings_download_icon",
                fallback: "arrow.down",
                size: headerActionIconSize,
                tint: tint
            )
            if update.showsPrimaryAction {
                Button {
                    viewModel.performMenuUpdateAction()
                } label: {
                    Text(update.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tint)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(!update.isRetryEnabled)
            } else {
                Text(update.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tint)
                    .lineSpacing(0)
                    .lineLimit(1)
            }

            if let retryTitle = update.retryTitle {
                Button {
                    viewModel.performMenuUpdateAction()
                } label: {
                    Text(retryTitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(updateErrorColor)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(!update.isRetryEnabled)
            }
        }
        .accessibilityLabel(update.accessibilityLabel)
    }

    private var permissionGuideCard: some View {
        // 首次引导权限卡样式。
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.permissionsTitle))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text(viewModel.text(.permissionsPrivacyPromise))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            permissionGuideRow(
                title: viewModel.text(.permissionNotificationsTitle),
                hint: viewModel.text(.permissionNotificationsHint),
                statusText: viewModel.hasNotificationPermission ? grantedStatusText : pendingStatusText,
                statusColor: viewModel.hasNotificationPermission ? Color(hex: 0x51DB42) : Color(hex: 0xD87E3E),
                actionTitle: viewModel.hasNotificationPermission ? nil : viewModel.text(.permissionNotificationsAction),
                action: viewModel.hasNotificationPermission ? nil : { viewModel.requestNotificationPermission() }
            )

            permissionGuideRow(
                title: viewModel.text(.permissionKeychainTitle),
                hint: viewModel.text(.permissionKeychainHint),
                statusText: viewModel.secureStorageReady ? grantedStatusText : pendingStatusText,
                statusColor: viewModel.secureStorageReady ? Color(hex: 0x51DB42) : Color(hex: 0xD87E3E),
                actionTitle: viewModel.secureStorageReady ? nil : viewModel.text(.permissionKeychainAction),
                action: viewModel.secureStorageReady ? nil : { _ = viewModel.prepareSecureStorageAccess() }
            )

            if viewModel.fullDiskAccessRelevant || viewModel.fullDiskAccessRequested {
                permissionGuideRow(
                    title: viewModel.text(.permissionFullDiskTitle),
                    hint: viewModel.text(.permissionFullDiskHint),
                    statusText: viewModel.fullDiskAccessGranted
                        ? grantedStatusText
                        : (viewModel.fullDiskAccessRequested ? waitingStatusText : pendingStatusText),
                    statusColor: viewModel.fullDiskAccessGranted
                        ? Color(hex: 0x51DB42)
                        : Color(hex: 0xD87E3E),
                    actionTitle: viewModel.fullDiskAccessGranted ? nil : viewModel.text(.permissionFullDiskAction),
                    action: viewModel.fullDiskAccessGranted ? nil : { viewModel.openFullDiskAccessSettings() }
                )
            }

            if viewModel.canRunLocalDiscoveryFromOnboarding {
                permissionGuideRow(
                    title: viewModel.text(.localDiscoveryTitle),
                    hint: viewModel.text(.localDiscoveryHint),
                    statusText: onboardingDiscoveryInFlight
                        ? waitingStatusText
                        : (onboardingDiscoveryMessage == nil ? readyStatusText : completedStatusText),
                    statusColor: onboardingDiscoveryInFlight
                        ? Color(hex: 0xD87E3E)
                        : Color(hex: 0x51DB42),
                    actionTitle: onboardingDiscoveryInFlight ? nil : viewModel.text(.localDiscoveryAction),
                    action: onboardingDiscoveryInFlight ? nil : {
                        onboardingDiscoveryMessage = viewModel.text(.localDiscoveryScanning)
                        onboardingDiscoveryIsError = false
                        onboardingDiscoveryInFlight = true
                        Task {
                            let result = await viewModel.discoverLocalProviders()
                            await MainActor.run {
                                onboardingDiscoveryMessage = result
                                onboardingDiscoveryIsError = result == viewModel.text(.localDiscoveryNothingFound)
                                onboardingDiscoveryInFlight = false
                            }
                        }
                    }
                )
            }

            if let onboardingDiscoveryMessage, !onboardingDiscoveryMessage.isEmpty {
                Text(onboardingDiscoveryMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(onboardingDiscoveryIsError ? Color(hex: 0xD83E3E) : Color(hex: 0x51DB42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
    }

    private func permissionGuideRow(
        title: String,
        hint: String,
        statusText: String,
        statusColor: Color,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        // 权限引导卡中的单行项样式（标题、状态胶囊、右侧按钮）。
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusColor.opacity(0.95))
                        )
                }
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Color(hex: 0x2F7CF6))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var grantedStatusText: String {
        viewModel.language == .zhHans ? "已授权" : "Allowed"
    }

    private var pendingStatusText: String {
        viewModel.language == .zhHans ? "待授权" : "Pending"
    }

    private var waitingStatusText: String {
        viewModel.language == .zhHans ? "待确认" : "Waiting"
    }

    private var readyStatusText: String {
        viewModel.language == .zhHans ? "可开始" : "Ready"
    }

    private var completedStatusText: String {
        viewModel.language == .zhHans ? "已完成" : "Done"
    }

    @ViewBuilder
    private func providerCard(_ provider: ProviderDescriptor, codexTeamAliases: [String: String] = [:]) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        // menubar 模型卡入口：官方模型和 quotaPercent relay 走百分比卡，其余第三方走余额卡。
        if ProviderCapabilities.capabilities(for: provider).usesPercentageMenuCard {
            let metrics = MenuQuotaPresenter.quotaMetrics(
                provider: provider,
                snapshot: snapshot,
                language: viewModel.language,
                localization: menuQuotaLocalization
            )
            let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
                provider: provider,
                metrics: metrics,
                language: viewModel.language,
                localization: menuQuotaLocalization
            )
            let visual = percentageVisualPresentation(
                snapshot: snapshot,
                errorText: error,
                healthPercents: visibleMetrics.map(\.healthPercent)
            )
            let metricDisplays = quotaMetricDisplays(
                from: visibleMetrics,
                blockageCandidates: metrics,
                provider: provider,
                snapshot: snapshot,
                disconnected: visual.isDisconnected
            )

            PercentageModelCard(
                title: displayName(for: provider),
                planType: MenuCardStatusPresenter.planType(for: provider, snapshot: snapshot),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                subtitle: provider.family == .official
                    ? MenuSubtitlePresenter.officialAccountSubtitle(
                        providerType: provider.type,
                        snapshot: snapshot,
                        showAccountEmail: viewModel.showOfficialAccountEmailInMenuBar,
                        codexTeamAliases: codexTeamAliases
                    )
                    : MenuSubtitlePresenter.relayQuotaSubtitle(
                        snapshot: snapshot,
                        language: viewModel.language
                    ),
                status: cardStatus(visual.status),
                metrics: percentageMetricViews(from: metricDisplays),
                errorText: visual.errorText,
                backgroundColor: cardBackground,
                isDisconnected: visual.isDisconnected,
                highlightColor: visual.showsErrorHighlight ? errorColor : nil
            )
        } else {
            let amountPresentation = MenuCardStatePresenter.amountPresentation(
                provider: provider,
                snapshot: snapshot,
                errorText: error,
                language: viewModel.language,
                secondaryText: MenuSubtitlePresenter.relaySecondaryText(
                    provider: provider,
                    snapshot: snapshot,
                    language: viewModel.language
                ),
                usedLabel: viewModel.text(.used),
                balanceLabel: viewModel.text(.balanceLabel),
                tightText: viewModel.text(.statusTight),
                sufficientText: viewModel.text(.statusSufficient),
                exhaustedText: viewModel.text(.statusExhausted),
                disconnectedText: disconnectedStatusText
            )
            AmountModelCard(
                title: displayName(for: provider),
                planType: MenuCardStatusPresenter.planType(for: provider, snapshot: snapshot),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                status: cardStatus(amountPresentation.visual.status),
                amountText: amountPresentation.amountText,
                secondaryText: amountPresentation.secondaryText,
                errorText: amountPresentation.visual.errorText,
                backgroundColor: cardBackground,
                isDisconnected: amountPresentation.visual.isDisconnected,
                highlightColor: amountPresentation.visual.showsErrorHighlight ? errorColor : nil,
                balanceLabel: amountPresentation.balanceLabel
            )
        }
    }

    private func codexSlotPresentation(
        _ slot: CodexSlotViewModel,
        provider: ProviderDescriptor,
        codexTeamAliases: [String: String]
    ) -> MenuOfficialSlotCardPresentation<CodexSlotID> {
        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: slot.snapshot,
            language: viewModel.language,
            localization: menuQuotaLocalization
        )
        let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: metrics,
            language: viewModel.language,
            localization: menuQuotaLocalization
        )
        let metricDisplays = quotaMetricDisplays(
            from: visibleMetrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: slot.snapshot,
            disconnected: false
        )

        return MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: slot.slotID,
            title: slot.title,
            planType: MenuCardStatusPresenter.planType(for: provider, snapshot: slot.snapshot),
            subtitle: MenuSubtitlePresenter.officialAccountSubtitle(
                providerType: provider.type,
                snapshot: slot.snapshot,
                showAccountEmail: viewModel.showOfficialAccountEmailInMenuBar,
                codexTeamAliases: codexTeamAliases
            ),
            status: percentageStatus(
                snapshot: slot.snapshot,
                healthPercents: visibleMetrics.map(\.healthPercent),
                disconnected: false
            ),
            metricDisplays: metricDisplays,
            isActive: slot.isActive,
            canSwitch: slot.canSwitch,
            isSwitching: slot.isSwitching,
            switchActionLabel: viewModel.text(.codexSwitchAction)
        )
    }

    private func claudeSlotPresentation(
        _ slot: ClaudeSlotViewModel,
        provider: ProviderDescriptor
    ) -> MenuOfficialSlotCardPresentation<CodexSlotID> {
        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: slot.snapshot,
            language: viewModel.language,
            localization: menuQuotaLocalization
        )
        let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: metrics,
            language: viewModel.language,
            localization: menuQuotaLocalization
        )
        let metricDisplays = quotaMetricDisplays(
            from: visibleMetrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: slot.snapshot,
            disconnected: false
        )

        return MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: slot.slotID,
            title: slot.title,
            planType: MenuCardStatusPresenter.planType(for: provider, snapshot: slot.snapshot),
            subtitle: MenuSubtitlePresenter.officialAccountSubtitle(
                providerType: provider.type,
                snapshot: slot.snapshot,
                showAccountEmail: viewModel.showOfficialAccountEmailInMenuBar
            ),
            status: percentageStatus(
                snapshot: slot.snapshot,
                healthPercents: visibleMetrics.map(\.healthPercent),
                disconnected: false
            ),
            metricDisplays: metricDisplays,
            isActive: slot.isActive,
            canSwitch: slot.canSwitch,
            isSwitching: slot.isSwitching,
            switchActionLabel: viewModel.localizedText("切换", "Switch")
        )
    }

    private func quotaMetricDisplays(
        from metrics: [MenuQuotaMetric],
        blockageCandidates: [MenuQuotaMetric],
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        disconnected: Bool
    ) -> [MenuQuotaMetricDisplayPresentation] {
        MenuQuotaPresenter.metricDisplays(
            metrics: metrics,
            blockageCandidates: blockageCandidates,
            provider: provider,
            snapshot: snapshot,
            disconnected: disconnected,
            language: viewModel.language,
            now: now
        )
    }

    private func percentageMetricViews(
        from metrics: [MenuQuotaMetricDisplayPresentation]
    ) -> [PercentageMetricDisplay] {
        metrics.map { metric in
            PercentageMetricDisplay(
                id: metric.id,
                title: metric.title,
                valueText: metric.valueText,
                resetText: metric.resetText,
                percent: metric.percent,
                barColor: percentageBarColor(for: metric.barTone),
                isBlockedByDepletedQuota: metric.isBlockedByDepletedQuota
            )
        }
    }

    private func percentageVisualPresentation(
        snapshot: UsageSnapshot?,
        errorText: String?,
        healthPercents: [Double?]
    ) -> MenuCardVisualPresentation {
        MenuCardStatePresenter.percentageVisualPresentation(
            snapshot: snapshot,
            errorText: errorText,
            healthPercents: healthPercents,
            language: viewModel.language,
            tightText: viewModel.text(.statusTight),
            sufficientText: viewModel.text(.statusSufficient),
            exhaustedText: viewModel.text(.statusExhausted),
            disconnectedText: disconnectedStatusText
        )
    }

    private func percentageStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double?],
        disconnected: Bool
    ) -> MenuCardStatusPresentation {
        MenuCardStatusPresenter.percentageStatus(
            healthPercents: healthPercents,
            snapshot: snapshot,
            disconnected: disconnected,
            language: viewModel.language,
            tightText: viewModel.text(.statusTight),
            sufficientText: viewModel.text(.statusSufficient),
            exhaustedText: viewModel.text(.statusExhausted),
            disconnectedText: disconnectedStatusText
        )
    }

    nonisolated static func cachedFetchHealthStatusText(_ health: FetchHealth, language: AppLanguage) -> String {
        MenuCardStatusPresenter.cachedFetchHealthStatusText(health, language: language)
    }

    private var disconnectedStatusText: String {
        viewModel.text(.statusDisconnected)
    }

    private var menuQuotaLocalization: MenuQuotaLocalization {
        MenuQuotaLocalization(
            quotaFiveHour: "5h",
            quotaWeekly: viewModel.localizedText("周", "Weekly"),
            allModels: viewModel.localizedText("全部模型", "All models"),
            sonnetOnly: viewModel.localizedText("Sonnet 专用", "Sonnet only"),
            claudeDesign: viewModel.localizedText("Claude Design", "Claude Design"),
            session: viewModel.localizedText("会话", "Session"),
            monthly: viewModel.localizedText("月度", "Monthly"),
            currentPlan: viewModel.localizedText("当前套餐", "Current Plan"),
            autocomplete: viewModel.localizedText("自动补全", "Autocomplete"),
            dollarBalance: viewModel.localizedText("美元余额", "Dollar Balance")
        )
    }

    private func cardStatus(_ presentation: MenuCardStatusPresentation) -> CardStatus {
        CardStatus(
            text: presentation.text,
            color: color(for: presentation.tone)
        )
    }

    private func color(for tone: MenuCardStatusPresentation.Tone) -> Color {
        switch tone {
        case .normal:
            return sufficientColor
        case .warning:
            return warningColor
        case .error:
            return errorColor
        }
    }

    private func percentageBarColor(for tone: MenuQuotaMetricDisplayPresentation.BarTone) -> Color {
        switch tone {
        case .clear:
            return .clear
        case .normal:
            return sufficientColor
        case .warning:
            return warningColor
        case .error:
            return errorColor
        }
    }

    private var displayProviders: [ProviderDescriptor] {
        let enabledProviders = viewModel.config.providers.filter(\.enabled)
        let officialProviders = enabledProviders.filter { $0.family == .official }
        let thirdPartyProviders = enabledProviders.filter { $0.family == .thirdParty }
        return officialProviders + thirdPartyProviders
    }

    @ViewBuilder
    private func providerCards(for provider: ProviderDescriptor) -> some View {
        if provider.family == .official && provider.type == .codex {
            let slots = viewModel.codexSlotViewModels()
            let codexTeamAliases = MenuSubtitlePresenter.codexTeamAliasMap(from: slots.map(\.snapshot))
            if slots.isEmpty {
                providerCard(provider, codexTeamAliases: codexTeamAliases)
            } else if let group = MenuOfficialProviderGroupPresenter.group(
                from: slots.map { codexSlotPresentation($0, provider: provider, codexTeamAliases: codexTeamAliases) }
            ) {
                officialProviderGroupCard(
                    group,
                    iconName: "menu_codex_icon",
                    iconFallback: "terminal.fill"
                ) { slotID in
                    Task {
                        await viewModel.switchCodexProfile(slotID: slotID)
                    }
                }
            } else {
                providerCard(provider, codexTeamAliases: codexTeamAliases)
            }
        } else if provider.family == .official && provider.type == .claude {
            let slots = viewModel.claudeSlotViewModels()
            if let group = MenuOfficialProviderGroupPresenter.group(
                from: slots.map { claudeSlotPresentation($0, provider: provider) }
            ) {
                officialProviderGroupCard(
                    group,
                    iconName: iconName(for: provider),
                    iconFallback: fallbackIcon(for: provider)
                ) { slotID in
                    Task {
                        await viewModel.switchClaudeProfile(slotID: slotID)
                    }
                }
            }
        } else {
            providerCard(provider)
        }
    }

    @ViewBuilder
    private func officialProviderGroupCard(
        _ group: MenuOfficialProviderGroupPresentation<CodexSlotID>,
        iconName: String,
        iconFallback: String,
        switchAction: @escaping (CodexSlotID) -> Void
    ) -> some View {
        OfficialProviderGroupCard(
            iconName: iconName,
            iconFallback: iconFallback,
            primary: group.primary,
            primaryMetrics: percentageMetricViews(from: group.primary.metricDisplays),
            secondary: group.secondary,
            backgroundColor: cardBackground,
            statusColor: { cardStatus($0).color },
            switchAction: switchAction
        )
    }

    private func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return viewModel.text(.thirdPartyRelay) }
        return ProviderDefinitionRegistry.definition(for: provider).displayName
    }

    private func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else {
            return ProviderPresentationRegistry.iconName(for: nil)
        }
        return ProviderDefinitionRegistry.definition(for: provider).iconName
    }

    private func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        guard let provider else {
            return ProviderPresentationRegistry.fallbackIcon(for: nil)
        }
        return ProviderDefinitionRegistry.definition(for: provider).fallbackSystemIcon
    }

    private func restartClockIfNeeded() {
        stopClock()
        guard viewModel.menuPanelVisible else { return }
        tickClock()
        clockTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RuntimeDiagnosticsLimits.menuClockIntervalSeconds))
                guard !Task.isCancelled else { break }
                tickClock()
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func tickClock(referenceDate: Date = Date()) {
        now = referenceDate
        if viewModel.shouldShowPermissionGuide {
            viewModel.refreshPermissionStatusesIfNeeded(referenceDate: referenceDate)
        }
    }

    static func countdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        // menubar 倒计时文案统一走 CountdownFormatter，避免与设置页实现漂移。
        CountdownFormatter.text(to: target, now: now, placeholder: "-", language: language)
    }
}

private struct OfficialProviderGroupCard<ID: Hashable>: View {
    let iconName: String
    let iconFallback: String
    let primary: MenuOfficialSlotCardPresentation<ID>
    let primaryMetrics: [PercentageMetricDisplay]
    let secondary: [MenuOfficialSlotCardPresentation<ID>]
    let backgroundColor: Color
    let statusColor: (MenuCardStatusPresentation) -> Color
    let switchAction: (ID) -> Void
    private let groupBackgroundColor = Color.black.opacity(0.30)

    var body: some View {
        if secondary.isEmpty {
            primaryCard
        } else {
            VStack(alignment: .leading, spacing: 12) {
                primaryCard

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(secondary.enumerated()), id: \.element.id) { index, row in
                        CompactOfficialSlotRowView(
                            iconName: iconName,
                            iconFallback: iconFallback,
                            row: row,
                            statusColor: statusColor(row.status),
                            action: row.actionLabel != nil ? { switchAction(row.id) } : nil
                        )

                        if index < secondary.count - 1 {
                            ModelCardDivider()
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
            .background(
                SmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                    .fill(groupBackgroundColor)
            )
        }
    }

    private var primaryCard: some View {
        PercentageModelCard(
            title: primary.title,
            planType: primary.planType,
            iconName: iconName,
            iconFallback: iconFallback,
            subtitle: primary.subtitle,
            status: CardStatus(
                text: primary.status.text,
                color: statusColor(primary.status)
            ),
            metrics: primaryMetrics,
            errorText: primary.detailText,
            backgroundColor: backgroundColor,
            isDisconnected: false
        )
    }
}

private struct CompactOfficialSlotRowView<ID: Hashable>: View {
    private let compactLineHeight: CGFloat = 12
    private let titleMetricSpacing: CGFloat = 4
    private var rowContentHeight: CGFloat {
        compactLineHeight * 2 + titleMetricSpacing
    }
    let iconName: String
    let iconFallback: String
    let row: MenuOfficialSlotCardPresentation<ID>
    let statusColor: Color
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ModelIconBadge(
                iconName: iconName,
                fallback: iconFallback
            )

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: titleMetricSpacing) {
                    ModelTitleWithPlanType(
                        title: row.title,
                        planType: row.planType,
                        textColor: Color.white.opacity(0.80)
                    )
                    .frame(height: compactLineHeight, alignment: .top)
                    CompactMetricSummaryView(segments: row.compactMetricSegments)
                        .frame(height: compactLineHeight, alignment: .bottom)
                }
                .frame(height: rowContentHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 12) {
                    if let actionLabel = row.actionLabel, let action {
                        HoverActionButton(title: actionLabel, disabled: row.actionDisabled, action: action)
                    }

                    Text(row.status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(statusColor)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: rowContentHeight, alignment: .center)
            }
        }
        .frame(height: rowContentHeight, alignment: .center)
    }
}

private struct CompactMetricSummaryView: View {
    let segments: [MenuCompactMetricSegmentPresentation]

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(segment.title)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .lineSpacing(0)
                        .lineLimit(1)

                    Text(segment.valueText)
                        .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineSpacing(0)
                        .lineLimit(1)
                }
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

private struct PercentageModelCard: View {
    private let primaryMetricLeadingWidth: CGFloat = 172
    private let primaryMetricTrailingWidth: CGFloat = 104
    let title: String
    let planType: String?
    let iconName: String
    let iconFallback: String
    let subtitle: String?
    let status: CardStatus
    let metrics: [PercentageMetricDisplay]
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var highlightColor: Color? = nil
    var leadingAccentColor: Color? = nil
    var actionLabel: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil
    var infoText: String? = nil
    var infoTextColor: Color = Color.white.opacity(0.5)

    var body: some View {
        // 百分比型模型卡（Codex/Claude/Gemini 等）的整体样式。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                ModelIconBadge(
                    iconName: iconName,
                    fallback: iconFallback
                )

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        ModelTitleWithPlanType(
                            title: title,
                            planType: planType,
                            textColor: Color.white.opacity(0.80)
                        )
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineSpacing(0)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    HStack(spacing: 12) {
                        if let actionLabel, let action {
                            HoverActionButton(title: actionLabel, disabled: actionDisabled, action: action)
                        }

                        Text(status.text)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(status.color)
                            .lineSpacing(0)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(height: 24)

            ModelCardDivider()

            if metrics.count > 2 {
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(metricsForRow(row), id: \.id) { metric in
                                PercentageMetricView(metric: metric)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else if metrics.count == 2 {
                HStack(spacing: 24) {
                    PercentageMetricView(metric: metrics[0])
                        .frame(width: primaryMetricLeadingWidth, alignment: .leading)

                    PercentageMetricView(metric: metrics[1])
                        .frame(width: primaryMetricTrailingWidth, alignment: .leading)
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(metrics) { metric in
                        PercentageMetricView(metric: metric)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let errorText, !errorText.isEmpty {
                ModelCardDivider()

                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xD05757))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let infoText, !infoText.isEmpty {
                Text(infoText)
                    .font(.system(size: 10))
                    .foregroundStyle(infoTextColor)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            SmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                // 卡片背景色由外部传入，统一在这里渲染。
                .fill(backgroundColor)
        )
        .overlay(
            SmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                // 卡片描边：断连或高亮时显示。
                .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
        .overlay {
            if let leadingAccentColor {
                // 左侧状态条：距离卡片左边框 4px，上下固定间距 12px，高度自适应。
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(leadingAccentColor)
                        .frame(
                            width: 2,
                            height: max(0, proxy.size.height - 24)
                        )
                        .padding(.leading, 4)
                        .padding(.vertical, 12)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var borderColor: Color {
        if let highlightColor {
            return highlightColor
        }
        return Color(hex: 0xD05757)
    }

    private var hasBorder: Bool {
        highlightColor != nil || isDisconnected
    }

    private func metricsForRow(_ row: Int) -> [PercentageMetricDisplay] {
        let start = row * 2
        guard start < metrics.count else { return [] }
        let end = min(start + 2, metrics.count)
        return Array(metrics[start..<end])
    }
}

private struct ModelCardDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }
}

private struct ModelIconBadge: View {
    let iconName: String
    let fallback: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.15))
            .frame(width: 24, height: 24)
            .overlay {
                BundledIconView(
                    name: iconName,
                    fallback: fallback,
                    size: 12,
                    iconOpacity: 0.8
                )
            }
    }
}

private struct ModelTitleWithPlanType: View {
    let title: String
    let planType: String?
    let textColor: Color

    private var planTypeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.80),
                Color(red: 1.0, green: 0.819, blue: 0.225, opacity: 0.80)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .lineSpacing(0)
                .lineLimit(1)

            if let planType, !planType.isEmpty {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.40))
                    .frame(width: 1, height: 8)

                Text(planType)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(planTypeGradient)
                    .lineSpacing(0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }
}

private struct HoverActionButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        // 卡片右上角小按钮（hover 态边框和底色）。
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(disabled ? Color.white.opacity(0.35) : Color.white.opacity(0.80))
                .padding(.horizontal, 4)
                .frame(width: 28, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var backgroundColor: Color {
        if disabled {
            return Color.white.opacity(0.02)
        }
        return isHovered ? Color.white.opacity(0.12) : Color.clear
    }

    private var borderColor: Color {
        if disabled {
            return Color.white.opacity(0.08)
        }
        return isHovered ? Color.white.opacity(0.92) : Color.white.opacity(0.80)
    }
}

private struct PercentageMetricView: View {
    let metric: PercentageMetricDisplay

    var body: some View {
        // 百分比卡里的单个指标块（标题、倒计时、进度条）。
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(0)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    // 重置计时左侧时钟图标（Figma: icon/system/clock，10x10）。
                    BundledIconView(
                        name: "menu_reset_clock_icon",
                        fallback: "clock",
                        size: 10
                    )

                    // 重置计时文本（Figma: 10px、white 40%、单行）。
                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.40))
                        .lineSpacing(0)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 2) {
                Text(metric.valueText)
                    .font(AppFonts.numeric(size: 16, fallbackWeight: .bold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineSpacing(0)
                    .frame(width: metric.valueColumnWidth, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.30))
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, geo.size.width * percent / 100))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if metric.isBlockedByDepletedQuota {
                            QuotaBlockedStripePattern()
                                .fill(Color(hex: 0x4D4D4D))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 4)
            }
        }
    }
}

private struct AmountModelCard: View {
    let title: String
    let planType: String?
    let iconName: String
    let iconFallback: String
    let status: CardStatus
    let amountText: String
    let secondaryText: String?
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var highlightColor: Color? = nil
    let balanceLabel: String

    var body: some View {
        // 余额型模型卡（第三方 relay 等）的整体样式。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                ModelIconBadge(
                    iconName: iconName,
                    fallback: iconFallback
                )

                HStack(alignment: .center, spacing: 12) {
                    ModelTitleWithPlanType(
                        title: title,
                        planType: planType,
                        textColor: Color.white.opacity(0.80)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Text(status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(status.color)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: false)
            }
            .frame(height: 24)

            ModelCardDivider()

            VStack(alignment: .leading, spacing: 4) {
                Text(balanceLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(0)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    BundledIconView(
                        name: "menu_balance_icon",
                        fallback: "dollarsign.circle.fill",
                        size: 16,
                        iconOpacity: 0.9
                    )
                    Text(amountText)
                        .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.80))
                .lineSpacing(0)
                .frame(height: 16)

                if let secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(0)
                        .lineLimit(1)
                }
            }

            if let errorText, !errorText.isEmpty {
                ModelCardDivider()

                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xD05757))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            SmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                .fill(backgroundColor)
        )
        .overlay(
            SmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
    }

    private var borderColor: Color {
        if let highlightColor {
            return highlightColor
        }
        return Color(hex: 0xD05757)
    }

    private var hasBorder: Bool {
        highlightColor != nil || isDisconnected
    }
}

private struct BundledIconView: View {
    let name: String
    let fallback: String
    let size: CGFloat
    var tint: Color? = nil
    var iconOpacity: Double = 1

    var body: some View {
        // 图标渲染入口：优先资源图，找不到则回退 SF Symbols。
        Group {
            if let image = bundledImage(named: name) {
                if let tint {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(systemName: fallback)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint ?? Color.white.opacity(0.80))
            }
        }
        .frame(width: size, height: size)
        .opacity(iconOpacity)
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
}

private struct SmoothRoundedRectangle: InsettableShape {
    // Figma Corner smoothing 60% 近似实现：用于 menubar 模型卡片的 iOS 风格圆角。
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
        // k 越小，角越“平滑扁圆”；在圆弧 k 和 squircle k 之间插值。
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
        SmoothRoundedRectangle(
            cornerRadius: cornerRadius,
            smoothing: smoothing,
            insetAmount: insetAmount + amount
        )
    }
}

private struct CardStatus {
    let text: String
    let color: Color
}

private struct PercentageMetricDisplay: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let resetText: String
    let percent: Double?
    let barColor: Color
    let isBlockedByDepletedQuota: Bool

    var valueColumnWidth: CGFloat {
        valueText.contains("%") || valueText == "-"
            ? MetricValueLayoutFormatter.percentageMetricValueColumnWidth
            : MetricValueLayoutFormatter.metricValueColumnWidth
    }
}
