import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private let configStore = ConfigStore()
    private let keychain = KeychainService()
    private let codexSlotStore = CodexAccountSlotStore()
    private let codexProfileStore = CodexAccountProfileStore()
    private let codexDesktopAuthService = CodexDesktopAuthService()
    private let codexDesktopAppService = CodexDesktopAppService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let notifications = NotificationService()
    private let providerFactory: ProviderFactory

    private(set) var config: AppConfig
    private(set) var snapshots: [String: UsageSnapshot] = [:]
    private(set) var codexSlots: [CodexAccountSlot] = []
    private(set) var codexProfiles: [CodexAccountProfile] = []
    private(set) var codexSwitchFeedback: [CodexSlotID: CodexSwitchFeedback] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var lastUpdatedAt: Date?

    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var codexFeedbackTasks: [CodexSlotID: Task<Void, Never>] = [:]
    private var codexSwitchingSlots: Set<CodexSlotID> = []
    private var consecutiveFailures: [String: Int] = [:]
    private var activeAlerts: Set<String> = []
    private var hasStarted = false

    init() {
        self.config = (try? configStore.load()) ?? .default
        self.providerFactory = ProviderFactory(keychain: keychain)
        self.codexSlots = codexSlotStore.visibleSlots()
        self.codexProfiles = []
        let launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
            self.config.launchAtLoginEnabled = launchAtLoginEnabled
            try? configStore.save(self.config)
        }
        notifications.requestPermissionIfNeeded()
        syncCodexProfilesCurrentState()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        restartPolling()
    }

    func restartPolling() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()

        for provider in config.providers where provider.enabled {
            pollTasks[provider.id] = Task { [weak self] in
                await self?.pollLoop(providerID: provider.id)
            }
        }
    }

    func refreshNow() {
        let enabled = config.providers.filter(\.enabled)
        guard !enabled.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            for descriptor in enabled {
                await self.refreshProvider(descriptor, forceRefresh: true)
            }
        }
    }

    var language: AppLanguage {
        config.language
    }

    var simplifiedRelayConfig: Bool {
        config.simplifiedRelayConfig
    }

    var launchAtLoginEnabled: Bool {
        config.launchAtLoginEnabled
    }

    var statusBarProviderID: String? {
        config.statusBarProviderID
    }

    func setLanguage(_ language: AppLanguage) {
        guard config.language != language else { return }
        config.language = language
        try? configStore.save(config)
    }

    func setSimplifiedRelayConfig(_ enabled: Bool) {
        guard config.simplifiedRelayConfig != enabled else { return }
        config.simplifiedRelayConfig = enabled
        try? configStore.save(config)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard config.launchAtLoginEnabled != enabled else { return }
        do {
            try launchAtLoginService.setEnabled(enabled)
            config.launchAtLoginEnabled = enabled
            try? configStore.save(config)
        } catch {
            errors["launch-at-login"] = error.localizedDescription
        }
    }

    func isStatusBarProvider(providerID: String) -> Bool {
        config.statusBarProviderID == providerID
    }

    func setStatusBarProvider(providerID: String?) {
        let normalized: String?
        if let providerID,
           config.providers.contains(where: { $0.id == providerID }) {
            normalized = providerID
        } else {
            normalized = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        guard config.statusBarProviderID != normalized else { return }
        config.statusBarProviderID = normalized
        try? configStore.save(config)
    }

    func statusBarProvider() -> ProviderDescriptor? {
        if let id = config.statusBarProviderID,
           let selected = config.providers.first(where: { $0.id == id }) {
            return selected
        }
        return config.providers.first(where: { $0.id == AppConfig.defaultStatusBarProviderID(from: config.providers) })
    }

    func text(_ key: L10nKey) -> String {
        Localizer.text(key, language: config.language)
    }

    func aggregateStatusTitle(_ status: AggregateStatus) -> String {
        switch status {
        case .normal:
            return text(.statusNormal)
        case .alert:
            return text(.statusAlert)
        case .disconnected:
            return text(.statusDisconnected)
        }
    }

    func codexSlotViewModels() -> [CodexSlotViewModel] {
        syncCodexProfilesCurrentState()
        codexSlots = codexSlotStore.visibleSlots()
        let now = Date()
        return codexSlots
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
                return lhs.slotID < rhs.slotID
            }
            .map { slot in
                let profile = matchedCodexProfile(for: slot)
                let feedback = codexSwitchFeedback[slot.slotID]
                let displaySnapshot = CodexQuotaDisplayNormalizer.normalize(
                    snapshot: slot.lastSnapshot,
                    isActive: slot.isActive,
                    now: now
                )
                return CodexSlotViewModel(
                    slotID: slot.slotID,
                    title: codexMenuTitle(for: slot.slotID),
                    snapshot: displaySnapshot,
                    isActive: slot.isActive,
                    lastSeenAt: slot.lastSeenAt,
                    displayName: profile?.displayName ?? slot.displayName,
                    isSwitching: codexSwitchingSlots.contains(slot.slotID),
                    canSwitch: profile != nil && !(profile?.isCurrentSystemAccount ?? false),
                    isCurrentSystemAccount: profile?.isCurrentSystemAccount ?? false,
                    profileDisplayName: profile?.displayName,
                    switchMessage: feedback?.message,
                    switchMessageIsError: feedback?.isError ?? false
                )
            }
    }

    func codexProfilesForSettings() -> [CodexAccountProfile] {
        syncCodexProfilesCurrentState()
        return codexProfiles.sorted { $0.slotID < $1.slotID }
    }

    func nextCodexProfileSlotID() -> CodexSlotID {
        codexProfileStore.nextAvailableSlotID()
    }

    func codexSettingsTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    func saveCodexProfile(slotID: CodexSlotID, displayName: String, authJSON: String) -> String {
        do {
            _ = try codexProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                authJSON: authJSON,
                currentFingerprint: codexDesktopAuthService.currentCredentialFingerprint()
            )
            syncCodexProfilesCurrentState()
            return text(.codexProfileImported)
        } catch {
            return "\(text(.codexProfileImportFailed)): \(error.localizedDescription)"
        }
    }

    func removeCodexProfile(slotID: CodexSlotID) {
        syncCodexProfilesCurrentState()
        guard codexProfiles.first(where: { $0.slotID == slotID })?.isCurrentSystemAccount != true else {
            return
        }
        codexProfiles = codexProfileStore.removeProfile(slotID: slotID)
    }

    func switchCodexProfile(slotID: CodexSlotID) async {
        guard !codexSwitchingSlots.contains(slotID) else { return }
        syncCodexProfilesCurrentState()
        codexSwitchingSlots.insert(slotID)
        setCodexSwitchFeedback(nil, for: slotID)
        defer { codexSwitchingSlots.remove(slotID) }

        guard let profile = codexProfiles.first(where: { $0.slotID == slotID }) else {
            setCodexSwitchFeedback(
                CodexSwitchFeedback(message: text(.codexProfileMissing), isError: true),
                for: slotID
            )
            return
        }

        do {
            try codexDesktopAuthService.applyProfile(profile)
            _ = await codexDesktopAppService.restartIfRunning()
            syncCodexProfilesCurrentState()

            guard let descriptor = config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
                setCodexSwitchFeedback(
                    CodexSwitchFeedback(message: text(.codexSwitchAppliedNeedsRestart), isError: false),
                    for: slotID
                )
                return
            }

            let provider = providerFactory.makeProvider(for: descriptor)
            do {
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = markCodexSnapshotActive(fetched, preferredSlotID: slotID)
                codexSlots = codexSlotStore.upsertActive(snapshot: snapshot)
                snapshots[descriptor.id] = snapshot
                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()
                setCodexSwitchFeedback(
                    CodexSwitchFeedback(message: text(.codexSwitchSuccess), isError: false),
                    for: slotID
                )
                notifications.notify(
                    title: "Codex",
                    body: text(.codexSwitchSuccess),
                    identifier: "codex-switch-\(slotID.rawValue.lowercased())"
                )
            } catch {
                errors[descriptor.id] = error.localizedDescription
                setCodexSwitchFeedback(
                    CodexSwitchFeedback(
                        message: "\(text(.codexSwitchNeedsVerification)): \(error.localizedDescription)",
                        isError: true
                    ),
                    for: slotID
                )
                notifications.notify(
                    title: "Codex",
                    body: "\(text(.codexSwitchNeedsVerification)): \(error.localizedDescription)",
                    identifier: "codex-switch-\(slotID.rawValue.lowercased())"
                )
            }
        } catch {
            setCodexSwitchFeedback(
                CodexSwitchFeedback(
                    message: "\(text(.codexSwitchFailed)): \(error.localizedDescription)",
                    isError: true
                ),
                for: slotID
            )
        }
    }

    func setEnabled(_ enabled: Bool, providerID: String) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
        if config.providers[idx].enabled == enabled { return }
        config.providers[idx].enabled = enabled

        // Keep enabled providers grouped at the top of the same family list.
        if enabled {
            let provider = config.providers.remove(at: idx)
            let family = provider.family
            let familyIndices = config.providers.indices.filter { config.providers[$0].family == family }

            let insertAt: Int
            if familyIndices.isEmpty {
                insertAt = config.providers.count
            } else if let firstDisabled = familyIndices.first(where: { !config.providers[$0].enabled }) {
                insertAt = firstDisabled
            } else if let lastFamily = familyIndices.last {
                insertAt = lastFamily + 1
            } else {
                insertAt = config.providers.count
            }
            config.providers.insert(provider, at: min(max(0, insertAt), config.providers.count))
        }

        if !enabled, config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        persistAndRestart()
    }

    func reorderEnabledProviders(
        family: ProviderFamily,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let enabledIndices = config.providers.indices.filter {
            config.providers[$0].family == family && config.providers[$0].enabled
        }
        guard enabledIndices.count > 1 else { return }

        var enabledProviders = enabledIndices.map { config.providers[$0] }
        moveArray(&enabledProviders, fromOffsets: fromOffsets, toOffset: toOffset)

        for (position, index) in enabledIndices.enumerated() {
            config.providers[index] = enabledProviders[position]
        }

        persistAndRestart()
    }

    private func moveArray<T>(_ array: inout [T], fromOffsets: IndexSet, toOffset: Int) {
        let moving = fromOffsets.sorted().map { array[$0] }
        for index in fromOffsets.sorted(by: >) {
            array.remove(at: index)
        }
        let insertion = min(max(0, toOffset), array.count)
        array.insert(contentsOf: moving, at: insertion)
    }

    func setLowThreshold(_ value: Double, providerID: String) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
        config.providers[idx].threshold.lowRemaining = value
        persistAndRestart()
    }

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return false
        }
        return keychain.readToken(service: service, account: account)?.isEmpty == false
    }

    func hasToken(auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return keychain.readToken(service: service, account: account)?.isEmpty == false
    }

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return false
        }
        let normalized = normalizedCredential(token, kind: descriptor.auth.kind)
        guard !normalized.isEmpty else { return false }
        return keychain.saveToken(normalized, service: service, account: account)
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        let normalized = normalizedCredential(token, kind: auth.kind)
        guard !normalized.isEmpty else { return false }
        return keychain.saveToken(normalized, service: service, account: account)
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return false
        }
        return keychain.readToken(service: KeychainService.defaultServiceName, account: account)?.isEmpty == false
    }

    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }),
              provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return false
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return keychain.saveToken(trimmed, service: KeychainService.defaultServiceName, account: account)
    }

    func addOpenRelay(name: String, baseURL: String, preferredAdapterID: String? = nil) {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID
        )
        config.providers.append(provider)
        if config.statusBarProviderID == nil {
            config.statusBarProviderID = provider.id
        }
        persistAndRestart()
    }

    func removeProvider(providerID: String) {
        config.providers.removeAll { $0.id == providerID }
        if config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        snapshots.removeValue(forKey: providerID)
        errors.removeValue(forKey: providerID)
        consecutiveFailures.removeValue(forKey: providerID)
        activeAlerts.remove("low:\(providerID)")
        activeAlerts.remove("fail:\(providerID)")
        activeAlerts.remove("auth:\(providerID)")
        persistAndRestart()
    }

    func updateOpenProviderSettings(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              let updated = relayDescriptorForPreview(
                providerID: providerID,
                name: name,
                baseURL: baseURL,
                preferredAdapterID: preferredAdapterID,
                balanceCredentialMode: balanceCredentialMode,
                tokenUsageEnabled: tokenUsageEnabled,
                accountEnabled: accountEnabled,
                authHeader: authHeader,
                authScheme: authScheme,
                userID: userID,
                userIDHeader: userIDHeader,
                endpointPath: endpointPath,
                remainingJSONPath: remainingJSONPath,
                usedJSONPath: usedJSONPath,
                limitJSONPath: limitJSONPath,
                successJSONPath: successJSONPath,
                unit: unit
              ) else {
            return
        }
        config.providers[idx] = updated
        persistAndRestart()
    }

    func relayDescriptorForPreview(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String
    ) -> ProviderDescriptor? {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].isRelay else {
            return nil
        }

        var provider = config.providers[idx]
        provider.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(baseURL.isEmpty ? (provider.baseURL ?? "") : baseURL)
        provider.baseURL = normalizedBaseURL

        let normalizedProvider = provider.normalized()
        let currentRelayView = normalizedProvider.relayViewConfig?.accountBalance
        let matchedManifest = RelayAdapterRegistry.shared.manifest(
            for: normalizedBaseURL,
            preferredID: trimmedOrNil(preferredAdapterID ?? "")
        )
        var relayConfig = normalizedProvider.relayConfig ?? ProviderDescriptor.makeOpenRelay(
            name: provider.name,
            baseURL: normalizedBaseURL,
            preferredAdapterID: trimmedOrNil(preferredAdapterID ?? "")
        ).relayConfig!
        relayConfig.baseURL = normalizedBaseURL
        relayConfig.adapterID = matchedManifest.id
        relayConfig.tokenChannelEnabled = tokenUsageEnabled
        relayConfig.balanceChannelEnabled = accountEnabled
        relayConfig.balanceCredentialMode = balanceCredentialMode

        let templateRequest = matchedManifest.balanceRequest
        let templateExtract = matchedManifest.extract
        let useTemplateDefaults = config.simplifiedRelayConfig

        let resolvedAuthHeader = useTemplateDefaults
            ? (templateRequest.authHeader ?? "Authorization")
            : nonEmptyOrDefault(authHeader, fallback: "Authorization")
        let resolvedAuthScheme = useTemplateDefaults
            ? (templateRequest.authScheme ?? "Bearer")
            : authScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUserID = useTemplateDefaults
            ? (trimmedOrNil(userID) ?? templateRequest.userID)
            : trimmedOrNil(userID)
        let resolvedUserIDHeader = useTemplateDefaults
            ? (templateRequest.userIDHeader ?? "New-Api-User")
            : nonEmptyOrDefault(userIDHeader, fallback: "New-Api-User")
        let resolvedRequestMethod = useTemplateDefaults
            ? templateRequest.method
            : (currentRelayView?.requestMethod ?? relayConfig.manualOverrides?.requestMethod)
        let resolvedRequestBody = useTemplateDefaults
            ? templateRequest.bodyJSON
            : (currentRelayView?.requestBodyJSON ?? relayConfig.manualOverrides?.requestBodyJSON)
        let resolvedEndpointPath = useTemplateDefaults
            ? templateRequest.path
            : nonEmptyOrDefault(endpointPath, fallback: "/api/user/self")
        let resolvedRemaining = useTemplateDefaults
            ? templateExtract.remaining
            : nonEmptyOrDefault(remainingJSONPath, fallback: "data.quota")
        let resolvedUsed = useTemplateDefaults
            ? templateExtract.used
            : trimmedOrNil(usedJSONPath)
        let resolvedLimit = useTemplateDefaults
            ? templateExtract.limit
            : trimmedOrNil(limitJSONPath)
        let resolvedSuccess = useTemplateDefaults
            ? templateExtract.success
            : trimmedOrNil(successJSONPath)
        let resolvedUnit = useTemplateDefaults
            ? (templateExtract.unit ?? "quota")
            : nonEmptyOrDefault(unit, fallback: "quota")

        relayConfig.manualOverrides = RelayManualOverride(
            authHeader: resolvedAuthHeader,
            authScheme: resolvedAuthScheme,
            userID: resolvedUserID,
            userIDHeader: resolvedUserIDHeader,
            requestMethod: resolvedRequestMethod,
            requestBodyJSON: resolvedRequestBody,
            endpointPath: resolvedEndpointPath,
            remainingExpression: resolvedRemaining,
            usedExpression: resolvedUsed,
            limitExpression: resolvedLimit,
            successExpression: resolvedSuccess,
            unitExpression: resolvedUnit,
            accountLabelExpression: relayConfig.manualOverrides?.accountLabelExpression,
            staticHeaders: useTemplateDefaults
                ? templateRequest.headers
                : relayConfig.manualOverrides?.staticHeaders
        )
        provider.relayConfig = relayConfig
        provider.openConfig = nil
        return provider.normalized()
    }

    func relayAdapterName(for provider: ProviderDescriptor) -> String? {
        provider.relayManifest?.displayName
    }

    func relayAuthSource(for providerID: String) -> String? {
        snapshots[providerID]?.authSourceLabel
            ?? snapshots[providerID]?.rawMeta["account.authSource"]
            ?? snapshots[providerID]?.rawMeta["token.authSource"]
    }

    func relayFetchHealth(for providerID: String) -> FetchHealth? {
        snapshots[providerID]?.fetchHealth
    }

    func relayValueFreshness(for providerID: String) -> ValueFreshness? {
        snapshots[providerID]?.valueFreshness
    }

    func testRelayConnection(providerID: String) async -> RelayDiagnosticResult {
        guard let descriptor = descriptor(for: providerID), descriptor.isRelay else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: "unknown",
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }

        return await testRelayConnection(descriptor: descriptor)
    }

    func testRelayConnection(descriptor: ProviderDescriptor) async -> RelayDiagnosticResult {
        let provider = providerFactory.makeProvider(for: descriptor)
        do {
            let snapshot = try await provider.fetch(forceRefresh: true)
            snapshots[descriptor.id] = snapshot
            errors.removeValue(forKey: descriptor.id)
            lastUpdatedAt = Date()
            return RelayDiagnosticResult(
                success: true,
                fetchHealth: snapshot.fetchHealth,
                resolvedAdapterID: snapshot.rawMeta["relay.adapterID"] ?? descriptor.relayManifest?.id ?? "generic-newapi",
                resolvedAuthSource: snapshot.authSourceLabel,
                message: text(.connectionSuccess),
                snapshotPreview: RelayDiagnosticSnapshotPreview(
                    remaining: snapshot.remaining,
                    used: snapshot.used,
                    limit: snapshot.limit,
                    unit: snapshot.unit
                )
            )
        } catch {
            errors[descriptor.id] = error.localizedDescription
            let health = classifyFetchHealth(error)
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: health,
                resolvedAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID ?? "generic-newapi",
                resolvedAuthSource: nil,
                message: "\(text(.connectionFailed)): \(error.localizedDescription)",
                snapshotPreview: nil
            )
        }
    }

    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .official else {
            return
        }

        var provider = config.providers[idx]
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        official.sourceMode = sourceMode
        official.webMode = webMode
        provider.officialConfig = official
        config.providers[idx] = provider
        persistAndRestart()
    }

    var aggregateStatus: AggregateStatus {
        let enabled = config.providers.filter(\.enabled)
        if enabled.isEmpty {
            return .disconnected
        }

        let allErrored = enabled.allSatisfy { errors[$0.id] != nil }
        if allErrored {
            return .disconnected
        }

        if !activeAlerts.isEmpty || snapshots.values.contains(where: { $0.status == .warning || $0.status == .error }) {
            return .alert
        }

        return .normal
    }

    private func persistAndRestart() {
        try? configStore.save(config)
        restartPolling()
    }

    private func normalizedCredential(_ token: String, kind: AuthKind) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .bearer:
            return KimiProvider.normalizeToken(trimmed)
        case .none, .localCodex:
            return trimmed
        }
    }

    private func descriptor(for id: String) -> ProviderDescriptor? {
        config.providers.first(where: { $0.id == id })
    }

    private func pollLoop(providerID: String) async {
        while !Task.isCancelled {
            guard let descriptor = descriptor(for: providerID), descriptor.enabled else {
                return
            }

            await refreshProvider(descriptor, forceRefresh: false)

            let failureCount = consecutiveFailures[providerID, default: 0]
            let delay = BackoffPolicy.delaySeconds(baseInterval: descriptor.pollIntervalSec, consecutiveFailures: failureCount)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        if descriptor.type == .codex, descriptor.family == .official {
            syncCodexProfilesCurrentState()
        }
        let provider = providerFactory.makeProvider(for: descriptor)

        do {
            let fetched = try await provider.fetch(forceRefresh: forceRefresh)
            let snapshot: UsageSnapshot
            if descriptor.type == .codex, descriptor.family == .official {
                snapshot = markCodexSnapshotActive(fetched)
                codexSlots = codexSlotStore.upsertActive(snapshot: snapshot)
            } else {
                snapshot = fetched
            }
            snapshots[descriptor.id] = snapshot
            errors.removeValue(forKey: descriptor.id)
            consecutiveFailures[descriptor.id] = 0
            lastUpdatedAt = Date()

            handleLowRemainingAlerts(for: descriptor, snapshot: snapshot)

            activeAlerts.remove("fail:\(descriptor.id)")
            activeAlerts.remove("auth:\(descriptor.id)")
        } catch {
            if isCancellationError(error) || Task.isCancelled {
                return
            }

            if isRateLimitedError(error),
               var previous = snapshots[descriptor.id] {
                previous.status = .warning
                previous.fetchHealth = .rateLimited
                previous.valueFreshness = .cachedFallback
                previous.updatedAt = Date()
                previous.diagnosticCode = "rate-limited"
                previous.note = "\(previous.note) | rate limited, showing cached value"
                snapshots[descriptor.id] = previous
                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()
                return
            }

            errors[descriptor.id] = error.localizedDescription
            consecutiveFailures[descriptor.id, default: 0] += 1
            let health = classifyFetchHealth(error)
            if descriptor.isRelay {
                if var previous = snapshots[descriptor.id] {
                    previous.fetchHealth = health
                    previous.valueFreshness = .cachedFallback
                    previous.updatedAt = Date()
                    previous.diagnosticCode = diagnosticCode(for: health)
                    previous.note = "\(previous.note) | \(error.localizedDescription)"
                    snapshots[descriptor.id] = previous
                } else {
                    snapshots[descriptor.id] = UsageSnapshot(
                        source: descriptor.id,
                        status: .error,
                        fetchHealth: health,
                        valueFreshness: .empty,
                        remaining: nil,
                        used: nil,
                        limit: nil,
                        unit: descriptor.relayViewConfig?.accountBalance?.unit ?? "quota",
                        updatedAt: Date(),
                        note: error.localizedDescription,
                        sourceLabel: "Third-Party",
                        accountLabel: nil,
                        authSourceLabel: nil,
                        diagnosticCode: diagnosticCode(for: health)
                    )
                }
            }

            let failureCount = consecutiveFailures[descriptor.id, default: 0]
            if AlertEngine.shouldAlertFailures(consecutiveFailures: failureCount, rule: descriptor.threshold) {
                let key = "fail:\(descriptor.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.providerUnreachable),
                        body: Localizer.providerFailedBody(
                            providerName: descriptor.name,
                            failures: failureCount,
                            language: config.language
                        ),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            }

            if descriptor.threshold.notifyOnAuthError,
               AlertEngine.isAuthError(error) {
                let key = "auth:\(descriptor.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.authError),
                        body: Localizer.authErrorBody(providerName: descriptor.name, language: config.language),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            }
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        return false
    }

    private func isRateLimitedError(_ error: Error) -> Bool {
        if let providerError = error as? ProviderError {
            if case .rateLimited = providerError {
                return true
            }
        }

        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        return description.contains("rate limited") || description.contains("429")
    }

    private func classifyFetchHealth(_ error: Error) -> FetchHealth {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingCredential, .unauthorized, .unauthorizedDetail:
                return .authExpired
            case .rateLimited:
                return .rateLimited
            case .invalidResponse:
                return .endpointMisconfigured
            case .timeout:
                return .unreachable
            case .commandFailed, .unavailable:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorUserAuthenticationRequired,
                 NSURLErrorNoPermissionsToReadFile:
                return .authExpired
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return .unreachable
            default:
                break
            }
        }

        let description = nsError.localizedDescription.lowercased()
        if description.contains("unauthorized") || description.contains("expired") || description.contains("forbidden") {
            return .authExpired
        }
        if description.contains("rate limited") || description.contains("429") {
            return .rateLimited
        }
        if description.contains("invalid") || description.contains("missing") || description.contains("path") || description.contains("base url") {
            return .endpointMisconfigured
        }
        return .unreachable
    }

    private func diagnosticCode(for health: FetchHealth) -> String {
        switch health {
        case .ok:
            return "ok"
        case .authExpired:
            return "auth-expired"
        case .rateLimited:
            return "rate-limited"
        case .endpointMisconfigured:
            return "endpoint-misconfigured"
        case .unreachable:
            return "unreachable"
        }
    }

    private func handleLowRemainingAlerts(for descriptor: ProviderDescriptor, snapshot: UsageSnapshot) {
        let genericKey = "low:\(descriptor.id)"
        let lowWindows = AlertEngine.lowQuotaWindows(snapshot: snapshot, rule: descriptor.threshold)

        if !lowWindows.isEmpty {
            activeAlerts.remove(genericKey)

            let activeWindowKeys = Set(lowWindows.map { "low:\(descriptor.id):\($0.id)" })
            for existingKey in activeAlerts.filter({ $0.hasPrefix("low:\(descriptor.id):") && !activeWindowKeys.contains($0) }) {
                activeAlerts.remove(existingKey)
            }

            for window in lowWindows {
                let key = "low:\(descriptor.id):\(window.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.lowBalanceWarning),
                        body: Localizer.lowQuotaWindowBody(
                            providerName: descriptor.name,
                            windowTitle: window.title,
                            remaining: String(Int(window.remainingPercent.rounded())),
                            language: config.language
                        ),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            }
            return
        }

        for existingKey in activeAlerts.filter({ $0.hasPrefix("low:\(descriptor.id):") }) {
            activeAlerts.remove(existingKey)
        }

        if AlertEngine.shouldAlertLowRemaining(snapshot: snapshot, rule: descriptor.threshold) {
            if !activeAlerts.contains(genericKey) {
                notifications.notify(
                    title: text(.lowBalanceWarning),
                    body: Localizer.lowBalanceBody(
                        providerName: descriptor.name,
                        remaining: format(snapshot.remaining),
                        unit: snapshot.unit,
                        language: config.language
                    ),
                    identifier: genericKey
                )
                activeAlerts.insert(genericKey)
            }
        } else {
            activeAlerts.remove(genericKey)
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return text(.unlimited) }
        return String(format: "%.2f", value)
    }

    private func normalizeBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return "https://open.ailinyu.de"
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmptyOrDefault(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func markCodexSnapshotActive(_ snapshot: UsageSnapshot, preferredSlotID: CodexSlotID? = nil) -> UsageSnapshot {
        var copy = snapshot
        let resolvedSlotID = preferredSlotID ?? matchedCodexProfile(for: copy)?.slotID
        let accountKey = CodexAccountSlotStore.accountKey(from: copy)
        let label = CodexAccountSlotStore.accountLabel(from: copy)
        if let resolvedSlotID {
            copy.rawMeta["codex.slotID"] = resolvedSlotID.rawValue
        }
        copy.rawMeta["codex.accountKey"] = accountKey
        copy.rawMeta["codex.accountLabel"] = label
        copy.rawMeta["codex.lastSeenAt"] = ISO8601DateFormatter().string(from: Date())
        copy.rawMeta["codex.isActive"] = "true"
        if copy.accountLabel == nil || copy.accountLabel?.isEmpty == true {
            copy.accountLabel = label == "Unknown" ? nil : label
        }
        return copy
    }

    private func syncCodexProfilesCurrentState() {
        codexProfiles = codexProfileStore.captureCurrentAuthIfNeeded(
            authJSON: codexDesktopAuthService.currentAuthJSON()
        )
    }

    private func codexMenuTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    private func setCodexSwitchFeedback(_ feedback: CodexSwitchFeedback?, for slotID: CodexSlotID) {
        codexFeedbackTasks[slotID]?.cancel()
        codexFeedbackTasks.removeValue(forKey: slotID)

        guard let feedback else {
            codexSwitchFeedback.removeValue(forKey: slotID)
            return
        }

        codexSwitchFeedback[slotID] = feedback
        codexFeedbackTasks[slotID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.codexSwitchFeedback[slotID] == feedback {
                self.codexSwitchFeedback.removeValue(forKey: slotID)
            }
            self.codexFeedbackTasks.removeValue(forKey: slotID)
        }
    }

    private func matchedCodexProfile(for slot: CodexAccountSlot) -> CodexAccountProfile? {
        matchedCodexProfile(for: slot.lastSnapshot) ?? codexProfiles.first(where: { $0.slotID == slot.slotID })
    }

    private func matchedCodexProfile(for snapshot: UsageSnapshot) -> CodexAccountProfile? {
        syncCodexProfilesCurrentState()
        let accountID = snapshot.rawMeta["codex.accountId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fingerprint = snapshot.rawMeta["codex.credentialFingerprint"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let explicitSlotID = CodexAccountSlotStore.explicitSlotID(from: snapshot),
           let matched = codexProfiles.first(where: { $0.slotID == explicitSlotID }) {
            return matched
        }
        if let accountID, !accountID.isEmpty,
           let matched = codexProfiles.first(where: { $0.accountId?.caseInsensitiveCompare(accountID) == .orderedSame }) {
            return matched
        }
        if let fingerprint, !fingerprint.isEmpty,
           let matched = codexProfiles.first(where: { $0.credentialFingerprint?.lowercased() == fingerprint }) {
            return matched
        }
        if let email, !email.isEmpty,
           let matched = codexProfiles.first(where: { $0.accountEmail?.lowercased() == email }) {
            return matched
        }
        return nil
    }
}

enum AggregateStatus {
    case normal
    case alert
    case disconnected

    var iconName: String {
        switch self {
        case .normal:
            return "checkmark.circle.fill"
        case .alert:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "xmark.octagon.fill"
        }
    }
}
