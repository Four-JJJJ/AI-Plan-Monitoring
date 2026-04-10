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
    @State private var kimiAuthModeInputs: [String: KimiAuthMode] = [:]
    @State private var kimiAutoCookieInputs: [String: Bool] = [:]
    @State private var kimiManualTokenInputs: [String: String] = [:]
    @State private var kimiDetectResult: [String: String] = [:]

    @State private var newProviderName = ""
    @State private var newProviderBaseURL = "https://"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(viewModel.text(.settingsTitle))
                    .font(.headline)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    generalSection
                    addRelaySection
                    providersSection
                }
                .padding(.vertical, 2)
            }
        }
        .glassPanel(cornerRadius: 20)
        .padding(10)
        .onAppear {
            seedInputsFromConfig()
        }
        .onChange(of: viewModel.config.providers.map(\.id)) { _, _ in
            seedInputsFromConfig()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.general))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Text(viewModel.text(.language))
                    .foregroundStyle(.secondary)
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
            }
        }
        .glassCard(cornerRadius: 12)
    }

    private var addRelaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.addRelayProvider))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField(viewModel.text(.providerName), text: $newProviderName)
                    .textFieldStyle(.roundedBorder)
                TextField(viewModel.text(.baseURL), text: $newProviderBaseURL)
                    .textFieldStyle(.roundedBorder)
                Button(viewModel.text(.addProvider)) {
                    viewModel.addOpenRelay(name: newProviderName, baseURL: newProviderBaseURL)
                    newProviderName = ""
                }
                .buttonStyle(.borderedProminent)
            }

            Text(viewModel.text(.relayRequiredFieldsHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard(cornerRadius: 12)
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.providers))
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.config.providers) { provider in
                providerSettingsCard(provider)
            }
        }
    }

    @ViewBuilder
    private func providerSettingsCard(_ provider: ProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.name)
                    .font(.headline)
                Spacer()
                let enabledBinding = Binding(
                    get: { provider.enabled },
                    set: { viewModel.setEnabled($0, providerID: provider.id) }
                )
                Toggle(viewModel.text(.enabled), isOn: enabledBinding)
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
                toggleStateBadge(isOn: enabledBinding.wrappedValue)
            }

            HStack(spacing: 8) {
                Text(viewModel.text(.lowThreshold))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { provider.threshold.lowRemaining },
                        set: { viewModel.setLowThreshold($0, providerID: provider.id) }
                    ),
                    in: 0...100
                )
                Text(String(format: "%.0f", provider.threshold.lowRemaining))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }

            if provider.type == .open || provider.type == .dragon {
                openRelayConfigSection(provider)
            } else if provider.type == .kimi {
                kimiConfigSection(provider)
            }
        }
        .glassCard(cornerRadius: 12)
    }

    @ViewBuilder
    private func openRelayConfigSection(_ provider: ProviderDescriptor) -> some View {
        let accountAuth = provider.openConfig?.accountBalance?.auth

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(viewModel.text(.providerName), text: Binding(
                    get: { providerNameInputs[provider.id] ?? provider.name },
                    set: { providerNameInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.baseURL), text: Binding(
                    get: { baseURLInputs[provider.id] ?? (provider.baseURL ?? "") },
                    set: { baseURLInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            let tokenChannelBinding = Binding(
                get: { tokenUsageEnabledInputs[provider.id] ?? (provider.openConfig?.tokenUsageEnabled ?? true) },
                set: { tokenUsageEnabledInputs[provider.id] = $0 }
            )
            labeledToggle(viewModel.text(.enableTokenChannel), isOn: tokenChannelBinding)

            HStack {
                SecureField(viewModel.text(.pasteToken), text: Binding(
                    get: { tokenInputs[provider.id, default: ""] },
                    set: { tokenInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button(viewModel.text(.saveToken)) {
                    let token = tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { return }
                    _ = viewModel.saveToken(token, for: provider)
                    tokenInputs[provider.id] = ""
                    viewModel.restartPolling()
                }
                .buttonStyle(.bordered)

                Text(viewModel.hasToken(for: provider) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                    .font(.caption)
                    .foregroundStyle(viewModel.hasToken(for: provider) ? .green : .secondary)
            }

            Divider()

            let accountChannelBinding = Binding(
                get: { accountEnabledInputs[provider.id] ?? (provider.openConfig?.accountBalance?.enabled ?? false) },
                set: { accountEnabledInputs[provider.id] = $0 }
            )
            labeledToggle(viewModel.text(.enableAccountChannel), isOn: accountChannelBinding)

            HStack {
                SecureField(viewModel.text(.pasteSystemToken), text: Binding(
                    get: { systemTokenInputs[provider.id, default: ""] },
                    set: { systemTokenInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button(viewModel.text(.saveToken)) {
                    guard let accountAuth else { return }
                    let token = systemTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { return }
                    _ = viewModel.saveToken(token, auth: accountAuth)
                    systemTokenInputs[provider.id] = ""
                    viewModel.restartPolling()
                }
                .buttonStyle(.bordered)

                if let accountAuth {
                    Text(viewModel.hasToken(auth: accountAuth) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                        .font(.caption)
                        .foregroundStyle(viewModel.hasToken(auth: accountAuth) ? .green : .secondary)
                }
            }

            HStack(spacing: 8) {
                TextField(viewModel.text(.authHeader), text: Binding(
                    get: { authHeaderInputs[provider.id] ?? (provider.openConfig?.accountBalance?.authHeader ?? "Authorization") },
                    set: { authHeaderInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.authScheme), text: Binding(
                    get: { authSchemeInputs[provider.id] ?? (provider.openConfig?.accountBalance?.authScheme ?? "Bearer") },
                    set: { authSchemeInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField(viewModel.text(.userID), text: Binding(
                    get: { userIDInputs[provider.id] ?? (provider.openConfig?.accountBalance?.userID ?? "") },
                    set: { userIDInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.userIDHeader), text: Binding(
                    get: { userHeaderInputs[provider.id] ?? (provider.openConfig?.accountBalance?.userIDHeader ?? "New-Api-User") },
                    set: { userHeaderInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField(viewModel.text(.endpointPath), text: Binding(
                    get: { endpointPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.endpointPath ?? "/api/user/self") },
                    set: { endpointPathInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.unit), text: Binding(
                    get: { unitInputs[provider.id] ?? (provider.openConfig?.accountBalance?.unit ?? "quota") },
                    set: { unitInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField(viewModel.text(.remainingPath), text: Binding(
                    get: { remainingPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.remainingJSONPath ?? "data.quota") },
                    set: { remainingPathInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.usedPath), text: Binding(
                    get: { usedPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.usedJSONPath ?? "") },
                    set: { usedPathInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField(viewModel.text(.limitPath), text: Binding(
                    get: { limitPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.limitJSONPath ?? "") },
                    set: { limitPathInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(viewModel.text(.successPath), text: Binding(
                    get: { successPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.successJSONPath ?? "") },
                    set: { successPathInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button(viewModel.text(.saveConfig)) {
                    viewModel.updateOpenProviderSettings(
                        providerID: provider.id,
                        name: providerNameInputs[provider.id] ?? provider.name,
                        baseURL: baseURLInputs[provider.id] ?? (provider.baseURL ?? ""),
                        tokenUsageEnabled: tokenUsageEnabledInputs[provider.id] ?? (provider.openConfig?.tokenUsageEnabled ?? true),
                        accountEnabled: accountEnabledInputs[provider.id] ?? (provider.openConfig?.accountBalance?.enabled ?? false),
                        authHeader: authHeaderInputs[provider.id] ?? (provider.openConfig?.accountBalance?.authHeader ?? "Authorization"),
                        authScheme: authSchemeInputs[provider.id] ?? (provider.openConfig?.accountBalance?.authScheme ?? "Bearer"),
                        userID: userIDInputs[provider.id] ?? (provider.openConfig?.accountBalance?.userID ?? ""),
                        userIDHeader: userHeaderInputs[provider.id] ?? (provider.openConfig?.accountBalance?.userIDHeader ?? "New-Api-User"),
                        endpointPath: endpointPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.endpointPath ?? "/api/user/self"),
                        remainingJSONPath: remainingPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.remainingJSONPath ?? "data.quota"),
                        usedJSONPath: usedPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.usedJSONPath ?? ""),
                        limitJSONPath: limitPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.limitJSONPath ?? ""),
                        successJSONPath: successPathInputs[provider.id] ?? (provider.openConfig?.accountBalance?.successJSONPath ?? ""),
                        unit: unitInputs[provider.id] ?? (provider.openConfig?.accountBalance?.unit ?? "quota")
                    )
                }
                .buttonStyle(.borderedProminent)

                if provider.id != "open-ailinyu" {
                    Button(viewModel.text(.removeProvider), role: .destructive) {
                        viewModel.removeProvider(providerID: provider.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func kimiConfigSection(_ provider: ProviderDescriptor) -> some View {
        let authModeBinding = Binding(
            get: { kimiAuthModeInputs[provider.id] ?? (provider.kimiConfig?.authMode ?? .auto) },
            set: { kimiAuthModeInputs[provider.id] = $0 }
        )
        let autoCookieBinding = Binding(
            get: { kimiAutoCookieInputs[provider.id] ?? (provider.kimiConfig?.autoCookieEnabled ?? true) },
            set: { kimiAutoCookieInputs[provider.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 8) {
            TextField(viewModel.text(.providerName), text: Binding(
                get: { providerNameInputs[provider.id] ?? provider.name },
                set: { providerNameInputs[provider.id] = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Text(viewModel.text(.kimiAuthMode))
                    .foregroundStyle(.secondary)
                Picker("", selection: authModeBinding) {
                    Text(viewModel.text(.kimiAuthAuto)).tag(KimiAuthMode.auto)
                    Text(viewModel.text(.kimiAuthManual)).tag(KimiAuthMode.manual)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            labeledToggle(viewModel.text(.kimiAutoCookie), isOn: autoCookieBinding)

            HStack {
                SecureField(viewModel.text(.kimiManualToken), text: Binding(
                    get: { kimiManualTokenInputs[provider.id, default: ""] },
                    set: { kimiManualTokenInputs[provider.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button(viewModel.text(.saveToken)) {
                    let token = kimiManualTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { return }
                    _ = viewModel.saveKimiManualToken(token, providerID: provider.id)
                    kimiManualTokenInputs[provider.id] = ""
                    viewModel.restartPolling()
                }
                .buttonStyle(.bordered)

                Text(viewModel.hasToken(for: provider) ? viewModel.text(.tokenSaved) : viewModel.text(.noToken))
                    .font(.caption)
                    .foregroundStyle(viewModel.hasToken(for: provider) ? .green : .secondary)
            }

            HStack(spacing: 8) {
                Button(viewModel.text(.kimiAutoDetect)) {
                    Task {
                        let message = await viewModel.detectAndCacheKimiToken(providerID: provider.id)
                        kimiDetectResult[provider.id] = message
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(viewModel.text(.kimiOpenPrivacySettings)) {
                    openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
            }

            if let detectText = kimiDetectResult[provider.id], !detectText.isEmpty {
                Text(detectText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(viewModel.text(.kimiBrowserOrder)): Arc → Chrome → Safari → Edge → Brave → Chromium")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.text(.kimiFdaHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(viewModel.text(.saveConfig)) {
                viewModel.updateKimiProviderSettings(
                    providerID: provider.id,
                    name: providerNameInputs[provider.id] ?? provider.name,
                    authMode: kimiAuthModeInputs[provider.id] ?? (provider.kimiConfig?.authMode ?? .auto),
                    autoCookieEnabled: kimiAutoCookieInputs[provider.id] ?? (provider.kimiConfig?.autoCookieEnabled ?? true)
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func seedInputsFromConfig() {
        for provider in viewModel.config.providers where provider.type == .open || provider.type == .dragon {
            if providerNameInputs[provider.id] == nil {
                providerNameInputs[provider.id] = provider.name
            }
            if baseURLInputs[provider.id] == nil {
                baseURLInputs[provider.id] = provider.baseURL ?? ""
            }
            if tokenUsageEnabledInputs[provider.id] == nil {
                tokenUsageEnabledInputs[provider.id] = provider.openConfig?.tokenUsageEnabled ?? true
            }
            if accountEnabledInputs[provider.id] == nil {
                accountEnabledInputs[provider.id] = provider.openConfig?.accountBalance?.enabled ?? false
            }
            if authHeaderInputs[provider.id] == nil {
                authHeaderInputs[provider.id] = provider.openConfig?.accountBalance?.authHeader ?? "Authorization"
            }
            if authSchemeInputs[provider.id] == nil {
                authSchemeInputs[provider.id] = provider.openConfig?.accountBalance?.authScheme ?? "Bearer"
            }
            if userIDInputs[provider.id] == nil {
                userIDInputs[provider.id] = provider.openConfig?.accountBalance?.userID ?? ""
            }
            if userHeaderInputs[provider.id] == nil {
                userHeaderInputs[provider.id] = provider.openConfig?.accountBalance?.userIDHeader ?? "New-Api-User"
            }
            if endpointPathInputs[provider.id] == nil {
                endpointPathInputs[provider.id] = provider.openConfig?.accountBalance?.endpointPath ?? "/api/user/self"
            }
            if remainingPathInputs[provider.id] == nil {
                remainingPathInputs[provider.id] = provider.openConfig?.accountBalance?.remainingJSONPath ?? "data.quota"
            }
            if usedPathInputs[provider.id] == nil {
                usedPathInputs[provider.id] = provider.openConfig?.accountBalance?.usedJSONPath ?? ""
            }
            if limitPathInputs[provider.id] == nil {
                limitPathInputs[provider.id] = provider.openConfig?.accountBalance?.limitJSONPath ?? ""
            }
            if successPathInputs[provider.id] == nil {
                successPathInputs[provider.id] = provider.openConfig?.accountBalance?.successJSONPath ?? ""
            }
            if unitInputs[provider.id] == nil {
                unitInputs[provider.id] = provider.openConfig?.accountBalance?.unit ?? "quota"
            }
        }

        for provider in viewModel.config.providers where provider.type == .kimi {
            if providerNameInputs[provider.id] == nil {
                providerNameInputs[provider.id] = provider.name
            }
            if kimiAuthModeInputs[provider.id] == nil {
                kimiAuthModeInputs[provider.id] = provider.kimiConfig?.authMode ?? .auto
            }
            if kimiAutoCookieInputs[provider.id] == nil {
                kimiAutoCookieInputs[provider.id] = provider.kimiConfig?.autoCookieEnabled ?? true
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

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
