import AppKit
import SwiftUI

struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    @State private var now = Date()
    @State private var onboardingDiscoveryMessage: String?
    @State private var onboardingDiscoveryIsError = false
    @State private var onboardingDiscoveryInFlight = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let panelBackground = Color(hex: 0x232325)
    private let cardBackground = Color.black

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cards
            footer
        }
        .frame(width: 360)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelBackground)
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
        HStack(spacing: 12) {
            Text(viewModel.text(.appTitle))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            if let date = viewModel.lastUpdatedAt {
                Text("\(viewModel.text(.updatedAgo)) \(elapsedText(from: date))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        }
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if viewModel.shouldShowPermissionGuide {
                permissionGuideCard
            }

            if let codexProvider = codexProvider {
                let slots = viewModel.codexSlotViewModels()
                if slots.isEmpty {
                    providerCard(codexProvider)
                } else {
                    ForEach(slots) { slot in
                        codexSlotCard(slot, provider: codexProvider)
                    }
                }
            }

            ForEach(nonCodexProviders) { provider in
                providerCard(provider)
            }
        }
    }

    private var permissionGuideCard: some View {
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
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
    private func providerCard(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        if provider.family == .official || provider.type == .kimi {
            let metrics = quotaMetrics(provider: provider, snapshot: snapshot)
            let visibleMetrics = Array((metrics.isEmpty ? placeholderQuotaMetrics(provider: provider) : metrics).prefix(2))
            let disconnected = error != nil

            PercentageModelCard(
                title: displayName(for: provider),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                activeTag: nil,
                status: percentageStatus(metrics: visibleMetrics, disconnected: disconnected),
                metrics: buildPercentageMetricDisplays(from: visibleMetrics, disconnected: disconnected),
                errorText: error,
                backgroundColor: cardBackground,
                isDisconnected: disconnected
            )
        } else {
            let stale = snapshot?.valueFreshness == .cachedFallback
            let disconnected = error != nil && !stale
            AmountModelCard(
                title: displayName(for: provider),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                status: amountStatus(snapshot: snapshot, disconnected: disconnected),
                amountText: (disconnected || stale) ? "-" : formattedBalanceNumber(snapshot?.remaining),
                errorText: error,
                backgroundColor: cardBackground,
                isDisconnected: disconnected || stale,
                balanceLabel: viewModel.text(.balanceLabel)
            )
        }
    }

    private func codexSlotCard(_ slot: CodexSlotViewModel, provider: ProviderDescriptor) -> some View {
        let metrics = quotaMetrics(provider: provider, snapshot: slot.snapshot)
        let visibleMetrics = Array((metrics.isEmpty ? placeholderQuotaMetrics(provider: provider) : metrics).prefix(2))
        let showsSwitchAction = !slot.isActive && slot.canSwitch

        return PercentageModelCard(
            title: slot.title,
            iconName: "codex_icon",
            iconFallback: "terminal.fill",
            activeTag: slot.isActive ? viewModel.text(.statusActive) : nil,
            status: percentageStatus(metrics: visibleMetrics, disconnected: false),
            metrics: buildPercentageMetricDisplays(from: visibleMetrics, disconnected: false),
            errorText: nil,
            backgroundColor: cardBackground,
            isDisconnected: false,
            actionLabel: showsSwitchAction ? viewModel.text(.codexSwitchAction) : nil,
            actionDisabled: slot.isSwitching,
            action: showsSwitchAction ? {
                Task {
                    await viewModel.switchCodexProfile(slotID: slot.slotID)
                }
            } : nil,
            infoText: slot.switchMessage,
            infoTextColor: slot.switchMessageIsError ? Color(hex: 0xD83E3E) : Color(hex: 0x51DB42)
        )
    }

    private func buildPercentageMetricDisplays(from metrics: [QuotaMetric], disconnected: Bool) -> [PercentageMetricDisplay] {
        metrics.map { metric in
            let percent = disconnected ? nil : metric.displayPercent
            let displayPercent = percent.map { Int($0.rounded()) }
            let valueText = displayPercent.map { "\($0)%" } ?? "-"
            let resetLabel: String
            if disconnected {
                resetLabel = "-"
            } else if let resetAt = metric.resetAt {
                resetLabel = resetText(to: resetAt)
            } else {
                resetLabel = "-"
            }
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

    private func percentageStatus(metrics: [QuotaMetric], disconnected: Bool) -> CardStatus {
        if disconnected {
            return CardStatus(text: viewModel.text(.statusDisconnected), color: Color(hex: 0xD83E3E))
        }

        let displayedMinimum = metrics.map { Int($0.healthPercent.rounded()) }.min() ?? 0
        if displayedMinimum <= 0 {
            return CardStatus(text: viewModel.text(.statusExhausted), color: Color(hex: 0xD83E3E))
        }
        if displayedMinimum > 30 {
            return CardStatus(text: viewModel.text(.statusSufficient), color: Color(hex: 0x51DB42))
        }
        if displayedMinimum < 10 {
            return CardStatus(text: viewModel.text(.statusTight), color: Color(hex: 0xD83E3E))
        }
        return CardStatus(text: viewModel.text(.statusTight), color: Color(hex: 0xD87E3E))
    }

    private func amountStatus(snapshot: UsageSnapshot?, disconnected: Bool) -> CardStatus {
        if let snapshot, snapshot.valueFreshness == .cachedFallback {
            return cachedRelayStatus(fetchHealth: snapshot.fetchHealth)
        }

        if let snapshot, snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return CardStatus(text: localizedRelayState(authExpired: true), color: Color(hex: 0xD83E3E))
            case .endpointMisconfigured:
                return CardStatus(text: localizedRelayState(configIssue: true), color: Color(hex: 0xD83E3E))
            case .rateLimited:
                return CardStatus(text: localizedRelayState(rateLimited: true), color: Color(hex: 0xD87E3E))
            case .unreachable:
                return CardStatus(text: viewModel.text(.statusDisconnected), color: Color(hex: 0xD83E3E))
            case .ok:
                break
            }
        }

        if disconnected {
            return CardStatus(text: viewModel.text(.statusDisconnected), color: Color(hex: 0xD83E3E))
        }

        let remaining = snapshot?.remaining
        guard let remaining else {
            return CardStatus(text: viewModel.text(.statusTight), color: Color(hex: 0xD87E3E))
        }

        if remaining > 50 {
            return CardStatus(text: viewModel.text(.statusSufficient), color: Color(hex: 0x51DB42))
        }
        if remaining > 0 {
            return CardStatus(text: viewModel.text(.statusTight), color: Color(hex: 0xD87E3E))
        }
        return CardStatus(text: viewModel.text(.statusExhausted), color: Color(hex: 0xD83E3E))
    }

    private func cachedRelayStatus(fetchHealth: FetchHealth) -> CardStatus {
        switch fetchHealth {
        case .authExpired:
            return CardStatus(text: localizedRelayState(authExpired: true, cached: true), color: Color(hex: 0xD83E3E))
        case .endpointMisconfigured:
            return CardStatus(text: localizedRelayState(configIssue: true, cached: true), color: Color(hex: 0xD83E3E))
        case .rateLimited:
            return CardStatus(text: localizedRelayState(rateLimited: true, cached: true), color: Color(hex: 0xD87E3E))
        case .unreachable:
            return CardStatus(text: localizedRelayState(cached: true), color: Color(hex: 0xD87E3E))
        case .ok:
            return CardStatus(text: localizedRelayState(cached: true), color: Color(hex: 0xD87E3E))
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

    private func percentageBarColor(_ percent: Double?, displayPercent: Int? = nil) -> Color {
        guard let percent, percent > 0 else {
            return .clear
        }
        let shownPercent = displayPercent ?? Int(percent.rounded())
        if shownPercent <= 0 { return .clear }
        if shownPercent < 10 { return Color(hex: 0xD83E3E) }
        if shownPercent <= 30 { return Color(hex: 0xD87E3E) }
        return Color(hex: 0x51DB42)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(title: viewModel.text(.refreshNow), iconName: "refresh_icon", fallback: "arrow.clockwise") {
                viewModel.refreshNow()
            }
            footerButton(title: viewModel.text(.settings).replacingOccurrences(of: "...", with: ""), iconName: "settings_icon", fallback: "gearshape") {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }
            footerButton(title: viewModel.text(.quit), iconName: "quit_icon", fallback: "xmark") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(height: 24)
    }

    private func footerButton(title: String, iconName: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                BundledIconView(name: iconName, fallback: fallback, size: 12, tint: Color.white.opacity(0.60))
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var displayProviders: [ProviderDescriptor] {
        viewModel.config.providers
            .filter(\.enabled)
            .sorted { lhs, rhs in
                let l = providerRank(lhs)
                let r = providerRank(rhs)
                if l != r { return l < r }
                if lhs.family == .thirdParty && rhs.family == .thirdParty {
                    let lHealth = relayHealthRank(lhs)
                    let rHealth = relayHealthRank(rhs)
                    if lHealth != rHealth { return lHealth < rHealth }

                    let lRemaining = viewModel.snapshots[lhs.id]?.remaining ?? -.greatestFiniteMagnitude
                    let rRemaining = viewModel.snapshots[rhs.id]?.remaining ?? -.greatestFiniteMagnitude
                    if lRemaining != rRemaining { return lRemaining > rRemaining }
                }
                return lhs.id < rhs.id
            }
    }

    private var codexProvider: ProviderDescriptor? {
        displayProviders.first { $0.type == .codex && $0.family == .official }
    }

    private var nonCodexProviders: [ProviderDescriptor] {
        displayProviders.filter { !($0.type == .codex && $0.family == .official) }
    }

    private func providerRank(_ provider: ProviderDescriptor) -> Int {
        if provider.family == .official {
            switch provider.type {
            case .codex: return 0
            case .claude: return 1
            case .gemini: return 2
            case .copilot: return 3
            case .zai: return 4
            case .cursor: return 5
            case .windsurf: return 6
            case .amp: return 7
            case .jetbrains: return 8
            case .kiro: return 9
            case .kimi: return 10
            case .relay, .open, .dragon: return 11
            }
        }
        switch provider.type {
        case .kimi: return 12
        case .relay, .open, .dragon: return 13
        case .codex, .claude, .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf: return 14
        }
    }

    private func relayHealthRank(_ provider: ProviderDescriptor) -> Int {
        let snapshot = viewModel.snapshots[provider.id]
        switch (snapshot?.valueFreshness, snapshot?.fetchHealth) {
        case (.live?, _):
            return 0
        case (.cachedFallback?, .authExpired?):
            return 2
        case (.cachedFallback?, _):
            return 1
        case (.empty?, .authExpired?):
            return 3
        case (.empty?, .endpointMisconfigured?), (.empty?, .unreachable?), (.empty?, .rateLimited?):
            return 4
        default:
            return 2
        }
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
            return "KIMI"
        case .relay, .open, .dragon:
            return provider.name
        }
    }

    private func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "relay_icon" }
        switch provider.type {
        case .codex:
            return "codex_icon"
        case .kimi:
            return "kimi_icon"
        case .relay, .open, .dragon:
            return "relay_icon"
        case .claude, .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf:
            return "relay_icon"
        }
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

    private func resetText(to target: Date) -> String {
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60

        switch viewModel.language {
        case .zhHans:
            if days > 0 {
                return "\(days)天\(hours):\(String(format: "%02d", minutes)): \(String(format: "%02d", seconds)) 重置".replacingOccurrences(of: " ", with: "")
            }
            return "\(hours):\(String(format: "%02d", minutes)): \(String(format: "%02d", seconds)) 重置".replacingOccurrences(of: " ", with: "")
        case .en:
            if days > 0 {
                return "resets in \(days)d \(hours):\(String(format: "%02d", minutes)): \(String(format: "%02d", seconds))"
            }
            return "resets in \(hours):\(String(format: "%02d", minutes)): \(String(format: "%02d", seconds))"
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

private struct PercentageModelCard: View {
    let title: String
    let iconName: String
    let iconFallback: String
    let activeTag: String?
    let status: CardStatus
    let metrics: [PercentageMetricDisplay]
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var actionLabel: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil
    var infoText: String? = nil
    var infoTextColor: Color = Color.white.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    BundledIconView(name: iconName, fallback: iconFallback, size: 12)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    if let activeTag, !activeTag.isEmpty {
                        Text(activeTag)
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: 0x296322))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if let actionLabel, let action {
                        HoverActionButton(title: actionLabel, disabled: actionDisabled, action: action)
                    }

                    Text(status.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(status.color)
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
                    .foregroundStyle(Color(hex: 0xD83E3E))
            }

            if let infoText, !infoText.isEmpty {
                Text(infoText)
                    .font(.system(size: 10))
                    .foregroundStyle(infoTextColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xD83E3E), lineWidth: isDisconnected ? 1 : 0)
        )
    }
}

private struct HoverActionButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? Color.white.opacity(0.35) : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    Capsule(style: .continuous)
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
            return Color.white.opacity(0.04)
        }
        return isHovered ? Color(hex: 0x2F6BFF).opacity(0.22) : Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if disabled {
            return Color.white.opacity(0.08)
        }
        return isHovered ? Color(hex: 0x2F6BFF) : Color.white.opacity(0.14)
    }
}

private struct PercentageMetricView: View {
    let metric: PercentageMetricDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 4)
                Text(metric.resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
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
    let balanceLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    BundledIconView(name: iconName, fallback: iconFallback, size: 12)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(status.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status.color)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(balanceLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.50))
                HStack(spacing: 2) {
                    Text("💰")
                        .font(.system(size: 16, weight: .semibold))
                    Text(amountText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xD83E3E))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xD83E3E), lineWidth: isDisconnected ? 1 : 0)
        )
    }
}

private struct BundledIconView: View {
    let name: String
    let fallback: String
    let size: CGFloat
    var tint: Color? = nil

    var body: some View {
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
                    .foregroundStyle(tint ?? Color.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
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
