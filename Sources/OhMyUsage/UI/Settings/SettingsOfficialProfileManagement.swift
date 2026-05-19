import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    struct CodexTeamDisplayInfo {
        var alias: String
        var teamID: String
    }

    @ViewBuilder
    func settingsModelTitleWithPlanType(title: String, planType: String?) -> some View {
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

    func officialAccountMonitorCard<Content: View>(
        highlightColor: Color? = nil,
        leadingAccentColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .background(
                DialogSmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                    .fill(cardBackground)
            )
            .overlay(
                DialogSmoothRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                    .stroke(highlightColor ?? outlineColor, lineWidth: 1)
            )
            .overlay {
                if let leadingAccentColor {
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

    var settingsModelCardDivider: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(dividerColor)
            .frame(height: 1)
    }

    var settingsModelIconBadgeFillColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.06) : Color.white.opacity(0.15)
    }

    var settingsCurrentAccountAccentColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.80) : Color.white.opacity(0.80)
    }

    func settingsModelIconBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(settingsModelIconBadgeFillColor)
            .frame(width: 24, height: 24)
            .overlay {
                content()
            }
    }

    @ViewBuilder
    func codexProfileManagementSection() -> some View {
        let refreshAnchor = viewModel.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0
        let profiles = viewModel.codexProfilesForSettings()
        let slotsByID = Dictionary(uniqueKeysWithValues: viewModel.codexSlotViewModelsForSettings().map { ($0.slotID, $0) })
        let teamDisplayBySlotID = codexTeamDisplayInfoBySlotID(profiles: profiles)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.slotID.rawValue) { index, profile in
                codexImportedProfileCard(
                    profile: profile,
                    slotViewModel: slotsByID[profile.slotID],
                    teamDisplay: teamDisplayBySlotID[profile.slotID],
                    showsBottomSeparator: index < profiles.count - 1
                )
            }
        }
        .id(refreshAnchor)
    }

    func codexImportedProfileCard(
        profile: CodexAccountProfile,
        slotViewModel: CodexSlotViewModel?,
        teamDisplay: CodexTeamDisplayInfo?,
        showsBottomSeparator: Bool = false
    ) -> some View {
        let key = profile.slotID.rawValue
        let snapshot = slotViewModel?.snapshot
        let provider = officialMonitoringProvider(for: .codex)
        let status = officialSubscriptionAccountStatus(provider: provider, snapshot: snapshot)
        let metrics = codexQuotaMetrics(provider: provider, snapshot: snapshot)
        let hasError = snapshot?.valueFreshness == .empty
        let subtitle = profileEmailWithNote(
            email: profile.accountEmail,
            note: profile.note,
            fallback: viewModel.text(.codexProfileEmailUnknown)
        )

        return officialSubscriptionAccountRow(
            title: subtitle,
            isCurrent: provider.enabled && profile.isCurrentSystemAccount,
            planType: officialMonitorPlanType(providerType: provider.type, snapshot: snapshot),
            statusText: provider.enabled ? status.text : "",
            statusColor: provider.enabled ? status.color : .clear,
            metrics: metrics,
            errorText: hasError ? snapshot?.note : nil,
            trailingDetail: teamDisplay.map(localizedCodexTeamInfoText),
            footerResult: profileDraftState.codexProfileResult[key],
            retryTitle: hasError ? viewModel.localizedText("重新OAuth", "Retry OAuth") : nil,
            retryAction: hasError ? { viewModel.startOAuthImport(providerType: .codex, slotID: profile.slotID) } : nil,
            editAction: { openCodexProfileEditor(slotID: profile.slotID, existingProfile: profile) },
            deleteAction: { dialogState.codexProfilePendingDelete = profile.slotID },
            showsBottomSeparator: showsBottomSeparator
        )
    }

    func codexTeamDisplayInfoBySlotID(profiles: [CodexAccountProfile]) -> [CodexSlotID: CodexTeamDisplayInfo] {
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

    func localizedCodexTeamInfoText(_ teamDisplay: CodexTeamDisplayInfo) -> String {
        if viewModel.language == .zhHans {
            return "\(teamDisplay.alias) · Team ID: \(teamDisplay.teamID)"
        }
        return "\(teamDisplay.alias) · Team ID: \(teamDisplay.teamID)"
    }

    func codexTeamAliasToken(index: Int) -> String {
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

    func codexImportNextProfileCard(nextSlotID: CodexSlotID) -> some View {
        let oauthState = viewModel.oauthImportState(for: .codex)
        let oauthRunning = oauthState?.isRunning ?? false

        return officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    settingsModelIconBadge {
                        codexAccountIcon(size: 12)
                    }
                    Text(viewModel.language == .zhHans ? "导入另一个Codex" : viewModel.text(.codexImportNextProfile))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                settingsModelCardDivider
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
    func claudeProfileManagementSection() -> some View {
        let refreshAnchor = viewModel.lastUpdatedAt?.timeIntervalSinceReferenceDate ?? 0
        let profiles = viewModel.claudeProfilesForSettings()
        let slotsByID = Dictionary(uniqueKeysWithValues: viewModel.claudeSlotViewModelsForSettings().map { ($0.slotID, $0) })

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.slotID.rawValue) { index, profile in
                claudeImportedProfileCard(
                    profile: profile,
                    slotViewModel: slotsByID[profile.slotID],
                    showsBottomSeparator: index < profiles.count - 1
                )
            }
        }
        .id(refreshAnchor)
    }

    func claudeImportedProfileCard(
        profile: ClaudeAccountProfile,
        slotViewModel: ClaudeSlotViewModel?,
        showsBottomSeparator: Bool = false
    ) -> some View {
        let key = profile.slotID.rawValue
        let snapshot = slotViewModel?.snapshot
        let provider = officialMonitoringProvider(for: .claude)
        let status = officialSubscriptionAccountStatus(provider: provider, snapshot: snapshot)
        let metrics = codexQuotaMetrics(provider: provider, snapshot: snapshot)
        let hasError = snapshot?.valueFreshness == .empty
        let subtitle = claudeProfileSubtitle(
            profile: profile,
            fallback: viewModel.localizedText("未识别账号", "Account unavailable")
        )

        return officialSubscriptionAccountRow(
            title: subtitle,
            isCurrent: provider.enabled && profile.isCurrentSystemAccount,
            planType: officialMonitorPlanType(providerType: provider.type, snapshot: snapshot),
            statusText: provider.enabled ? status.text : "",
            statusColor: provider.enabled ? status.color : .clear,
            metrics: metrics,
            errorText: hasError ? snapshot?.note : nil,
            trailingDetail: claudeProfileSourceHint(profile),
            footerResult: profileDraftState.claudeProfileResult[key],
            retryTitle: hasError ? claudeProfileRetryTitle(profile.source) : nil,
            retryAction: hasError ? claudeProfileRetryAction(profile) : nil,
            editAction: { openClaudeProfileEditor(slotID: profile.slotID, existingProfile: profile) },
            deleteAction: { dialogState.claudeProfilePendingDelete = profile.slotID },
            showsBottomSeparator: showsBottomSeparator
        )
    }

    func claudeImportNextProfileCard(nextSlotID: CodexSlotID) -> some View {
        let oauthState = viewModel.oauthImportState(for: .claude)
        let oauthRunning = oauthState?.isRunning ?? false

        return officialAccountMonitorCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    settingsModelIconBadge {
                        claudeAccountIcon(size: 12)
                    }
                    Text(viewModel.localizedText("导入另一个 Claude", "Import another Claude account"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 8)
                }
                .frame(height: 24)

                settingsModelCardDivider
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

    func claudeProfileSourceLabel(_ source: ClaudeProfileSource) -> String {
        switch source {
        case .configDir:
            return viewModel.localizedText("目录绑定", "Config Directory")
        case .manualCredentials:
            return viewModel.localizedText("手动粘贴", "Manual Paste")
        }
    }

    func claudeProfileSourceHint(_ profile: ClaudeAccountProfile) -> String {
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

    func claudeProfileRetryTitle(_ source: ClaudeProfileSource) -> String {
        switch source {
        case .manualCredentials:
            return viewModel.localizedText("重新粘贴json", "Paste JSON Again")
        case .configDir:
            return viewModel.localizedText("重新OAuth", "Retry OAuth")
        }
    }

    func claudeProfileRetryAction(_ profile: ClaudeAccountProfile) -> () -> Void {
        switch profile.source {
        case .manualCredentials:
            return { openClaudeProfileEditor(slotID: profile.slotID, existingProfile: profile) }
        case .configDir:
            return { viewModel.startOAuthImport(providerType: .claude, slotID: profile.slotID) }
        }
    }

    func officialSubscriptionAccountStatus(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> (text: String, color: Color) {
        let healthPercents = codexQuotaMetrics(provider: provider, snapshot: snapshot).compactMap(\.healthPercent)
        let status = Self.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        )

        switch status {
        case .unknown:
            return (viewModel.language == .zhHans ? "未知" : "Unknown", Color.white.opacity(0.55))
        case .authError:
            return (viewModel.language == .zhHans ? "认证故障" : "Auth Error", Color(hex: 0xD05858))
        case .configError:
            return (viewModel.language == .zhHans ? "配置异常" : "Config Error", Color(hex: 0xD05858))
        case .rateLimited:
            return (viewModel.language == .zhHans ? "限流" : "Rate Limited", Color(hex: 0xD87E3E))
        case .disconnected:
            return (viewModel.language == .zhHans ? "连接失败" : "Disconnected", Color(hex: 0xD05858))
        case .sufficient:
            return (viewModel.text(.statusSufficient), Color(hex: 0x69BD64))
        case .tight:
            return (viewModel.text(.statusTight), Color(hex: 0xD87E3E))
        case .exhausted:
            return (viewModel.text(.statusExhausted), Color(hex: 0xD05858))
        }
    }

    func officialSubscriptionAccountRow(
        title: String,
        isCurrent: Bool,
        planType: String? = nil,
        statusText: String,
        statusColor: Color,
        metrics: [CodexQuotaMetricDisplay],
        errorText: String?,
        trailingDetail: String?,
        footerResult: String?,
        retryTitle: String?,
        retryAction: (() -> Void)?,
        editAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        showsBottomSeparator: Bool = false
    ) -> some View {
        let trimmedError = officialSubscriptionAccountVisibleError(errorText)
        let compactMetrics = metrics.prefix(2).map { metric in
            SettingsCompactRecordMetric(
                id: metric.id,
                title: metric.title,
                valueText: metric.valueText,
                resetText: metric.resetText
            )
        }
        let actions: [SettingsCompactRecordAction] = {
            var output: [SettingsCompactRecordAction] = []
            if let retryTitle, let retryAction {
                output.append(SettingsCompactRecordAction(id: "retry", title: retryTitle, action: retryAction))
            }
            output.append(SettingsCompactRecordAction(id: "edit", title: codexEditButtonTitle, action: editAction))
            output.append(SettingsCompactRecordAction(id: "delete", title: codexDeleteButtonTitle, destructive: true, action: deleteAction))
            return output
        }()

        return officialSubscriptionAccountRecordRow(
            title: title,
            currentText: isCurrent ? viewModel.localizedText("正在使用", "Current") : nil,
            planType: planType,
            statusText: statusText,
            statusColor: statusColor,
            errorText: trimmedError,
            metrics: compactMetrics,
            actions: actions,
            showsBottomSeparator: showsBottomSeparator
        )
    }

    func officialSubscriptionReadOnlyAccountRow(
        title: String,
        isCurrent: Bool = true,
        planType: String? = nil,
        statusText: String,
        statusColor: Color,
        metrics: [CodexQuotaMetricDisplay],
        errorText: String?,
        showsBottomSeparator: Bool = false
    ) -> some View {
        let compactMetrics = metrics.prefix(2).map { metric in
            SettingsCompactRecordMetric(
                id: metric.id,
                title: metric.title,
                valueText: metric.valueText,
                resetText: metric.resetText
            )
        }

        return officialSubscriptionAccountRecordRow(
            title: title,
            currentText: isCurrent ? viewModel.localizedText("正在使用", "Current") : nil,
            planType: planType,
            statusText: statusText,
            statusColor: statusColor,
            errorText: officialSubscriptionAccountVisibleError(errorText),
            metrics: compactMetrics,
            actions: [],
            showsBottomSeparator: showsBottomSeparator
        )
    }

    func officialSubscriptionAccountRecordRow(
        title: String,
        currentText: String?,
        planType: String?,
        statusText: String,
        statusColor: Color,
        errorText: String?,
        metrics: [SettingsCompactRecordMetric],
        actions: [SettingsCompactRecordAction],
        showsBottomSeparator: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    if let planType, !planType.isEmpty {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(settingsRowStrokeColor)
                            .frame(width: 1, height: 8)
                            .fixedSize(horizontal: true, vertical: true)

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
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let currentText, !currentText.isEmpty {
                        Text(currentText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0x69BD64))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .frame(height: 12)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD05858))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 12) {
                settingsCompactRecordMetricsLine(metrics, columnSpacing: 40)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                ForEach(actions) { action in
                    settingsCompactRecordTextActionButton(
                        action.title,
                        destructive: action.destructive,
                        action: action.action
                    )
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: officialSubscriptionAccountRowHeight(errorText), alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if showsBottomSeparator {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
            }
        }
    }

    func officialSubscriptionAccountVisibleError(_ errorText: String?) -> String? {
        guard let errorText else { return nil }
        let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func officialSubscriptionAccountRowHeight(_ errorText: String?) -> CGFloat {
        guard let errorText, !errorText.isEmpty else { return 62 }
        return errorText.count > 56 ? 96 : 83
    }
}
