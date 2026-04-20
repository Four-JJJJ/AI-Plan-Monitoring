import AppKit
import SwiftUI

private struct MenuCardsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    @State private var now = Date()
    @State private var onboardingDiscoveryMessage: String?
    @State private var onboardingDiscoveryIsError = false
    @State private var onboardingDiscoveryInFlight = false
    @State private var cardsContentHeight: CGFloat = 0

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Menubar 视觉 Token（改这里可全局影响首页样式）
    // menubar 面板外层背景。
    private let panelBackground = Color(hex: 0x232323)
    // menubar 内部卡片背景。
    private let cardBackground = Color.black
    // 卡片垂直间距。
    private let cardSpacing: CGFloat = 6
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
    // menubar 卡片区最大高度：约 5.5 张模型卡可见，超出后在卡片区内滚动。
    private let modelCardHeightEstimate: CGFloat = 86
    private let maxVisibleModelCards: CGFloat = 5.5
    private let cardsViewportCornerRadius: CGFloat = 12

    var body: some View {
        // menubar 主面板布局：顶部 header + 下方卡片列表。
        VStack(alignment: .leading, spacing: 10) {
            header
            cards
        }
        .frame(width: 363)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
        .background(
            SmoothRoundedRectangle(cornerRadius: 20, smoothing: 0.6)
                // menubar 外层圆角背景。
                .fill(panelBackground)
        )
        .clipShape(
            SmoothRoundedRectangle(cornerRadius: 20, smoothing: 0.6)
        )
        .environment(\.colorScheme, .dark)
        .onReceive(clock) { value in
            now = value
            if viewModel.shouldShowPermissionGuide {
                viewModel.refreshPermissionStatusesIfNeeded(referenceDate: value)
            }
        }
    }

    private var header: some View {
        // 顶部工具条：更新时间 + 新版本入口 + 刷新/设置/退出三个图标按钮。
        HStack(spacing: 12) {
            Text(headerUpdatedText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.30))
                .lineSpacing(0)
                .lineLimit(1)

            Spacer(minLength: 8)

            if shouldShowUpdateButton {
                headerUpdateButton
            }

            HStack(spacing: headerActionSpacing) {
                headerIconButton(iconName: "refresh_icon", fallback: "arrow.clockwise") {
                    viewModel.refreshNow()
                }
                headerIconButton(iconName: "settings_icon", fallback: "gearshape") {
                    SettingsWindowController.shared.show(viewModel: viewModel)
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
            .padding(2)
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
        let maxHeight = modelCardHeightEstimate * maxVisibleModelCards + cardSpacing * floor(maxVisibleModelCards)
        let measured = cardsContentHeight > 0 ? cardsContentHeight : maxHeight
        return min(maxHeight, measured)
    }

    private var headerUpdatedText: String {
        if let date = viewModel.lastUpdatedAt {
            return "\(viewModel.text(.updatedAgo)) \(elapsedText(from: date))"
        }
        return viewModel.language == .zhHans ? "更新于 -" : "Updated -"
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

    private var shouldShowUpdateButton: Bool {
        viewModel.availableUpdate != nil
            || viewModel.updateDownloadInFlight
            || viewModel.updateInstallationInFlight
            || viewModel.updatePreparedVersion != nil
            || viewModel.updateInstallErrorMessage != nil
    }

    private var headerUpdateButton: some View {
        Button {
            viewModel.openLatestReleaseDownload()
        } label: {
            HStack(spacing: 4) {
                BundledIconView(
                    name: "settings_download_icon",
                    fallback: "arrow.down",
                    size: headerActionIconSize,
                    tint: updateHintColor
                )
                Text(headerUpdateTitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(updateHintColor)
                    .lineSpacing(0)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isUpdateActionEnabled)
        .accessibilityLabel(
            viewModel.language == .zhHans
                ? "应用更新操作：\(headerUpdateTitle)"
                : "App update action: \(headerUpdateTitle)"
        )
    }

    private var headerUpdateTitle: String {
        viewModel.updateActionTitle
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

        // menubar 模型卡入口：官方模型走百分比卡，第三方走余额卡。
        if provider.family == .official || provider.type == .kimi {
            let metrics = quotaMetrics(provider: provider, snapshot: snapshot)
            let visibleMetrics = Array((metrics.isEmpty ? placeholderQuotaMetrics(provider: provider) : metrics).prefix(2))
            let disconnected = error != nil
            let status = percentageStatus(metrics: visibleMetrics, snapshot: snapshot, disconnected: disconnected)
            let hasErrorState = disconnected || (snapshot?.valueFreshness == .empty && snapshot?.fetchHealth != .ok)

            PercentageModelCard(
                title: displayName(for: provider),
                planType: monitorPlanType(for: provider, snapshot: snapshot),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                subtitle: officialAccountSubtitle(
                    providerType: provider.type,
                    snapshot: snapshot,
                    codexTeamAliases: codexTeamAliases
                ),
                status: status,
                metrics: buildPercentageMetricDisplays(from: visibleMetrics, disconnected: disconnected),
                errorText: error,
                backgroundColor: cardBackground,
                isDisconnected: disconnected,
                highlightColor: hasErrorState ? errorColor : nil
            )
        } else {
            let stale = snapshot?.valueFreshness == .cachedFallback
            let disconnected = error != nil && !stale
            let status = amountStatus(snapshot: snapshot, disconnected: disconnected)
            let hasErrorState = disconnected || (snapshot?.valueFreshness == .empty && snapshot?.fetchHealth != .ok)
            AmountModelCard(
                title: displayName(for: provider),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                status: status,
                amountText: (disconnected || stale) ? "-" : formattedBalanceNumber(snapshot?.remaining),
                errorText: error,
                backgroundColor: cardBackground,
                isDisconnected: disconnected || stale,
                highlightColor: hasErrorState ? errorColor : nil,
                balanceLabel: viewModel.text(.balanceLabel)
            )
        }
    }

    private func codexSlotCard(
        _ slot: CodexSlotViewModel,
        provider: ProviderDescriptor,
        codexTeamAliases: [String: String]
    ) -> some View {
        // Codex 多账号卡片样式（激活账号左侧绿条）。
        let metrics = quotaMetrics(provider: provider, snapshot: slot.snapshot)
        let visibleMetrics = Array((metrics.isEmpty ? placeholderQuotaMetrics(provider: provider) : metrics).prefix(2))
        let showsSwitchAction = !slot.isActive && slot.canSwitch

        return PercentageModelCard(
            title: slot.title,
            planType: monitorPlanType(for: provider, snapshot: slot.snapshot),
            iconName: "menu_codex_icon",
            iconFallback: "terminal.fill",
            subtitle: officialAccountSubtitle(
                providerType: provider.type,
                snapshot: slot.snapshot,
                codexTeamAliases: codexTeamAliases
            ),
            status: percentageStatus(metrics: visibleMetrics, snapshot: slot.snapshot, disconnected: false),
            metrics: buildPercentageMetricDisplays(from: visibleMetrics, disconnected: false),
            errorText: nil,
            backgroundColor: cardBackground,
            isDisconnected: false,
            leadingAccentColor: slot.isActive ? Color.white.opacity(0.80) : nil,
            actionLabel: showsSwitchAction ? viewModel.text(.codexSwitchAction) : nil,
            actionDisabled: slot.isSwitching,
            action: showsSwitchAction ? {
                Task {
                    await viewModel.switchCodexProfile(slotID: slot.slotID)
                }
            } : nil,
            infoText: slot.switchMessage,
            infoTextColor: slot.switchMessageIsError ? errorColor : sufficientColor
        )
    }

    private func claudeSlotCard(_ slot: ClaudeSlotViewModel, provider: ProviderDescriptor) -> some View {
        let metrics = quotaMetrics(provider: provider, snapshot: slot.snapshot)
        let visibleMetrics = Array((metrics.isEmpty ? placeholderQuotaMetrics(provider: provider) : metrics).prefix(2))
        let showsSwitchAction = !slot.isActive && slot.canSwitch

        return PercentageModelCard(
            title: slot.title,
            planType: monitorPlanType(for: provider, snapshot: slot.snapshot),
            iconName: iconName(for: provider),
            iconFallback: fallbackIcon(for: provider),
            subtitle: officialAccountSubtitle(providerType: provider.type, snapshot: slot.snapshot),
            status: percentageStatus(metrics: visibleMetrics, snapshot: slot.snapshot, disconnected: false),
            metrics: buildPercentageMetricDisplays(from: visibleMetrics, disconnected: false),
            errorText: nil,
            backgroundColor: cardBackground,
            isDisconnected: false,
            leadingAccentColor: slot.isActive ? Color.white.opacity(0.80) : nil,
            actionLabel: showsSwitchAction ? viewModel.localizedText("切换", "Switch") : nil,
            actionDisabled: slot.isSwitching,
            action: showsSwitchAction ? {
                Task {
                    await viewModel.switchClaudeProfile(slotID: slot.slotID)
                }
            } : nil,
            infoText: slot.switchMessage,
            infoTextColor: slot.switchMessageIsError ? errorColor : sufficientColor
        )
    }

    private func officialAccountSubtitle(
        providerType: ProviderType,
        snapshot: UsageSnapshot?,
        codexTeamAliases: [String: String] = [:]
    ) -> String? {
        guard viewModel.showOfficialAccountEmailInMenuBar else { return nil }
        guard let value = snapshot?.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        guard providerType == .codex else {
            return value
        }

        guard let teamAlias = codexTeamAlias(for: snapshot, aliases: codexTeamAliases) else {
            return value
        }
        return "\(value) · \(teamAlias)"
    }

    private func buildPercentageMetricDisplays(from metrics: [QuotaMetric], disconnected: Bool) -> [PercentageMetricDisplay] {
        metrics.map { metric in
            let percent = disconnected ? nil : metric.displayPercent
            let displayPercent = percent.map { Int($0.rounded()) }
            let valueText = displayPercent.map { "\($0)%" } ?? "-"
            let resetLabel = disconnected ? "-" : Self.countdownText(to: metric.resetAt, now: now)
            return PercentageMetricDisplay(
                id: metric.id,
                title: metric.title,
                valueText: valueText,
                resetText: resetLabel,
                percent: (displayPercent ?? 0) > 0 ? percent : 0,
                barColor: percentageBarColor(metric.healthPercent, displayPercent: Int(metric.healthPercent.rounded()))
            )
        }
    }

    private func monitorPlanType(for provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        guard provider.family == .official else { return nil }
        let showsPlanType = provider.officialConfig?.showPlanTypeInMenuBar
            ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).showPlanTypeInMenuBar
        guard showsPlanType else { return nil }

        return PlanTypeDisplayFormatter.resolvedPlanType(
            providerType: provider.type,
            extrasPlanType: snapshot?.extras["planType"],
            rawPlanType: snapshot?.rawMeta["planType"]
        )
    }

    private func percentageStatus(metrics: [QuotaMetric], snapshot: UsageSnapshot?, disconnected: Bool) -> CardStatus {
        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return CardStatus(text: authFailureStatusText, color: errorColor)
            case .endpointMisconfigured:
                return CardStatus(text: configFailureStatusText, color: errorColor)
            case .rateLimited:
                return CardStatus(text: rateLimitedStatusText, color: warningColor)
            case .unreachable:
                return CardStatus(text: disconnectedStatusText, color: errorColor)
            case .ok:
                break
            }
        }

        if disconnected {
            return CardStatus(text: disconnectedStatusText, color: errorColor)
        }

        let displayedMinimum = metrics.map { Int($0.healthPercent.rounded()) }.min() ?? 0
        if displayedMinimum <= 0 {
            return CardStatus(text: viewModel.text(.statusExhausted), color: errorColor)
        }
        if displayedMinimum > 30 {
            return CardStatus(text: viewModel.text(.statusSufficient), color: sufficientColor)
        }
        if displayedMinimum < 10 {
            return CardStatus(text: viewModel.text(.statusTight), color: errorColor)
        }
        return CardStatus(text: viewModel.text(.statusTight), color: warningColor)
    }

    private func amountStatus(snapshot: UsageSnapshot?, disconnected: Bool) -> CardStatus {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return cachedRelayStatus(fetchHealth: snapshot.fetchHealth)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return CardStatus(text: localizedRelayState(authExpired: true), color: errorColor)
            case .endpointMisconfigured:
                return CardStatus(text: localizedRelayState(configIssue: true), color: errorColor)
            case .rateLimited:
                return CardStatus(text: localizedRelayState(rateLimited: true), color: warningColor)
            case .unreachable:
                return CardStatus(text: disconnectedStatusText, color: errorColor)
            case .ok:
                break
            }
        }

        if disconnected {
            return CardStatus(text: disconnectedStatusText, color: errorColor)
        }

        let remaining = snapshot?.remaining
        guard let remaining else {
            return CardStatus(text: viewModel.text(.statusTight), color: warningColor)
        }

        if remaining > 50 {
            return CardStatus(text: viewModel.text(.statusSufficient), color: sufficientColor)
        }
        if remaining > 0 {
            return CardStatus(text: viewModel.text(.statusTight), color: warningColor)
        }
        return CardStatus(text: viewModel.text(.statusExhausted), color: errorColor)
    }

    private func cachedRelayStatus(fetchHealth: FetchHealth) -> CardStatus {
        switch fetchHealth {
        case .authExpired:
            return CardStatus(text: localizedRelayState(authExpired: true, cached: true), color: errorColor)
        case .endpointMisconfigured:
            return CardStatus(text: localizedRelayState(configIssue: true, cached: true), color: errorColor)
        case .rateLimited:
            return CardStatus(text: localizedRelayState(rateLimited: true, cached: true), color: warningColor)
        case .unreachable:
            return CardStatus(text: localizedRelayState(cached: true), color: warningColor)
        case .ok:
            return CardStatus(text: localizedRelayState(cached: true), color: warningColor)
        }
    }

    private func localizedRelayState(
        authExpired: Bool = false,
        configIssue: Bool = false,
        rateLimited: Bool = false,
        cached: Bool = false
    ) -> String {
        if viewModel.language == .zhHans {
            if cached {
                if authExpired { return "认证失效(缓存)" }
                if configIssue { return "配置异常(缓存)" }
                if rateLimited { return "限流回退" }
                return "缓存回退"
            }
            if authExpired { return "认证失效" }
            if configIssue { return "配置异常" }
            if rateLimited { return "限流" }
            return "异常"
        }
        if cached {
            if authExpired { return "Auth Expired (Cached)" }
            if configIssue { return "Config Issue (Cached)" }
            if rateLimited { return "Rate Limited (Cached)" }
            return "Cached Fallback"
        }
        if authExpired { return "Auth Expired" }
        if configIssue { return "Config Issue" }
        if rateLimited { return "Rate Limited" }
        return "Error"
    }

    private var disconnectedStatusText: String {
        viewModel.text(.statusDisconnected)
    }

    private var authFailureStatusText: String {
        viewModel.language == .zhHans ? "认证故障" : "Auth Failure"
    }

    private var configFailureStatusText: String {
        viewModel.language == .zhHans ? "配置异常" : "Config Issue"
    }

    private var rateLimitedStatusText: String {
        viewModel.language == .zhHans ? "限流" : "Rate Limited"
    }

    private func percentageBarColor(_ percent: Double?, displayPercent: Int? = nil) -> Color {
        // 进度条颜色规则：<10 红，10~30 橙，>30 绿。
        guard let percent, percent > 0 else {
            return .clear
        }
        let shownPercent = displayPercent ?? Int(percent.rounded())
        if shownPercent <= 0 { return .clear }
        if shownPercent < 10 { return errorColor }
        if shownPercent <= 30 { return warningColor }
        return sufficientColor
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
            let codexTeamAliases = codexTeamAliasMap(from: slots.map(\.snapshot))
            if slots.isEmpty {
                providerCard(provider, codexTeamAliases: codexTeamAliases)
            } else {
                ForEach(slots) { slot in
                    codexSlotCard(
                        slot,
                        provider: provider,
                        codexTeamAliases: codexTeamAliases
                    )
                }
            }
        } else if provider.family == .official && provider.type == .claude {
            let slots = viewModel.claudeSlotViewModels()
            if slots.isEmpty {
                providerCard(provider)
            } else {
                ForEach(slots) { slot in
                    claudeSlotCard(slot, provider: provider)
                }
            }
        } else {
            providerCard(provider)
        }
    }

    private func codexTeamAliasMap(from snapshots: [UsageSnapshot]) -> [String: String] {
        var teamIDsByEmail: [String: Set<String>] = [:]
        for snapshot in snapshots {
            guard let key = codexTeamAliasKey(from: snapshot) else { continue }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let email = parts[0]
            let teamID = parts[1]
            teamIDsByEmail[email, default: []].insert(teamID)
        }

        var aliases: [String: String] = [:]
        for (email, teamIDs) in teamIDsByEmail {
            let sortedTeamIDs = teamIDs.sorted()
            guard sortedTeamIDs.count > 1 else { continue }
            for (index, teamID) in sortedTeamIDs.enumerated() {
                aliases["\(email)|\(teamID)"] = "Team \(codexTeamAliasToken(index: index))"
            }
        }
        return aliases
    }

    private func codexTeamAlias(for snapshot: UsageSnapshot?, aliases: [String: String]) -> String? {
        guard let key = codexTeamAliasKey(from: snapshot) else { return nil }
        return aliases[key]
    }

    private func codexTeamAliasKey(from snapshot: UsageSnapshot?) -> String? {
        guard let snapshot else { return nil }
        guard let email = CodexIdentity.normalizedEmail(
            snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"]
        ) else {
            return nil
        }
        guard let teamID = CodexIdentity.normalizedAccountID(CodexIdentity.teamID(from: snapshot)) else {
            return nil
        }
        return "\(email)|\(teamID)"
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

    private func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return viewModel.text(.thirdPartyRelay) }
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
            return provider.family == .official ? "Kimi Coding" : "KIMI"
        case .relay, .open, .dragon:
            return provider.name
        }
    }

    private func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "menu_relay_icon" }
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
            return firstExistingRelayIconName(["menu_deepseek_icon", "menu_deep_seek_icon"])
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return firstExistingRelayIconName(["menu_mimo_icon", "menu_xiaomimimo_icon", "menu_xiaomi_mimo_icon"])
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return firstExistingRelayIconName(["menu_minimax_icon", "menu_minimaxi_icon"])
        }
        return nil
    }

    private func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        for name in candidates {
            if Bundle.module.url(forResource: name, withExtension: "png") != nil ||
                Bundle.module.url(forResource: name, withExtension: "svg") != nil {
                return name
            }
        }
        return nil
    }

    private func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "link" }
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

    private func quotaMetrics(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> [QuotaMetric] {
        guard let snapshot else { return [] }
        if !snapshot.quotaWindows.isEmpty {
            return snapshot.quotaWindows
                .sorted { metricRank($0.kind) < metricRank($1.kind) }
                .map {
                    let displayPercent = provider.displaysUsedQuota ? clamp($0.usedPercent) : clamp($0.remainingPercent)
                    return QuotaMetric(
                        id: $0.id,
                        title: metricTitle(for: $0, provider: provider),
                        displayPercent: displayPercent,
                        healthPercent: clamp($0.remainingPercent),
                        resetAt: $0.resetAt
                    )
                }
        }
        return []
    }

    private func placeholderQuotaMetrics(provider: ProviderDescriptor) -> [QuotaMetric] {
        switch provider.type {
        case .codex, .claude, .kimi:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-5h", title: placeholderMetricTitle(viewModel.text(.quotaFiveHour), provider: provider), displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-weekly", title: placeholderMetricTitle(viewModel.text(.quotaWeekly), provider: provider), displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .gemini:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-pro", title: "Pro", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-flash", title: "Flash", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .copilot:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-premium", title: "Premium", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-chat", title: "Chat", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .zai:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-session", title: placeholderMetricTitle(viewModel.text(.quotaFiveHour), provider: provider), displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-weekly", title: placeholderMetricTitle(viewModel.text(.quotaWeekly), provider: provider), displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .amp:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-free", title: "Free", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-credits", title: "Credits", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .cursor:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-monthly", title: "Monthly", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-ondemand", title: "On-Demand", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .jetbrains:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-quota", title: "Quota", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .kiro:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-monthly", title: "Credits", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-bonus", title: "Bonus", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .windsurf:
            return [
                QuotaMetric(id: "\(provider.id)-placeholder-prompt", title: "Prompt", displayPercent: 0, healthPercent: 0, resetAt: nil),
                QuotaMetric(id: "\(provider.id)-placeholder-flex", title: "Flex", displayPercent: 0, healthPercent: 0, resetAt: nil)
            ]
        case .relay, .open, .dragon:
            return []
        }
    }

    private func metricRank(_ kind: UsageQuotaKind) -> Int {
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

    private func metricTitle(for window: UsageQuotaWindow, provider: ProviderDescriptor) -> String {
        let baseTitle: String
        switch window.kind {
        case .session:
            baseTitle = viewModel.text(.quotaFiveHour)
        case .weekly:
            baseTitle = viewModel.text(.quotaWeekly)
        default:
            if provider.type == .kimi,
               window.kind == .custom,
               window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "overall" {
                baseTitle = viewModel.text(.quotaWeekly)
            } else {
                baseTitle = window.title
            }
        }
        return placeholderMetricTitle(baseTitle, provider: provider)
    }

    private func placeholderMetricTitle(_ baseTitle: String, provider: ProviderDescriptor) -> String {
        guard provider.displaysUsedQuota else { return baseTitle }
        switch viewModel.language {
        case .zhHans:
            return "\(baseTitle)已用"
        case .en:
            return "\(baseTitle) used"
        }
    }

    private func formattedBalanceNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func elapsedText(from date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
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

    static func countdownText(to target: Date?, now: Date) -> String {
        // menubar 倒计时文案统一走 CountdownFormatter，避免与设置页实现漂移。
        CountdownFormatter.text(to: target, now: now, placeholder: "-")
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

private struct PercentageModelCard: View {
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
            HStack(spacing: 12) {
                HStack(alignment: .center, spacing: 6) {
                    BundledIconView(name: iconName, fallback: iconFallback, size: 12, iconOpacity: 0.8)
                    VStack(alignment: .leading, spacing: 0) {
                        ModelTitleWithPlanType(
                            title: title,
                            planType: planType,
                            textColor: Color.white.opacity(0.80)
                        )
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.80))
                                .lineSpacing(0)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
            }

            HStack(spacing: 24) {
                ForEach(metrics) { metric in
                    PercentageMetricView(metric: metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let errorText, !errorText.isEmpty {
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
                        .stroke(borderColor, lineWidth: 1)
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

            HStack(spacing: 6) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineSpacing(0)
                    .frame(width: 44, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.30))
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, geo.size.width * percent / 100))
                        }
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

private struct AmountModelCard: View {
    let title: String
    let iconName: String
    let iconFallback: String
    let status: CardStatus
    let amountText: String
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var highlightColor: Color? = nil
    let balanceLabel: String

    var body: some View {
        // 余额型模型卡（第三方 relay 等）的整体样式。
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    BundledIconView(name: iconName, fallback: iconFallback, size: 12, iconOpacity: 0.8)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(status.text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(status.color)
                    .lineSpacing(0)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(balanceLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(0)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    Text("💰")
                        .font(.system(size: 16, weight: .semibold))
                    Text(amountText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.80))
            }

            if let errorText, !errorText.isEmpty {
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
}

private struct QuotaMetric: Identifiable {
    let id: String
    let title: String
    let displayPercent: Double
    let healthPercent: Double
    let resetAt: Date?
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
