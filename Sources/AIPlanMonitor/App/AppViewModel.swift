import AppKit
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppViewModel {
    private let configStore = ConfigStore()
    private let keychain = KeychainService()
    private let appUpdateService = AppUpdateService()
    private let codexSlotStore = CodexAccountSlotStore()
    private let codexProfileStore = CodexAccountProfileStore()
    private let codexProfileSnapshotService = CodexProfileSnapshotService()
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
    private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var secureStorageReady = false
    private(set) var fullDiskAccessGranted = false
    private(set) var fullDiskAccessRelevant = false
    private(set) var fullDiskAccessRequested = false
    private(set) var currentAppVersion: String
    private(set) var availableUpdate: AppUpdateInfo?
    private(set) var lastUpdateCheckAt: Date?
    private(set) var updateCheckInFlight = false
    private(set) var lastCheckedLatestVersion: String?
    private(set) var updateCheckErrorMessage: String?

    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var codexFeedbackTasks: [CodexSlotID: Task<Void, Never>] = [:]
    private var codexSwitchingSlots: Set<CodexSlotID> = []
    private var codexPrefetchInFlightSlots: Set<CodexSlotID> = []
    private var codexPrefetchAttemptedIdentity: [CodexSlotID: String] = [:]
    private var consecutiveFailures: [String: Int] = [:]
    private var activeAlerts: Set<String> = []
    private var hasStarted = false
    private var lastPermissionStatusRefreshAt = Date.distantPast
    private var notificationPermissionPollingTask: Task<Void, Never>?

    init() {
        var loadedConfig = (try? configStore.load()) ?? .default
        if loadedConfig.simplifiedRelayConfig == false {
            loadedConfig.simplifiedRelayConfig = true
            try? configStore.save(loadedConfig)
        }
        self.config = loadedConfig
        self.currentAppVersion = Self.detectCurrentAppVersion()
        self.providerFactory = ProviderFactory(keychain: keychain)
        self.codexSlots = codexSlotStore.visibleSlots()
        self.codexProfiles = []
        let launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
            self.config.launchAtLoginEnabled = launchAtLoginEnabled
            try? configStore.save(self.config)
        }
        syncCodexProfilesCurrentState()
        refreshPermissionStatuses(force: true)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissionStatuses(force: true)
        restartPolling()
        checkForAppUpdate(force: true)
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

    func checkForAppUpdate(force: Bool = false) {
        if updateCheckInFlight { return }
        if !force,
           let last = lastUpdateCheckAt,
           Date().timeIntervalSince(last) < 6 * 60 * 60 {
            return
        }

        updateCheckInFlight = true
        updateCheckErrorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.updateCheckInFlight = false
                self.lastUpdateCheckAt = Date()
            }

            do {
                let latest = try await self.appUpdateService.fetchLatestRelease()
                self.lastCheckedLatestVersion = latest.latestVersion
                self.updateCheckErrorMessage = nil
                if Self.isVersion(latest.latestVersion, newerThan: self.currentAppVersion) {
                    self.availableUpdate = latest
                } else {
                    self.availableUpdate = nil
                }
            } catch {
                self.updateCheckErrorMessage = error.localizedDescription
            }
        }
    }

    func openRepositoryPage() {
        NSWorkspace.shared.open(AppUpdateService.repositoryURL)
    }

    func openLatestReleaseDownload() {
        if let url = availableUpdate?.downloadURL {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = availableUpdate?.releaseURL {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(AppUpdateService.releasesURL)
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

    var showOfficialAccountEmailInMenuBar: Bool {
        config.showOfficialAccountEmailInMenuBar
    }

    var hasNotificationPermission: Bool {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var shouldShowPermissionGuide: Bool {
        let hasEnabledProviders = config.providers.contains(where: \.enabled)
        guard !hasEnabledProviders else { return false }
        if !hasNotificationPermission { return true }
        if !secureStorageReady { return true }
        if (fullDiskAccessRelevant || fullDiskAccessRequested) && !fullDiskAccessGranted { return true }
        return true
    }

    var canRunLocalDiscoveryFromOnboarding: Bool {
        guard secureStorageReady else { return false }
        if fullDiskAccessRelevant || fullDiskAccessRequested {
            return fullDiskAccessGranted
        }
        return true
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

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        guard config.showOfficialAccountEmailInMenuBar != enabled else { return }
        config.showOfficialAccountEmailInMenuBar = enabled
        try? configStore.save(config)
    }

    func statusBarProvider() -> ProviderDescriptor? {
        if let id = config.statusBarProviderID,
           let selected = config.providers.first(where: { $0.id == id && $0.enabled }) {
            return selected
        }
        guard let fallbackID = AppConfig.defaultStatusBarProviderID(from: config.providers) else {
            return nil
        }
        return config.providers.first(where: { $0.id == fallbackID })
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
        triggerCodexProfileSnapshotPrefetchIfNeeded()
        let now = Date()
        return mergedCodexSlotsForMenu()
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
        codexProfiles = codexProfileStore.removeProfile(slotID: slotID)
        codexPrefetchAttemptedIdentity.removeValue(forKey: slotID)
        codexPrefetchInFlightSlots.remove(slotID)
    }

    func requestNotificationPermission() {
        notifications.requestPermissionIfNeeded()
        notificationPermissionPollingTask?.cancel()
        notificationPermissionPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                if Task.isCancelled { break }
                let status = await self.fetchNotificationAuthorizationStatus()
                self.notificationAuthorizationStatus = status
                if status != .notDetermined {
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.refreshPermissionStatuses(force: true)
        }
    }

    @discardableResult
    func prepareSecureStorageAccess() -> Bool {
        let ok = keychain.prepareSecureStoreAccess()
        refreshPermissionStatuses(force: true)
        return ok
    }

    func openFullDiskAccessSettings() {
        fullDiskAccessRequested = true
        openSystemSettingsApplication()
    }

    private func openSystemSettingsApplication() {
        let bundleIDs = [
            "com.apple.systemsettings",
            "com.apple.systempreferences"
        ]

        for bundleID in bundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
            return
        }
    }

    func refreshPermissionStatusesIfNeeded(referenceDate: Date = Date()) {
        guard referenceDate.timeIntervalSince(lastPermissionStatusRefreshAt) >= 5 else { return }
        refreshPermissionStatuses(force: true)
    }

    func refreshPermissionStatusesNow() {
        refreshPermissionStatuses(force: true)
    }

    func resetLocalAppData() {
        notificationPermissionPollingTask?.cancel()
        notificationPermissionPollingTask = nil
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()
        codexFeedbackTasks.values.forEach { $0.cancel() }
        codexFeedbackTasks.removeAll()
        codexSwitchingSlots.removeAll()
        codexPrefetchInFlightSlots.removeAll()
        codexPrefetchAttemptedIdentity.removeAll()
        codexSwitchFeedback.removeAll()
        snapshots.removeAll()
        errors.removeAll()
        consecutiveFailures.removeAll()
        activeAlerts.removeAll()
        lastUpdatedAt = nil

        launchAtLoginService.reset()
        keychain.resetAllStoredCredentials()
        codexProfileStore.reset()
        codexSlotStore.reset()
        try? configStore.reset()

        config = .default
        codexSlots = []
        codexProfiles = []
        notificationAuthorizationStatus = .notDetermined
        secureStorageReady = false
        fullDiskAccessGranted = false
        fullDiskAccessRelevant = false
        fullDiskAccessRequested = false
        lastPermissionStatusRefreshAt = .distantPast
        hasStarted = false
        start()
        refreshPermissionStatuses(force: true)
    }

    func discoverLocalProviders() async -> String {
        let candidates = config.providers.filter { $0.family == .official }
        guard !candidates.isEmpty else {
            return text(.localDiscoveryNothingFound)
        }

        var discoveredIDs: [String] = []
        var discoveredNames: [String] = []

        for descriptor in candidates {
            let provider = providerFactory.makeProvider(for: descriptor)
            do {
                let fetched = try await provider.fetch(forceRefresh: true)
                if descriptor.type == .codex {
                    let snapshot = markCodexSnapshotActive(fetched)
                    codexSlots = codexSlotStore.upsertActive(snapshot: snapshot)
                    snapshots[descriptor.id] = snapshot
                } else {
                    snapshots[descriptor.id] = fetched
                }

                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()

                if let index = config.providers.firstIndex(where: { $0.id == descriptor.id }) {
                    config.providers[index].enabled = true
                }
                discoveredIDs.append(descriptor.id)
                discoveredNames.append(displayNameForDiscovery(descriptor))
            } catch {
                continue
            }
        }

        let currentStatusProviderIsEnabled = config.statusBarProviderID.flatMap { selectedID in
            config.providers.first(where: { $0.id == selectedID && $0.enabled })
        } != nil
        if !currentStatusProviderIsEnabled {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }

        if discoveredIDs.isEmpty {
            return text(.localDiscoveryNothingFound)
        }

        try? configStore.save(config)
        restartPolling()
        return Localizer.localDiscoveryFoundBody(providerNames: discoveredNames, language: config.language)
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

    private func refreshPermissionStatuses(force: Bool) {
        if !force, Date().timeIntervalSince(lastPermissionStatusRefreshAt) < 5 {
            return
        }
        lastPermissionStatusRefreshAt = Date()
        secureStorageReady = keychain.isSecureStoreReady()

        let fullDiskProbe = probeFullDiskAccess()
        fullDiskAccessGranted = fullDiskProbe.isGranted
        fullDiskAccessRelevant = fullDiskProbe.isRelevant

        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.notifications.authorizationStatus()
            self.notificationAuthorizationStatus = status
        }
    }

    private func fetchNotificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notifications.authorizationStatus()
    }

    private func probeFullDiskAccess() -> (isGranted: Bool, isRelevant: Bool) {
        let home = NSHomeDirectory()
        let fileManager = FileManager.default
        let fileCandidates = [
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.sqlite",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies/Cookies.sqlite",
            "\(home)/Library/Application Support/Google/Chrome/Default/Network/Cookies",
            "\(home)/Library/Application Support/Arc/User Data/Default/Network/Cookies",
            "\(home)/Library/Application Support/Microsoft Edge/Default/Network/Cookies",
            "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Network/Cookies",
            "\(home)/Library/Application Support/Chromium/Default/Network/Cookies"
        ]
        let directoryCandidates = [
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Arc/User Data",
            "\(home)/Library/Application Support/Microsoft Edge",
            "\(home)/Library/Application Support/BraveSoftware/Brave-Browser",
            "\(home)/Library/Application Support/Chromium",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies"
        ]

        let existingFiles = fileCandidates.filter { fileManager.fileExists(atPath: $0) }
        let existingDirectories = directoryCandidates.filter { fileManager.fileExists(atPath: $0) }
        guard !existingFiles.isEmpty || !existingDirectories.isEmpty else {
            return (false, false)
        }

        for path in existingFiles {
            if fileManager.isReadableFile(atPath: path),
               let handle = FileHandle(forReadingAtPath: path) {
                do {
                    _ = try handle.read(upToCount: 1)
                } catch {
                    // Keep probing additional protected files.
                }
                try? handle.close()
                return (true, true)
            }
        }

        for path in existingDirectories {
            if (try? fileManager.contentsOfDirectory(atPath: path)) != nil {
                return (true, true)
            }
        }
        return (false, true)
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
            let enabledFamilyIndices = familyIndices.filter { config.providers[$0].enabled }

            let insertAt: Int
            if let lastEnabled = enabledFamilyIndices.last {
                // Newly enabled providers always append after already-enabled ones.
                insertAt = lastEnabled + 1
            } else if let firstFamily = familyIndices.first {
                // No enabled providers yet in this family: insert at family head.
                insertAt = firstFamily
            } else if familyIndices.isEmpty {
                insertAt = config.providers.count
            } else {
                insertAt = config.providers.count
            }
            config.providers.insert(provider, at: min(max(0, insertAt), config.providers.count))
        }

        if !enabled, config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        } else if enabled, config.statusBarProviderID == nil {
            config.statusBarProviderID = providerID
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
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .official else {
            return
        }

        var provider = config.providers[idx]
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        official.sourceMode = sourceMode
        official.webMode = webMode
        if let quotaDisplayMode {
            official.quotaDisplayMode = quotaDisplayMode
        }
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

    private func displayNameForDiscovery(_ descriptor: ProviderDescriptor) -> String {
        switch descriptor.type {
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
            return descriptor.name
        }
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
        let displaysUsedQuota = descriptor.displaysUsedQuota
        let lowWindows = AlertEngine.lowQuotaWindows(
            snapshot: snapshot,
            rule: descriptor.threshold,
            displaysUsedQuota: displaysUsedQuota
        )

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
                            remaining: String(
                                Int(
                                    (displaysUsedQuota ? window.usedPercent : window.remainingPercent)
                                        .rounded()
                                )
                            ),
                            language: config.language,
                            displaysUsedQuota: displaysUsedQuota
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

        if AlertEngine.shouldAlertLowRemaining(
            snapshot: snapshot,
            rule: descriptor.threshold,
            displaysUsedQuota: displaysUsedQuota
        ) {
            if !activeAlerts.contains(genericKey) {
                notifications.notify(
                    title: text(.lowBalanceWarning),
                    body: Localizer.lowBalanceBody(
                        providerName: descriptor.name,
                        remaining: format(displaysUsedQuota ? snapshot.used : snapshot.remaining),
                        unit: snapshot.unit,
                        language: config.language,
                        displaysUsedQuota: displaysUsedQuota
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

    private func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
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
        copy.rawMeta["codex.isActive"] = isActive ? "true" : "false"
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

    private func triggerCodexProfileSnapshotPrefetchIfNeeded() {
        guard let descriptor = config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
            return
        }

        let existingSlotIDs = Set(codexSlots.map(\.slotID))
        for profile in codexProfiles where !existingSlotIDs.contains(profile.slotID) {
            if codexPrefetchInFlightSlots.contains(profile.slotID) {
                continue
            }
            let identityKey = profile.credentialFingerprint?.lowercased()
                ?? profile.accountSubject?.lowercased()
                ?? profile.accountEmail?.lowercased()
                ?? profile.slotID.rawValue.lowercased()
            if codexPrefetchAttemptedIdentity[profile.slotID] == identityKey {
                continue
            }

            codexPrefetchAttemptedIdentity[profile.slotID] = identityKey
            codexPrefetchInFlightSlots.insert(profile.slotID)

            Task { [weak self] in
                guard let self else { return }
                defer { self.codexPrefetchInFlightSlots.remove(profile.slotID) }

                guard let fetched = try? await self.codexProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                ) else {
                    return
                }
                let snapshot = self.markCodexSnapshotActive(
                    fetched,
                    preferredSlotID: profile.slotID,
                    isActive: false
                )
                self.codexSlots = self.codexSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: profile.slotID
                )
            }
        }
    }

    private static func detectCurrentAppVersion() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "0.0.0"
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = parseVersionComponents(lhs)
        let right = parseVersionComponents(rhs)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func parseVersionComponents(_ raw: String) -> [Int] {
        let normalized = AppUpdateService.normalizeVersion(raw)
        return normalized
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    private func mergedCodexSlotsForMenu() -> [CodexAccountSlot] {
        var mergedBySlotID = Dictionary(uniqueKeysWithValues: codexSlots.map { ($0.slotID, $0) })

        for profile in codexProfiles where mergedBySlotID[profile.slotID] == nil {
            mergedBySlotID[profile.slotID] = placeholderCodexSlot(for: profile)
        }

        return mergedBySlotID.values.map { slot in
            var updated = slot
            if let profile = codexProfiles.first(where: { $0.slotID == slot.slotID }),
               profile.isCurrentSystemAccount {
                updated.isActive = true
            }
            return updated
        }
    }

    private func placeholderCodexSlot(for profile: CodexAccountProfile) -> CodexAccountSlot {
        let accountKey: String
        if let fingerprint = profile.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !fingerprint.isEmpty {
            accountKey = "fingerprint:\(fingerprint)"
        } else if let subject = profile.accountSubject?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !subject.isEmpty {
            accountKey = "subject:\(subject)"
        } else if let email = profile.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !email.isEmpty {
            accountKey = "email:\(email)"
        } else {
            accountKey = "profile:\(profile.slotID.rawValue.lowercased())"
        }

        let slotID = profile.slotID
        let displayName = profile.displayName
        let lastSnapshot = placeholderCodexSnapshot(for: profile)
        let lastSeenAt = profile.lastImportedAt
        let isActive = profile.isCurrentSystemAccount

        return CodexAccountSlot(
            slotID: slotID,
            accountKey: accountKey,
            displayName: displayName,
            lastSnapshot: lastSnapshot,
            lastSeenAt: lastSeenAt,
            isActive: isActive
        )
    }

    private func placeholderCodexSnapshot(for profile: CodexAccountProfile) -> UsageSnapshot {
        var rawMeta: [String: String] = [
            "codex.slotID": profile.slotID.rawValue,
            "codex.menuPlaceholder": "true"
        ]
        if let accountId = profile.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            rawMeta["codex.accountId"] = accountId
        }
        if let subject = profile.accountSubject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            rawMeta["codex.subject"] = subject
        }
        if let fingerprint = profile.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty {
            rawMeta["codex.credentialFingerprint"] = fingerprint
        }

        return UsageSnapshot(
            source: "codex-placeholder-\(profile.slotID.rawValue.lowercased())",
            status: .disabled,
            fetchHealth: .ok,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: profile.lastImportedAt,
            note: "",
            quotaWindows: [],
            sourceLabel: "Codex",
            accountLabel: profile.accountEmail,
            authSourceLabel: nil,
            diagnosticCode: nil,
            extras: [:],
            rawMeta: rawMeta
        )
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
        let email = (snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let subject = snapshot.rawMeta["codex.subject"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fingerprint = snapshot.rawMeta["codex.credentialFingerprint"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let explicitSlotID = CodexAccountSlotStore.explicitSlotID(from: snapshot),
           let matched = codexProfiles.first(where: { $0.slotID == explicitSlotID }) {
            return matched
        }
        if let fingerprint, !fingerprint.isEmpty,
           let matched = codexProfiles.first(where: { $0.credentialFingerprint?.lowercased() == fingerprint }) {
            return matched
        }
        if let subject, !subject.isEmpty,
           let matched = codexProfiles.first(where: { $0.accountSubject?.lowercased() == subject }) {
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
