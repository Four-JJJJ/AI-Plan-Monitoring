import AppKit
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppViewModel {
    static let statusBarDisplayConfigDidChangeNotification = Notification.Name("AIPlanMonitor.StatusBarDisplayConfigDidChange")

    private let configStore = ConfigStore()
    private let keychain = KeychainService()
    private let thirdPartyBalanceBaselineStore = ThirdPartyBalanceBaselineStore()
    private let appUpdateService: any AppUpdateServicing
    private let codexSlotStore = CodexAccountSlotStore()
    private let codexProfileStore = CodexAccountProfileStore()
    private let codexProfileSnapshotService = CodexProfileSnapshotService()
    private let codexDesktopAuthService = CodexDesktopAuthService()
    private let codexDesktopAppService = CodexDesktopAppService()
    private let oauthImportOrchestrator = OAuthImportOrchestrator()
    private let claudeSlotStore = ClaudeAccountSlotStore()
    private let claudeProfileStore = ClaudeAccountProfileStore()
    private let claudeProfileSnapshotService = ClaudeProfileSnapshotService()
    private let claudeDesktopAuthService = ClaudeDesktopAuthService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let notifications = NotificationService()
    private let postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring
    @ObservationIgnored private let localSessionSignalMonitor = LocalSessionCompletionSignalMonitor()
    private let providerFactory: ProviderFactory
    @ObservationIgnored private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator

    private(set) var config: AppConfig
    private(set) var snapshots: [String: UsageSnapshot] = [:]
    private(set) var codexSlots: [CodexAccountSlot] = []
    private(set) var codexProfiles: [CodexAccountProfile] = []
    private(set) var codexSwitchFeedback: [CodexSlotID: CodexSwitchFeedback] = [:]
    private(set) var codexOAuthImportState: OAuthImportState?
    private(set) var claudeSlots: [ClaudeAccountSlot] = []
    private(set) var claudeProfiles: [ClaudeAccountProfile] = []
    private(set) var claudeSwitchFeedback: [CodexSlotID: ClaudeSwitchFeedback] = [:]
    private(set) var claudeOAuthImportState: OAuthImportState?
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
    private(set) var updateDownloadInFlight = false
    private(set) var updateInstallBufferingInFlight = false
    private(set) var updateInstallationInFlight = false
    private(set) var updatePreparedVersion: String?
    private(set) var updateInstallErrorMessage: String?

    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var codexFeedbackTasks: [CodexSlotID: Task<Void, Never>] = [:]
    private var codexSwitchingSlots: Set<CodexSlotID> = []
    private var codexOAuthImportTask: Task<Void, Never>?
    private var codexPrefetchInFlightSlots: Set<CodexSlotID> = []
    private var codexPrefetchAttemptedIdentity: [CodexSlotID: String] = [:]
    private var claudeFeedbackTasks: [CodexSlotID: Task<Void, Never>] = [:]
    private var claudeSwitchingSlots: Set<CodexSlotID> = []
    private var claudeOAuthImportTask: Task<Void, Never>?
    private var claudePrefetchInFlightSlots: Set<CodexSlotID> = []
    private var claudePrefetchAttemptedIdentity: [CodexSlotID: String] = [:]
    private var inactiveProfileBackgroundRefreshLastAttemptAt: [String: Date] = [:]
    private var codexInactiveRefreshCursor = 0
    private var codexInactiveRefreshRetryState = InactiveProfileRefreshRetryState()
    private var claudeInactiveRefreshCursor = 0
    private var claudeInactiveRefreshRetryState = InactiveProfileRefreshRetryState()
    private var didRunClaudeAutoCaptureCompaction = false
    private var consecutiveFailures: [String: Int] = [:]
    private var activeAlerts: Set<String> = []
    private var thirdPartyBalanceBaselineTracker = ThirdPartyBalanceBaselineTracker()
    private var hasStarted = false
    private var lastPermissionStatusRefreshAt = Date.distantPast
    private var notificationPermissionPollingTask: Task<Void, Never>?
    @ObservationIgnored private var permissionRefreshTask: Task<Void, Never>?
    private var preparedUpdate: PreparedAppUpdate?
    private var preparedUpdateInfo: AppUpdateInfo?
    private var updateFlowVersionInFlight: String?
    private var updateInstallBufferTask: Task<Void, Never>?
    private let updateInstallBufferDelaySeconds: TimeInterval
    private var updateCheckStatusClearTask: Task<Void, Never>?
    private let updateCheckStatusClearDelaySeconds: TimeInterval
    @ObservationIgnored private var localSessionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var credentialLookupInFlight: Set<String> = []
    @ObservationIgnored private var credentialLookupMissingKeys: Set<String> = []
    private(set) var credentialLookupVersion: Int = 0

    init(
        appUpdateService: any AppUpdateServicing = AppUpdateService(),
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        updateInstallBufferDelaySeconds: TimeInterval = 5,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10
    ) {
        self.appUpdateService = appUpdateService
        self.postUpdateReleaseNotesStore = postUpdateReleaseNotesStore
        self.updateInstallBufferDelaySeconds = updateInstallBufferDelaySeconds
        self.updateCheckStatusClearDelaySeconds = updateCheckStatusClearDelaySeconds
        let shouldPersistConfigDuringBootstrap: Bool
        var loadedConfig: AppConfig
        do {
            loadedConfig = try configStore.load()
            shouldPersistConfigDuringBootstrap = true
        } catch {
            loadedConfig = .default
            shouldPersistConfigDuringBootstrap = false
        }
        if loadedConfig.simplifiedRelayConfig == false {
            loadedConfig.simplifiedRelayConfig = true
            if shouldPersistConfigDuringBootstrap {
                try? configStore.save(loadedConfig)
            }
        }
        self.config = loadedConfig
        self.currentAppVersion = Self.detectCurrentAppVersion()
        self.providerFactory = ProviderFactory(keychain: keychain)
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.codexSlots = codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        thirdPartyBalanceBaselineTracker.restore(entries: thirdPartyBalanceBaselineStore.load())
        let preNormalizedConfig = self.config
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        if shouldPersistConfigDuringBootstrap && self.config != preNormalizedConfig {
            try? configStore.save(self.config)
        }
        let launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
            self.config.launchAtLoginEnabled = launchAtLoginEnabled
            if shouldPersistConfigDuringBootstrap {
                try? configStore.save(self.config)
            }
        }
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        refreshPermissionStatuses(force: true)
    }

#if DEBUG
    init(
        testingConfig: AppConfig = .default,
        testingCurrentAppVersion: String = "0.0.0",
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        updateInstallBufferDelaySeconds: TimeInterval = 5,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10
    ) {
        self.appUpdateService = appUpdateService
        self.postUpdateReleaseNotesStore = postUpdateReleaseNotesStore
        self.updateInstallBufferDelaySeconds = updateInstallBufferDelaySeconds
        self.updateCheckStatusClearDelaySeconds = updateCheckStatusClearDelaySeconds
        self.config = testingConfig.migratedWithSiteDefaults()
        self.currentAppVersion = testingCurrentAppVersion
        self.providerFactory = ProviderFactory(keychain: keychain)
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.codexSlots = []
        self.claudeSlots = []
        self.codexProfiles = []
        self.claudeProfiles = []
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
    }
#endif

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissionStatuses(force: true)
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

        restartLocalSessionSignalMonitor()
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

        cancelUpdateCheckStatusClear()
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
                let effectiveInstalledVersion = Self.detectNewestInstalledAppVersion(
                    fallbackVersion: self.currentAppVersion
                )
                if Self.isVersion(latest.latestVersion, newerThan: effectiveInstalledVersion) {
                    self.availableUpdate = latest
                    self.lastCheckedLatestVersion = nil
                    if self.updatePreparedVersion != latest.latestVersion {
                        self.clearPreparedUpdateState()
                    }
                } else {
                    self.availableUpdate = nil
                    self.clearPreparedUpdateState()
                    self.scheduleUpdateCheckStatusClear()
                }
            } catch {
                self.updateCheckErrorMessage = error.localizedDescription
                self.lastCheckedLatestVersion = nil
                self.scheduleUpdateCheckStatusClear()
            }
        }
    }

    func openRepositoryPage() {
        NSWorkspace.shared.open(AppUpdateService.repositoryURL)
    }

    func openCurrentVersionReleaseNotes() {
        ReleaseNotesWindowController.shared.show(
            releaseNotes: PendingPostUpdateReleaseNotes(
                version: currentAppVersion,
                releaseURL: AppUpdateService.releasePageURL(forVersion: currentAppVersion),
                notesURL: nil,
                createdAt: Date()
            )
        )
    }

    func openLatestReleaseDownload() {
        performUpdateAction(allowCheckForUpdateFallback: true)
    }

    func performMenuUpdateAction() {
        guard availableUpdate != nil || preparedUpdate != nil else { return }
        performUpdateAction(allowCheckForUpdateFallback: false)
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

    var statusBarMultiUsageEnabled: Bool {
        config.statusBarMultiUsageEnabled
    }

    var statusBarDisplayStyle: StatusBarDisplayStyle {
        config.statusBarDisplayStyle
    }

    var statusBarAppearanceMode: StatusBarAppearanceMode {
        config.statusBarAppearanceMode
    }

    var showOfficialAccountEmailInMenuBar: Bool {
        config.showOfficialAccountEmailInMenuBar
    }

    func thirdPartyBarPercent(for providerID: String) -> Double? {
        thirdPartyBalanceBaselineTracker.percent(for: providerID)
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
        if config.statusBarMultiUsageEnabled {
            return config.statusBarMultiProviderIDs.contains(providerID)
        }
        return config.statusBarProviderID == providerID
    }

    func setStatusBarMultiUsageEnabled(_ enabled: Bool) {
        guard config.statusBarMultiUsageEnabled != enabled else { return }
        config.statusBarMultiUsageEnabled = enabled
        if enabled,
           config.statusBarMultiProviderIDs.isEmpty,
           let selected = config.statusBarProviderID {
            config.statusBarMultiProviderIDs = [selected]
        }
        normalizeStatusBarSelections()
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
    }

    func setStatusBarDisplayStyle(_ style: StatusBarDisplayStyle) {
        guard config.statusBarDisplayStyle != style else { return }
        config.statusBarDisplayStyle = style
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
    }

    func setStatusBarAppearanceMode(_ mode: StatusBarAppearanceMode) {
        guard config.statusBarAppearanceMode != mode else { return }
        config.statusBarAppearanceMode = mode
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
    }

    func setStatusBarDisplayEnabled(_ enabled: Bool, providerID: String) {
        guard config.providers.contains(where: { $0.id == providerID }) else { return }

        if config.statusBarMultiUsageEnabled {
            if enabled {
                if !config.statusBarMultiProviderIDs.contains(providerID) {
                    config.statusBarMultiProviderIDs.append(providerID)
                }
                if config.statusBarProviderID == nil {
                    config.statusBarProviderID = providerID
                }
            } else {
                config.statusBarMultiProviderIDs.removeAll { $0 == providerID }
                if config.statusBarProviderID == providerID {
                    config.statusBarProviderID = config.statusBarMultiProviderIDs.first
                        ?? AppConfig.defaultStatusBarProviderID(from: config.providers)
                }
            }
            normalizeStatusBarSelections()
            try? configStore.save(config)
            notifyStatusBarDisplayConfigChanged()
            return
        }

        guard enabled else { return }
        setStatusBarProvider(providerID: providerID)
    }

    func setStatusBarProvider(providerID: String?) {
        let normalized: String?
        if let providerID,
           config.providers.contains(where: { $0.id == providerID }) {
            normalized = providerID
        } else {
            normalized = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        guard config.statusBarProviderID != normalized else {
            if normalized != nil {
                normalizeStatusBarSelections()
                try? configStore.save(config)
            }
            return
        }
        config.statusBarProviderID = normalized
        normalizeStatusBarSelections()
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
    }

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        guard config.showOfficialAccountEmailInMenuBar != enabled else { return }
        config.showOfficialAccountEmailInMenuBar = enabled
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
    }

    func showOfficialPlanTypeInMenuBar(providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }) else {
            return true
        }
        guard provider.family == .official else {
            return true
        }
        return provider.officialConfig?.showPlanTypeInMenuBar
            ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).showPlanTypeInMenuBar
    }

    func setShowOfficialPlanTypeInMenuBar(_ enabled: Bool, providerID: String) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .official else {
            return
        }

        var provider = config.providers[idx]
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        guard official.showPlanTypeInMenuBar != enabled else { return }
        official.showPlanTypeInMenuBar = enabled
        provider.officialConfig = official
        config.providers[idx] = provider
        try? configStore.save(config)
        notifyStatusBarDisplayConfigChanged()
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

    func statusBarProvidersForDisplay() -> [ProviderDescriptor] {
        if !config.statusBarMultiUsageEnabled {
            if let provider = statusBarProvider() {
                return [provider]
            }
            return []
        }

        let providersByID = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        let selectedProviders = config.statusBarMultiProviderIDs.compactMap { id -> ProviderDescriptor? in
            guard let provider = providersByID[id], provider.enabled else { return nil }
            return provider
        }
        return selectedProviders
    }

    func text(_ key: L10nKey) -> String {
        Localizer.text(key, language: config.language)
    }

    func localizedText(_ zhHans: String, _ en: String) -> String {
        config.language == .zhHans ? zhHans : en
    }

    func runtimeMemoryDiagnostics() -> RuntimeMemoryDiagnostics {
        RuntimeMemoryDiagnostics(
            residentSizeBytes: RuntimeMemoryProbe.residentSizeBytes(),
            snapshotCount: snapshots.count,
            codexProfileCount: codexProfiles.count,
            codexSlotCount: codexSlots.count,
            claudeProfileCount: claudeProfiles.count,
            claudeSlotCount: claudeSlots.count,
            codexPrefetchAttemptedIdentityCount: codexPrefetchAttemptedIdentity.count,
            codexPrefetchInFlightCount: codexPrefetchInFlightSlots.count,
            claudePrefetchAttemptedIdentityCount: claudePrefetchAttemptedIdentity.count,
            claudePrefetchInFlightCount: claudePrefetchInFlightSlots.count,
            pollTaskCount: pollTasks.count
        )
    }

    enum UpdateDisplayTone: Equatable {
        case neutral
        case positive
        case negative
    }

    struct SettingsUpdateDisplayState: Equatable {
        enum Kind: Equatable {
            case idle
            case checkFailed
            case upToDate
            case updateAvailable(version: String)
            case downloading
            case installBuffering
            case failed
        }

        var kind: Kind
        var statusText: String?
        var tone: UpdateDisplayTone
        var retryTitle: String?
        var isRetryEnabled: Bool
    }

    struct MenuUpdateDisplayState: Equatable {
        enum Kind: Equatable {
            case idle
            case updateAvailable(version: String)
            case downloading
            case installBuffering
            case failed
        }

        var kind: Kind
        var statusText: String?
        var tone: UpdateDisplayTone
        var retryTitle: String?
        var isRetryEnabled: Bool
    }

    private var canRetryUpdateAction: Bool {
        isUpdateActionEnabled && (availableUpdate != nil || preparedUpdate != nil)
    }

    var settingsUpdateDisplayState: SettingsUpdateDisplayState {
        if updateInstallErrorMessage != nil {
            return SettingsUpdateDisplayState(
                kind: .failed,
                statusText: localizedText("安装失败", "Install Failed"),
                tone: .negative,
                retryTitle: canRetryUpdateAction ? localizedText("重试", "Retry") : nil,
                isRetryEnabled: canRetryUpdateAction
            )
        }
        if updateCheckErrorMessage != nil {
            return SettingsUpdateDisplayState(
                kind: .checkFailed,
                statusText: localizedText("检查失败", "Check Failed"),
                tone: .negative,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if updateInstallBufferingInFlight || updateInstallationInFlight {
            return SettingsUpdateDisplayState(
                kind: .installBuffering,
                statusText: localizedText("即将安装", "Installing soon"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if updateDownloadInFlight {
            return SettingsUpdateDisplayState(
                kind: .downloading,
                statusText: localizedText("下载中", "Downloading"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if let update = availableUpdate {
            return SettingsUpdateDisplayState(
                kind: .updateAvailable(version: update.latestVersion),
                statusText: localizedText("新版本 \(update.latestVersion)", "New \(update.latestVersion)"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: isUpdateActionEnabled
            )
        }
        if lastCheckedLatestVersion != nil {
            return SettingsUpdateDisplayState(
                kind: .upToDate,
                statusText: localizedText("已经是最新版本", "Up to Date"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        return SettingsUpdateDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral,
            retryTitle: nil,
            isRetryEnabled: false
        )
    }

    var menuUpdateDisplayState: MenuUpdateDisplayState {
        if updateInstallErrorMessage != nil {
            return MenuUpdateDisplayState(
                kind: .failed,
                statusText: localizedText("安装失败", "Install Failed"),
                tone: .negative,
                retryTitle: canRetryUpdateAction ? localizedText("重试", "Retry") : nil,
                isRetryEnabled: canRetryUpdateAction
            )
        }
        if updateInstallBufferingInFlight || updateInstallationInFlight {
            return MenuUpdateDisplayState(
                kind: .installBuffering,
                statusText: localizedText("即将安装", "Installing soon"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if updateDownloadInFlight {
            return MenuUpdateDisplayState(
                kind: .downloading,
                statusText: localizedText("下载中", "Downloading"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if let update = availableUpdate {
            return MenuUpdateDisplayState(
                kind: .updateAvailable(version: update.latestVersion),
                statusText: localizedText("新版本 \(update.latestVersion)", "New \(update.latestVersion)"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: isUpdateActionEnabled
            )
        }
        return MenuUpdateDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral,
            retryTitle: nil,
            isRetryEnabled: false
        )
    }

    var updateActionTitle: String {
        if updateInstallBufferingInFlight || updateInstallationInFlight {
            return localizedText("即将安装", "Installing soon")
        }
        if updateDownloadInFlight {
            return localizedText("下载中", "Downloading")
        }
        if updatePreparedVersion != nil {
            return localizedText("安装更新", "Install Update")
        }
        if availableUpdate != nil {
            return localizedText("安装更新", "Install Update")
        }
        return localizedText("检查更新", "Check for Updates")
    }

    var updateStatusSummary: String? {
        if let message = updateInstallErrorMessage, !message.isEmpty {
            return "\(localizedText("更新失败", "Update failed")): \(message)"
        }
        if updateDownloadInFlight {
            return localizedText("下载中…", "Downloading…")
        }
        if updateInstallBufferingInFlight || updateInstallationInFlight {
            return localizedText("即将安装", "Installing soon")
        }
        if let version = updatePreparedVersion {
            return localizedText("新版本 \(version) 已准备完成。", "Version \(version) is ready.")
        }
        if let update = availableUpdate {
            return localizedText(
                "发现新版本 \(update.latestVersion)，点击“安装更新”开始更新。",
                "Version \(update.latestVersion) is available. Click Install Update to continue."
            )
        }
        if let latest = lastCheckedLatestVersion {
            return localizedText("当前已是最新版本（最新 \(latest)）。", "You're up to date (latest \(latest)).")
        }
        return nil
    }

    var isUpdateActionEnabled: Bool {
        !(updateDownloadInFlight || updateInstallBufferingInFlight || updateInstallationInFlight)
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

    private func performUpdateAction(allowCheckForUpdateFallback: Bool) {
        if updateDownloadInFlight || updateInstallBufferingInFlight || updateInstallationInFlight {
            return
        }

        if let preparedUpdate {
            beginUpdateInstallBuffering(for: preparedUpdate)
            return
        }

        if let availableUpdate {
            beginUpdatePreparation(with: availableUpdate)
            return
        }

        guard allowCheckForUpdateFallback else { return }
        checkForAppUpdate(force: true)
    }

    private func clearPreparedUpdateState() {
        preparedUpdate = nil
        preparedUpdateInfo = nil
        updatePreparedVersion = nil
        updateFlowVersionInFlight = nil
        cancelUpdateInstallBuffering()
    }

    private func cancelUpdateInstallBuffering() {
        updateInstallBufferTask?.cancel()
        updateInstallBufferTask = nil
        updateInstallBufferingInFlight = false
    }

    private func cancelUpdateCheckStatusClear() {
        updateCheckStatusClearTask?.cancel()
        updateCheckStatusClearTask = nil
    }

    private func scheduleUpdateCheckStatusClear() {
        cancelUpdateCheckStatusClear()
        let delaySeconds = max(0, updateCheckStatusClearDelaySeconds)
        updateCheckStatusClearTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.updateCheckErrorMessage = nil
            self.lastCheckedLatestVersion = nil
            self.updateCheckStatusClearTask = nil
        }
    }

    private func beginUpdateInstallBuffering(for prepared: PreparedAppUpdate) {
        guard !updateDownloadInFlight, !updateInstallationInFlight else { return }

        updateInstallErrorMessage = nil
        cancelUpdateInstallBuffering()
        updateInstallBufferingInFlight = true

        let expectedVersion = prepared.version
        updateInstallBufferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.updateInstallBufferDelaySeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.startPreparedUpdateInstallationIfNeeded(expectedVersion: expectedVersion)
        }
    }

    private func startPreparedUpdateInstallationIfNeeded(expectedVersion: String) {
        updateInstallBufferTask = nil
        guard updateInstallBufferingInFlight,
              !updateDownloadInFlight,
              !updateInstallationInFlight,
              let preparedUpdate,
              preparedUpdate.version == expectedVersion else {
            updateInstallBufferingInFlight = false
            return
        }

        updateInstallBufferingInFlight = false
        updateInstallErrorMessage = nil
        updateInstallationInFlight = true
        if let preparedUpdateInfo, preparedUpdateInfo.latestVersion == preparedUpdate.version {
            postUpdateReleaseNotesStore.schedulePresentation(for: preparedUpdateInfo)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.appUpdateService.installPreparedUpdate(
                    preparedUpdate,
                    over: Bundle.main.bundleURL
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                self.updateInstallationInFlight = false
                self.updateInstallErrorMessage = error.localizedDescription
            }
        }
    }

    private func beginUpdatePreparation(with update: AppUpdateInfo) {
        if updateDownloadInFlight || updateInstallBufferingInFlight || updateInstallationInFlight {
            return
        }
        if updatePreparedVersion == update.latestVersion {
            if let preparedUpdate, preparedUpdate.version == update.latestVersion {
                beginUpdateInstallBuffering(for: preparedUpdate)
            }
            return
        }
        if updateFlowVersionInFlight == update.latestVersion {
            return
        }

        cancelUpdateInstallBuffering()
        updateFlowVersionInFlight = update.latestVersion
        updateDownloadInFlight = true
        updateInstallErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let prepared = try await self.appUpdateService.prepareUpdate(update)
                self.preparedUpdate = prepared
                self.preparedUpdateInfo = update
                self.updatePreparedVersion = prepared.version
                self.updateDownloadInFlight = false
                self.updateFlowVersionInFlight = nil
                self.beginUpdateInstallBuffering(for: prepared)
            } catch {
                self.updateDownloadInFlight = false
                self.updateFlowVersionInFlight = nil
                self.updateInstallErrorMessage = error.localizedDescription
            }
        }
    }

    func codexSlotViewModels() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func codexSlotViewModelsForSettings() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func codexProfilesForSettings() -> [CodexAccountProfile] {
        codexProfiles.sorted { $0.slotID < $1.slotID }
    }

    func nextCodexProfileSlotID() -> CodexSlotID {
        codexProfileStore.nextAvailableSlotID()
    }

    func codexSettingsTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    func oauthImportState(for providerType: ProviderType) -> OAuthImportState? {
        switch providerType {
        case .codex:
            return codexOAuthImportState
        case .claude:
            return claudeOAuthImportState
        default:
            return nil
        }
    }

    func claudeOAuthImportEnabled() -> Bool {
        true
    }

    func setClaudeOAuthImportEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID) {
        switch providerType {
        case .codex:
            guard codexOAuthImportTask == nil else { return }
        case .claude:
            guard claudeOAuthImportTask == nil else { return }
        default:
            return
        }

        let provider: OAuthImportProvider
        switch providerType {
        case .codex:
            provider = .codex
        case .claude:
            provider = .claude
        default:
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }

            let result = await self.oauthImportOrchestrator.importAccount(
                provider: provider,
                slotID: slotID
            ) { [weak self] state in
                guard let self else { return }
                switch providerType {
                case .codex:
                    self.codexOAuthImportState = state
                case .claude:
                    self.claudeOAuthImportState = state
                default:
                    break
                }
            }

            switch result {
            case .success(let imported):
                let saveMessage: String
                switch providerType {
                case .codex:
                    let existing = self.codexProfileStore.matchingProfile(authJSON: imported.rawCredentialJSON)
                    let resolvedSlotID = existing?.slotID ?? slotID
                    let resolvedDisplayName = existing?.displayName ?? "Codex \(resolvedSlotID.rawValue)"
                    saveMessage = self.saveCodexProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        authJSON: imported.rawCredentialJSON
                    )
                    self.codexOAuthImportState = OAuthImportState(
                        provider: imported.provider,
                        slotID: resolvedSlotID,
                        mode: imported.mode,
                        phase: .succeeded,
                        detail: saveMessage,
                        startedAt: self.codexOAuthImportState?.startedAt ?? Date(),
                        updatedAt: Date()
                    )
                case .claude:
                    let existing = self.claudeProfileStore.matchingProfile(credentialsJSON: imported.rawCredentialJSON)
                    let resolvedSlotID = existing?.slotID ?? slotID
                    let resolvedDisplayName = existing?.displayName ?? "Claude \(resolvedSlotID.rawValue)"
                    saveMessage = self.saveClaudeProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        source: .manualCredentials,
                        configDir: existing?.configDir,
                        credentialsJSON: imported.rawCredentialJSON
                    )
                    self.claudeOAuthImportState = OAuthImportState(
                        provider: imported.provider,
                        slotID: resolvedSlotID,
                        mode: imported.mode,
                        phase: .succeeded,
                        detail: saveMessage,
                        startedAt: self.claudeOAuthImportState?.startedAt ?? Date(),
                        updatedAt: Date()
                    )
                default:
                    break
                }
            case .failure(let error):
                let description = error.localizedDescription
                switch providerType {
                case .codex:
                    let current = self.codexOAuthImportState
                    self.codexOAuthImportState = OAuthImportState(
                        provider: .codex,
                        slotID: slotID,
                        mode: current?.mode ?? .browserCallback,
                        phase: error == .cancelled ? .cancelled : .failed,
                        detail: description,
                        startedAt: current?.startedAt ?? Date(),
                        updatedAt: Date()
                    )
                case .claude:
                    let current = self.claudeOAuthImportState
                    self.claudeOAuthImportState = OAuthImportState(
                        provider: .claude,
                        slotID: slotID,
                        mode: current?.mode ?? .browserCallback,
                        phase: error == .cancelled ? .cancelled : .failed,
                        detail: description,
                        startedAt: current?.startedAt ?? Date(),
                        updatedAt: Date()
                    )
                default:
                    break
                }
            }

            switch providerType {
            case .codex:
                self.codexOAuthImportTask = nil
            case .claude:
                self.claudeOAuthImportTask = nil
            default:
                break
            }
        }

        switch providerType {
        case .codex:
            codexOAuthImportTask = task
        case .claude:
            claudeOAuthImportTask = task
        default:
            break
        }
    }

    func cancelOAuthImport(providerType: ProviderType) {
        switch providerType {
        case .codex:
            Task { await oauthImportOrchestrator.cancelImport(provider: .codex) }
        case .claude:
            Task { await oauthImportOrchestrator.cancelImport(provider: .claude) }
        default:
            break
        }
    }

    func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String) -> String {
        do {
            _ = try codexProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
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
        codexSlots = codexSlotStore.remove(slotID: slotID)
        codexPrefetchAttemptedIdentity.removeValue(forKey: slotID)
        codexPrefetchInFlightSlots.remove(slotID)
        codexInactiveRefreshRetryState.remove(slotID: slotID)
        setCodexSwitchFeedback(nil, for: slotID)
    }

    func claudeSlotViewModels() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func claudeSlotViewModelsForSettings() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func claudeProfilesForSettings() -> [ClaudeAccountProfile] {
        claudeProfiles.sorted { $0.slotID < $1.slotID }
    }

    func refreshSettingsProfileState() {
        syncCodexProfilesCurrentState()
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
    }

    private func codexSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [CodexSlotViewModel] {
        if refreshFromStore {
            let latestCodexSlots = codexSlotStore.visibleSlots()
            if latestCodexSlots != codexSlots {
                codexSlots = latestCodexSlots
            }
        }
        if triggerPrefetch {
            triggerCodexProfileSnapshotPrefetchIfNeeded()
        }
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
                    note: profile?.note,
                    isSwitching: codexSwitchingSlots.contains(slot.slotID),
                    canSwitch: profile != nil && !(profile?.isCurrentSystemAccount ?? false),
                    isCurrentSystemAccount: profile?.isCurrentSystemAccount ?? false,
                    profileDisplayName: profile?.displayName,
                    switchMessage: feedback?.message,
                    switchMessageIsError: feedback?.isError ?? false
                )
            }
    }

    private func claudeSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [ClaudeSlotViewModel] {
        if refreshFromStore {
            let latestClaudeSlots = claudeSlotStore.visibleSlots()
            if latestClaudeSlots != claudeSlots {
                claudeSlots = latestClaudeSlots
            }
        }
        if triggerPrefetch {
            triggerClaudeProfileSnapshotPrefetchIfNeeded()
        }
        let now = Date()
        return mergedClaudeSlotsForMenu()
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
                return lhs.slotID < rhs.slotID
            }
            .map { slot in
                let profile = matchedClaudeProfile(for: slot)
                let feedback = claudeSwitchFeedback[slot.slotID]
                let displaySnapshot = CodexQuotaDisplayNormalizer.normalize(
                    snapshot: slot.lastSnapshot,
                    isActive: slot.isActive,
                    now: now
                )
                return ClaudeSlotViewModel(
                    slotID: slot.slotID,
                    title: claudeMenuTitle(for: slot.slotID),
                    snapshot: displaySnapshot,
                    isActive: slot.isActive,
                    lastSeenAt: slot.lastSeenAt,
                    displayName: profile?.displayName ?? slot.displayName,
                    note: profile?.note,
                    source: profile?.source,
                    isSwitching: claudeSwitchingSlots.contains(slot.slotID),
                    canSwitch: profile != nil && !(profile?.isCurrentSystemAccount ?? false),
                    isCurrentSystemAccount: profile?.isCurrentSystemAccount ?? false,
                    profileDisplayName: profile?.displayName,
                    switchMessage: feedback?.message,
                    switchMessageIsError: feedback?.isError ?? false
                )
            }
    }

    func nextClaudeProfileSlotID() -> CodexSlotID {
        claudeProfileStore.nextAvailableSlotID()
    }

    func claudeSettingsTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    func saveClaudeProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) -> String {
        do {
            _ = try claudeProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON,
                currentFingerprint: claudeDesktopAuthService.currentCredentialFingerprint()
            )
            syncClaudeProfilesCurrentState()
            return localizedText("Claude 账号档案已导入", "Claude profile imported")
        } catch {
            return "\(localizedText("导入失败", "Import failed")): \(error.localizedDescription)"
        }
    }

    func removeClaudeProfile(slotID: CodexSlotID) {
        syncClaudeProfilesCurrentState()
        claudeProfiles = claudeProfileStore.removeProfile(slotID: slotID)
        claudeSlots = claudeSlotStore.remove(slotID: slotID)
        claudePrefetchAttemptedIdentity.removeValue(forKey: slotID)
        claudePrefetchInFlightSlots.remove(slotID)
        claudeInactiveRefreshRetryState.remove(slotID: slotID)
        setClaudeSwitchFeedback(nil, for: slotID)
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
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        SettingsWindowController.shared.show(viewModel: self)
        let ok = keychain.prepareSecureStoreAccess()
        if ok {
            invalidateCredentialLookupCache()
        }
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
        refreshPermissionStatuses(force: true)
        return ok
    }

    func openNotificationSettings() {
        openSystemSettings(
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications"
            ]
        )
    }

    func openKeychainAccessSettings() {
        // 保留接口兼容旧调用，但不再主动拉起系统应用，避免钥匙串授权时打断当前窗口焦点。
    }

    func openFullDiskAccessSettings() {
        fullDiskAccessRequested = true
        openSystemSettings(
            urlCandidates: [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            ]
        )
    }

    private func openSystemSettings(urlCandidates: [String], fallbackBundleIDs: [String] = ["com.apple.systemsettings", "com.apple.systempreferences"]) {
        for raw in urlCandidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettingsApplication(bundleIDs: fallbackBundleIDs)
    }

    private func openSystemSettingsApplication(bundleIDs: [String]) {
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
        codexOAuthImportTask?.cancel()
        codexOAuthImportTask = nil
        Task { await oauthImportOrchestrator.cancelImport(provider: .codex) }
        claudeFeedbackTasks.values.forEach { $0.cancel() }
        claudeFeedbackTasks.removeAll()
        claudeOAuthImportTask?.cancel()
        claudeOAuthImportTask = nil
        Task { await oauthImportOrchestrator.cancelImport(provider: .claude) }
        codexSwitchingSlots.removeAll()
        codexPrefetchInFlightSlots.removeAll()
        codexPrefetchAttemptedIdentity.removeAll()
        codexInactiveRefreshCursor = 0
        codexInactiveRefreshRetryState = InactiveProfileRefreshRetryState()
        codexSwitchFeedback.removeAll()
        codexOAuthImportState = nil
        claudeSwitchingSlots.removeAll()
        claudePrefetchInFlightSlots.removeAll()
        claudePrefetchAttemptedIdentity.removeAll()
        claudeInactiveRefreshCursor = 0
        claudeInactiveRefreshRetryState = InactiveProfileRefreshRetryState()
        inactiveProfileBackgroundRefreshLastAttemptAt.removeAll()
        didRunClaudeAutoCaptureCompaction = false
        claudeSwitchFeedback.removeAll()
        claudeOAuthImportState = nil
        snapshots.removeAll()
        errors.removeAll()
        consecutiveFailures.removeAll()
        activeAlerts.removeAll()
        thirdPartyBalanceBaselineTracker.removeAll()
        thirdPartyBalanceBaselineStore.reset()
        lastUpdatedAt = nil

        launchAtLoginService.reset()
        keychain.resetAllStoredCredentials()
        codexProfileStore.reset()
        codexSlotStore.reset()
        claudeProfileStore.reset()
        claudeSlotStore.reset()
        try? configStore.reset()

        config = .default
        codexSlots = []
        codexProfiles = []
        claudeSlots = []
        claudeProfiles = []
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
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
                    snapshots[descriptor.id] = boundedSnapshot(snapshot)
                } else if descriptor.type == .claude {
                    let snapshot = markClaudeSnapshotActive(fetched)
                    claudeSlots = claudeSlotStore.upsertActive(snapshot: snapshot)
                    snapshots[descriptor.id] = boundedSnapshot(snapshot)
                } else {
                    snapshots[descriptor.id] = boundedSnapshot(fetched)
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

        normalizeStatusBarSelections()

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
                snapshots[descriptor.id] = boundedSnapshot(snapshot)
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

    func switchClaudeProfile(slotID: CodexSlotID) async {
        guard !claudeSwitchingSlots.contains(slotID) else { return }
        syncClaudeProfilesCurrentState()
        claudeSwitchingSlots.insert(slotID)
        setClaudeSwitchFeedback(nil, for: slotID)
        defer { claudeSwitchingSlots.remove(slotID) }

        guard let profile = claudeProfiles.first(where: { $0.slotID == slotID }) else {
            setClaudeSwitchFeedback(
                ClaudeSwitchFeedback(
                    message: localizedText("该槽位还没有导入可切换的 Claude 账号", "No imported Claude profile is available for this slot"),
                    isError: true
                ),
                for: slotID
            )
            return
        }

        do {
            let credentialsJSON = try claudeProfileStore.resolvedCredentialsJSON(for: profile)
            try claudeDesktopAuthService.applyCredentialsJSON(credentialsJSON)
            syncClaudeProfilesCurrentState()

            guard let descriptor = config.providers.first(where: { $0.type == .claude && $0.family == .official }) else {
                setClaudeSwitchFeedback(
                    ClaudeSwitchFeedback(
                        message: localizedText("已写入本机 Claude 登录", "Local Claude credentials updated"),
                        isError: false
                    ),
                    for: slotID
                )
                return
            }

            let provider = providerFactory.makeProvider(for: descriptor)
            do {
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = markClaudeSnapshotActive(fetched, preferredSlotID: slotID)
                claudeSlots = claudeSlotStore.upsertActive(snapshot: snapshot)
                snapshots[descriptor.id] = boundedSnapshot(snapshot)
                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()
                let successMessage = localizedText("已切换 Claude 账号", "Claude account switched")
                setClaudeSwitchFeedback(
                    ClaudeSwitchFeedback(message: successMessage, isError: false),
                    for: slotID
                )
                notifications.notify(
                    title: "Claude",
                    body: successMessage,
                    identifier: "claude-switch-\(slotID.rawValue.lowercased())"
                )
            } catch {
                errors[descriptor.id] = error.localizedDescription
                let message = "\(localizedText("已切换到该账号，但需要重新验证", "Switched to this account, but re-verification is required")): \(error.localizedDescription)"
                setClaudeSwitchFeedback(
                    ClaudeSwitchFeedback(message: message, isError: true),
                    for: slotID
                )
                notifications.notify(
                    title: "Claude",
                    body: message,
                    identifier: "claude-switch-\(slotID.rawValue.lowercased())"
                )
            }
        } catch {
            setClaudeSwitchFeedback(
                ClaudeSwitchFeedback(
                    message: "\(localizedText("切换失败", "Switch failed")): \(error.localizedDescription)",
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
        permissionRefreshTask?.cancel()
        let keychain = self.keychain
        permissionRefreshTask = Task { [weak self, keychain] in
            let ready = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: keychain.isSecureStoreReady())
                }
            }
            guard let self, !Task.isCancelled else { return }
            let wasReady = self.secureStorageReady
            self.secureStorageReady = ready
            if ready && !wasReady {
                self.invalidateCredentialLookupCache()
            }
        }

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
        if !enabled, config.providers[idx].family == .thirdParty {
            thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
            persistThirdPartyBalanceBaselines()
        }
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
        return cachedCredentialExists(service: service, account: account)
    }

    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? {
        savedCredentialLength(
            service: descriptor.auth.keychainService,
            account: descriptor.auth.keychainAccount
        )
    }

    func hasToken(auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return cachedCredentialExists(service: service, account: account)
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        savedCredentialLength(
            service: auth.keychainService,
            account: auth.keychainAccount
        )
    }

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return false
        }
        let normalized = normalizedCredential(token, kind: descriptor.auth.kind)
        guard !normalized.isEmpty else { return false }
        let ok = keychain.saveToken(normalized, service: service, account: account)
        if ok {
            markCredentialLookupCached(service: service, account: account)
        }
        return ok
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        let normalized = normalizedCredential(token, kind: auth.kind)
        guard !normalized.isEmpty else { return false }
        let ok = keychain.saveToken(normalized, service: service, account: account)
        if ok {
            markCredentialLookupCached(service: service, account: account)
        }
        return ok
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return false
        }
        return cachedCredentialExists(service: KeychainService.defaultServiceName, account: account)
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        guard provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return nil
        }
        return savedCredentialLength(service: KeychainService.defaultServiceName, account: account)
    }

    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }),
              provider.family == .official,
              let account = provider.officialConfig?.manualCookieAccount else {
            return false
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ok = keychain.saveToken(trimmed, service: KeychainService.defaultServiceName, account: account)
        if ok {
            markCredentialLookupCached(service: KeychainService.defaultServiceName, account: account)
        }
        return ok
    }

    private func savedCredentialLength(service: String?, account: String?) -> Int? {
        _ = credentialLookupVersion
        guard let service,
              let account,
              !service.isEmpty,
              !account.isEmpty else {
            return nil
        }
        guard let token = keychain.cachedToken(service: service, account: account),
              !token.isEmpty else {
            guard secureStorageReady else {
                return nil
            }
            scheduleCredentialLookup(service: service, account: account)
            return nil
        }
        return token.count
    }

    private func cachedCredentialExists(service: String?, account: String?) -> Bool {
        savedCredentialLength(service: service, account: account) != nil
    }

    private func scheduleCredentialLookup(service: String, account: String) {
        let key = credentialLookupCacheKey(service: service, account: account)
        guard !credentialLookupInFlight.contains(key),
              !credentialLookupMissingKeys.contains(key) else {
            return
        }
        credentialLookupInFlight.insert(key)

        let keychain = self.keychain
        Task { [weak self, keychain, service, account, key] in
            let token = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let token = keychain.readToken(service: service, account: account)
                    continuation.resume(returning: token)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.credentialLookupInFlight.remove(key)
            if let token, !token.isEmpty {
                self.credentialLookupMissingKeys.remove(key)
                self.credentialLookupVersion &+= 1
            } else {
                self.credentialLookupMissingKeys.insert(key)
            }
        }
    }

    private func credentialLookupCacheKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }

    private func markCredentialLookupCached(service: String, account: String) {
        let key = credentialLookupCacheKey(service: service, account: account)
        credentialLookupInFlight.remove(key)
        credentialLookupMissingKeys.remove(key)
        credentialLookupVersion &+= 1
    }

    private func invalidateCredentialLookupCache() {
        credentialLookupInFlight.removeAll()
        credentialLookupMissingKeys.removeAll()
        credentialLookupVersion &+= 1
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
        thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
        persistThirdPartyBalanceBaselines()
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
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
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
                unit: unit,
                quotaDisplayMode: quotaDisplayMode
              ) else {
            return
        }
        let previousDisplaysUsedQuota = config.providers[idx].displaysUsedQuota
        let previousName = config.providers[idx].name
        config.providers[idx] = updated
        persistAndRestart()
        if previousDisplaysUsedQuota != updated.displaysUsedQuota
            || previousName != updated.name {
            notifyStatusBarDisplayConfigChanged()
        }
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
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
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
        if let quotaDisplayMode {
            relayConfig.quotaDisplayMode = quotaDisplayMode
        }

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
            ? (templateExtract.unit ?? "USD")
            : nonEmptyOrDefault(unit, fallback: "USD")

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

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .thirdParty,
              config.providers[idx].isRelay,
              var relayConfig = config.providers[idx].relayConfig else {
            return
        }
        var provider = config.providers[idx]
        let previousDisplaysUsedQuota = provider.displaysUsedQuota
        relayConfig.quotaDisplayMode = quotaDisplayMode
        provider.relayConfig = relayConfig
        let normalizedProvider = provider.normalized()
        config.providers[idx] = normalizedProvider
        persistAndRestart()
        if previousDisplaysUsedQuota != normalizedProvider.displaysUsedQuota {
            notifyStatusBarDisplayConfigChanged()
        }
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
            snapshots[descriptor.id] = boundedSnapshot(snapshot)
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
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .official else {
            return
        }

        var provider = config.providers[idx]
        let previousDisplaysUsedQuota = provider.displaysUsedQuota
        let previousTraeDisplaysAmount = provider.traeDisplaysAmount
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        official.sourceMode = sourceMode
        official.webMode = webMode
        if let quotaDisplayMode {
            official.quotaDisplayMode = quotaDisplayMode
        }
        if let traeValueDisplayMode {
            official.traeValueDisplayMode = traeValueDisplayMode
        }
        provider.officialConfig = official
        config.providers[idx] = provider
        persistAndRestart()
        if previousDisplaysUsedQuota != provider.displaysUsedQuota
            || previousTraeDisplaysAmount != provider.traeDisplaysAmount {
            notifyStatusBarDisplayConfigChanged()
        }
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
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        try? configStore.save(config)
        restartPolling()
        syncClaudeProfilesCurrentState()
        triggerClaudeProfileSnapshotPrefetchIfNeeded()
    }

    private func normalizeStatusBarSelections() {
        let enabledProviders = config.providers.filter(\.enabled)
        let enabledProviderIDs = Set(enabledProviders.map(\.id))

        if let selectedID = config.statusBarProviderID,
           !enabledProviderIDs.contains(selectedID) {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        } else if config.statusBarProviderID == nil {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }

        config.statusBarMultiProviderIDs = AppConfig.normalizedStatusBarMultiProviderIDs(
            config.statusBarMultiProviderIDs,
            providers: config.providers
        ).filter { enabledProviderIDs.contains($0) }
    }

    private func pruneThirdPartyBalanceBaselines() {
        let previousEntries = thirdPartyBalanceBaselineTracker.snapshotEntries()
        let validProviderIDs = Set(
            config.providers
                .filter { $0.family == .thirdParty }
                .map(\.id)
        )
        thirdPartyBalanceBaselineTracker.prune(
            keepingProviderIDs: validProviderIDs,
            maxEntries: RuntimeDiagnosticsLimits.thirdPartyBalanceBaselineCacheMaxEntries
        )
        persistThirdPartyBalanceBaselinesIfChanged(previousEntries: previousEntries)
    }

    private func persistThirdPartyBalanceBaselinesIfChanged(
        previousEntries: [String: ThirdPartyBalanceBaselineTracker.Entry]
    ) {
        let latestEntries = thirdPartyBalanceBaselineTracker.snapshotEntries()
        guard latestEntries != previousEntries else { return }
        thirdPartyBalanceBaselineStore.save(latestEntries)
    }

    private func persistThirdPartyBalanceBaselines() {
        thirdPartyBalanceBaselineStore.save(thirdPartyBalanceBaselineTracker.snapshotEntries())
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
            return descriptor.family == .official ? "Kimi Coding" : "Kimi"
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
            return descriptor.name
        }
    }

    private func normalizedCredential(_ token: String, kind: AuthKind) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .bearer:
            return TraeProvider.normalizeToken(trimmed)
        case .none, .localCodex:
            return trimmed
        }
    }

    private func descriptor(for id: String) -> ProviderDescriptor? {
        config.providers.first(where: { $0.id == id })
    }

    private func pollLoop(providerID: String) async {
        let startupJitterSeconds = Double.random(in: 0...20)
        if startupJitterSeconds > 0 {
            do {
                try await Task.sleep(for: .seconds(startupJitterSeconds))
            } catch {
                return
            }
        }

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

    private func restartLocalSessionSignalMonitor() {
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
        let hasWatchTargets = config.providers.contains {
            $0.enabled && $0.family == .official && ($0.type == .codex || $0.type == .claude)
        }
        guard hasWatchTargets else {
            return
        }
        localSessionMonitorTask = Task { [weak self] in
            await self?.localSessionSignalLoop()
        }
    }

    private func localSessionSignalLoop() async {
        var idleCycles = 0
        while !Task.isCancelled {
            let watchTargets = config.providers.filter {
                $0.enabled && $0.family == .official && ($0.type == .codex || $0.type == .claude)
            }
            if watchTargets.isEmpty {
                return
            }

            var didTriggerRefresh = false
            if !watchTargets.isEmpty {
                let refreshTargets = localSessionRefreshCoordinator.refreshCandidates(from: watchTargets)
                for descriptor in refreshTargets {
                    didTriggerRefresh = true
                    await refreshProvider(descriptor, forceRefresh: false)
                }
            }

            if didTriggerRefresh {
                idleCycles = 0
            } else {
                idleCycles += 1
            }

            let sleepSeconds: TimeInterval
            if idleCycles <= 2 {
                sleepSeconds = 10
            } else {
                sleepSeconds = 30
            }

            do {
                try await Task.sleep(for: .seconds(sleepSeconds))
            } catch {
                return
            }
        }
    }

    private func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        defer { pruneThirdPartyBalanceBaselines() }
        let isClaudeOfficial = descriptor.type == .claude && descriptor.family == .official
        if descriptor.type == .codex, descriptor.family == .official {
            syncCodexProfilesCurrentState()
        }
        if isClaudeOfficial {
            syncClaudeProfilesCurrentState()
        }
        let provider = providerFactory.makeProvider(for: descriptor)

        do {
            let fetched = try await provider.fetch(forceRefresh: forceRefresh)
            let snapshot: UsageSnapshot
            if descriptor.type == .codex, descriptor.family == .official {
                snapshot = markCodexSnapshotActive(fetched)
                codexSlots = codexSlotStore.upsertActive(snapshot: snapshot)
            } else if descriptor.type == .claude, descriptor.family == .official {
                snapshot = markClaudeSnapshotActive(fetched)
                claudeSlots = claudeSlotStore.upsertActive(snapshot: snapshot)
            } else {
                snapshot = fetched
            }
            snapshots[descriptor.id] = boundedSnapshot(snapshot)
            if descriptor.family == .thirdParty {
                let previousEntries = thirdPartyBalanceBaselineTracker.snapshotEntries()
                _ = thirdPartyBalanceBaselineTracker.record(
                    remaining: resolvedThirdPartyRemainingForBaseline(snapshot),
                    for: descriptor.id,
                    at: snapshot.updatedAt
                )
                persistThirdPartyBalanceBaselinesIfChanged(previousEntries: previousEntries)
            }
            errors.removeValue(forKey: descriptor.id)
            consecutiveFailures[descriptor.id] = 0
            lastUpdatedAt = Date()
            if descriptor.family == .official {
                if forceRefresh {
                    await refreshOfficialProfileCardsAfterManualRefresh(for: descriptor)
                } else {
                    await refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for: descriptor)
                }
            }

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
                previous.note = RuntimeBoundedState.appendSnapshotNote(
                    existing: previous.note,
                    appending: "rate limited, showing cached value"
                )
                snapshots[descriptor.id] = boundedSnapshot(previous)
                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()
                return
            }

            errors[descriptor.id] = error.localizedDescription
            consecutiveFailures[descriptor.id, default: 0] += 1
            let health = classifyFetchHealth(error)
            if descriptor.isRelay || descriptor.family == .official {
                if var previous = snapshots[descriptor.id] {
                    previous.fetchHealth = health
                    previous.valueFreshness = .cachedFallback
                    previous.updatedAt = Date()
                    previous.diagnosticCode = Self.diagnosticCode(for: health)
                    previous.note = RuntimeBoundedState.appendSnapshotNote(
                        existing: previous.note,
                        appending: error.localizedDescription
                    )
                    snapshots[descriptor.id] = boundedSnapshot(previous)
                } else if let emptySnapshot = Self.emptySnapshotForFetchFailure(
                    descriptor: descriptor,
                    health: health,
                    message: error.localizedDescription
                ) {
                    snapshots[descriptor.id] = boundedSnapshot(emptySnapshot)
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

    nonisolated static func diagnosticCode(for health: FetchHealth) -> String {
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

    nonisolated static func emptySnapshotForFetchFailure(
        descriptor: ProviderDescriptor,
        health: FetchHealth,
        message: String,
        now: Date = Date()
    ) -> UsageSnapshot? {
        if descriptor.isRelay {
            return UsageSnapshot(
                source: descriptor.id,
                status: .error,
                fetchHealth: health,
                valueFreshness: .empty,
                remaining: nil,
                used: nil,
                limit: nil,
                unit: descriptor.relayViewConfig?.accountBalance?.unit ?? "quota",
                updatedAt: now,
                note: message,
                sourceLabel: "Third-Party",
                accountLabel: nil,
                authSourceLabel: nil,
                diagnosticCode: diagnosticCode(for: health)
            )
        }

        guard descriptor.family == .official else {
            return nil
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: .error,
            fetchHealth: health,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: now,
            note: message,
            sourceLabel: "Official",
            accountLabel: nil,
            authSourceLabel: nil,
            diagnosticCode: diagnosticCode(for: health)
        )
    }

    private func handleLowRemainingAlerts(for descriptor: ProviderDescriptor, snapshot: UsageSnapshot) {
        let genericKey = "low:\(descriptor.id)"
        let displaysUsedQuota = descriptor.displaysUsedQuota && (snapshot.used != nil || !snapshot.quotaWindows.isEmpty)
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
                        remaining: format(displaysUsedQuota ? (snapshot.used ?? snapshot.remaining) : snapshot.remaining),
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

    private func resolvedThirdPartyRemainingForBaseline(_ snapshot: UsageSnapshot) -> Double? {
        Self.resolvedThirdPartyRemainingForBaseline(
            remaining: snapshot.remaining,
            used: snapshot.used,
            limit: snapshot.limit
        )
    }

    nonisolated static func resolvedThirdPartyRemainingForBaseline(
        remaining: Double?,
        used: Double?,
        limit: Double?
    ) -> Double? {
        ThirdPartyBalanceBaselineTracker.resolvedRemainingForBaseline(
            remaining: remaining,
            used: used,
            limit: limit
        )
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

    private func notifyStatusBarDisplayConfigChanged() {
        NotificationCenter.default.post(
            name: Self.statusBarDisplayConfigDidChangeNotification,
            object: nil
        )
    }

    private func boundedSnapshot(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        var copy = snapshot
        copy.note = RuntimeBoundedState.boundedSnapshotNote(copy.note)
        return copy
    }

    private func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        var copy = snapshot
        if let teamID = CodexIdentity.teamID(from: copy) {
            copy.rawMeta["codex.accountId"] = teamID
            copy.rawMeta["codex.teamId"] = teamID
        }
        let identity = CodexIdentity.from(snapshot: copy)
        let resolvedSlotID = preferredSlotID ?? matchedCodexProfile(for: copy)?.slotID
        let accountKey = CodexAccountSlotStore.accountKey(from: copy)
        let label = CodexAccountSlotStore.accountLabel(from: copy)
        if let resolvedSlotID {
            copy.rawMeta["codex.slotID"] = resolvedSlotID.rawValue
        }
        copy.rawMeta["codex.tenantKey"] = identity.tenantKey
        copy.rawMeta["codex.principalKey"] = identity.principalKey
        copy.rawMeta["codex.identityKey"] = identity.identityKey
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
        let latestProfiles = codexProfileStore.captureCurrentAuthIfNeeded(
            authJSON: codexDesktopAuthService.currentAuthJSON()
        )
        if latestProfiles != codexProfiles {
            codexProfiles = latestProfiles
        }
        codexInactiveRefreshRetryState.prune(keeping: Set(latestProfiles.map(\.slotID)))
    }

    private func codexMenuTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    private enum InactiveProfileRefreshResult {
        case success
        case failed
        case skipped
    }

    private func refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for descriptor: ProviderDescriptor) async {
        guard descriptor.family == .official else { return }
        switch descriptor.type {
        case .codex:
            await refreshCodexInactiveProfileCardInBackground(descriptor: descriptor)
        case .claude:
            await refreshClaudeInactiveProfileCardInBackground(descriptor: descriptor)
        case .relay, .open, .dragon, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            break
        }
    }

    private func refreshCodexInactiveProfileCardInBackground(descriptor: ProviderDescriptor) async {
        syncCodexProfilesCurrentState()
        let orderedProfiles = codexProfiles.sorted { $0.slotID < $1.slotID }
        let orderedSlotIDs = orderedProfiles.map(\.slotID)
        let visibleSlotIDs = Set(orderedSlotIDs)
        codexInactiveRefreshRetryState.prune(keeping: visibleSlotIDs)
        guard !orderedSlotIDs.isEmpty else { return }

        let now = Date()
        guard InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
            lastAttemptAt: inactiveProfileBackgroundRefreshLastAttemptAt[descriptor.id],
            minimumInterval: TimeInterval(descriptor.pollIntervalSec),
            now: now
        ) else {
            return
        }

        let activeSlotIDs = Set(codexSlots.filter(\.isActive).map(\.slotID))
        guard let selection = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: orderedSlotIDs,
            activeSlotIDs: activeSlotIDs,
            inFlightSlotIDs: codexPrefetchInFlightSlots,
            retryNotBefore: codexInactiveRefreshRetryState.retryNotBefore,
            cursor: codexInactiveRefreshCursor,
            now: now
        ) else {
            return
        }

        codexInactiveRefreshCursor = selection.nextCursor
        inactiveProfileBackgroundRefreshLastAttemptAt[descriptor.id] = now

        guard let profile = orderedProfiles.first(where: { $0.slotID == selection.slotID }) else {
            return
        }

        let result = await refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
        switch result {
        case .success:
            codexInactiveRefreshRetryState.markSuccess(slotID: selection.slotID)
        case .failed:
            codexInactiveRefreshRetryState.markFailure(
                slotID: selection.slotID,
                baseInterval: descriptor.pollIntervalSec,
                now: Date()
            )
        case .skipped:
            break
        }
    }

    private func refreshClaudeInactiveProfileCardInBackground(descriptor: ProviderDescriptor) async {
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
        let orderedProfiles = claudeProfiles.sorted { $0.slotID < $1.slotID }
        let orderedSlotIDs = orderedProfiles.map(\.slotID)
        let visibleSlotIDs = Set(orderedSlotIDs)
        claudeInactiveRefreshRetryState.prune(keeping: visibleSlotIDs)
        guard !orderedSlotIDs.isEmpty else { return }

        let now = Date()
        guard InactiveProfileRefreshPlanner.shouldAttemptProviderRefresh(
            lastAttemptAt: inactiveProfileBackgroundRefreshLastAttemptAt[descriptor.id],
            minimumInterval: TimeInterval(descriptor.pollIntervalSec),
            now: now
        ) else {
            return
        }

        let activeSlotIDs = Set(claudeSlots.filter(\.isActive).map(\.slotID))
        guard let selection = InactiveProfileRefreshPlanner.selectNextSlot(
            orderedSlotIDs: orderedSlotIDs,
            activeSlotIDs: activeSlotIDs,
            inFlightSlotIDs: claudePrefetchInFlightSlots,
            retryNotBefore: claudeInactiveRefreshRetryState.retryNotBefore,
            cursor: claudeInactiveRefreshCursor,
            now: now
        ) else {
            return
        }

        claudeInactiveRefreshCursor = selection.nextCursor
        inactiveProfileBackgroundRefreshLastAttemptAt[descriptor.id] = now

        guard let profile = orderedProfiles.first(where: { $0.slotID == selection.slotID }) else {
            return
        }

        let result = await refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
        switch result {
        case .success:
            claudeInactiveRefreshRetryState.markSuccess(slotID: selection.slotID)
        case .failed:
            claudeInactiveRefreshRetryState.markFailure(
                slotID: selection.slotID,
                baseInterval: descriptor.pollIntervalSec,
                now: Date()
            )
        case .skipped:
            break
        }
    }

    private func refreshOfficialProfileCardsAfterManualRefresh(for descriptor: ProviderDescriptor) async {
        guard descriptor.family == .official else { return }
        switch descriptor.type {
        case .codex:
            await refreshCodexProfileCardsAfterManualRefresh(descriptor: descriptor)
        case .claude:
            await refreshClaudeProfileCardsAfterManualRefresh(descriptor: descriptor)
        case .relay, .open, .dragon, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            break
        }
    }

    private func refreshCodexProfileCardsAfterManualRefresh(descriptor: ProviderDescriptor) async {
        syncCodexProfilesCurrentState()
        let activeSlotIDs = Set(codexSlots.filter(\.isActive).map(\.slotID))
        for profile in codexProfiles.sorted(by: { $0.slotID < $1.slotID }) where !activeSlotIDs.contains(profile.slotID) {
            _ = await refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
        }
    }

    private func refreshCodexProfileSnapshotSlot(
        _ profile: CodexAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> InactiveProfileRefreshResult {
        if codexPrefetchInFlightSlots.contains(profile.slotID) {
            return .skipped
        }
        codexPrefetchInFlightSlots.insert(profile.slotID)
        defer { codexPrefetchInFlightSlots.remove(profile.slotID) }

        guard let result = try? await codexProfileSnapshotService.fetchSnapshot(
            profile: profile,
            descriptor: descriptor
        ) else {
            return .failed
        }

        if let refreshedAuthJSON = result.refreshedAuthJSON, !refreshedAuthJSON.isEmpty {
            _ = codexProfileStore.updateStoredAuthJSON(
                slotID: profile.slotID,
                authJSON: refreshedAuthJSON
            )
            syncCodexProfilesCurrentState()
        }

        let snapshot = boundedSnapshot(
            markCodexSnapshotActive(
                result.snapshot,
                preferredSlotID: profile.slotID,
                isActive: false
            )
        )
        codexSlots = codexSlotStore.upsertInactive(
            snapshot: snapshot,
            preferredSlotID: profile.slotID
        )
        return .success
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
            let identityKey = CodexIdentity.from(profile: profile).identityKey
            if codexPrefetchAttemptedIdentity[profile.slotID] == identityKey {
                continue
            }

            codexPrefetchAttemptedIdentity[profile.slotID] = identityKey

            Task { [weak self] in
                guard let self else { return }
                _ = await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
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

    private static func detectNewestInstalledAppVersion(fallbackVersion: String) -> String {
        var newest = fallbackVersion
        for bundleURL in candidateInstalledAppBundleURLs() {
            guard let version = bundleVersion(at: bundleURL) else { continue }
            if isVersion(version, newerThan: newest) {
                newest = version
            }
        }
        return newest
    }

    private static func candidateInstalledAppBundleURLs() -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []

        if Bundle.main.bundleURL.pathExtension == "app" {
            urls.append(Bundle.main.bundleURL.standardizedFileURL)
        }

        let appBundleName = "AI Plan Monitor.app"
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        urls.append(systemApplications.appendingPathComponent(appBundleName).standardizedFileURL)
        urls.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent(appBundleName)
                .standardizedFileURL
        )

        var deduped: [URL] = []
        var seen: Set<String> = []
        for url in urls {
            let key = url.path
            if seen.insert(key).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }

    private static func bundleVersion(at bundleURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: bundleURL.path),
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }

        if let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let value = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
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
        let profileSlotIDs = Set(codexProfiles.map(\.slotID))
        let visibleRuntimeSlots = codexSlots.filter { $0.isActive || profileSlotIDs.contains($0.slotID) }
        var mergedBySlotID = Dictionary(uniqueKeysWithValues: visibleRuntimeSlots.map { ($0.slotID, $0) })

        for profile in codexProfiles where mergedBySlotID[profile.slotID] == nil {
            mergedBySlotID[profile.slotID] = placeholderCodexSlot(for: profile)
        }

        // 登录切换瞬间可能出现“旧 active 槽位 + 新 current profile 槽位”并存。
        // 这里把菜单展示的 active 状态统一收敛到单一槽位，避免短暂显示两张“使用中”卡。
        let preferredActiveSlotID = codexProfiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID

        var merged = mergedBySlotID.values.map { slot -> CodexAccountSlot in
            var updated = slot
            if let preferredActiveSlotID {
                updated.isActive = updated.slotID == preferredActiveSlotID
            }
            return updated
        }

        if preferredActiveSlotID == nil {
            let activeSlots = merged.filter(\.isActive)
            if activeSlots.count > 1 {
                let keep = activeSlots
                    .sorted { lhs, rhs in
                        if lhs.lastSeenAt != rhs.lastSeenAt {
                            return lhs.lastSeenAt > rhs.lastSeenAt
                        }
                        return lhs.slotID < rhs.slotID
                    }
                    .first?.slotID
                merged = merged.map { slot in
                    var updated = slot
                    updated.isActive = updated.slotID == keep
                    return updated
                }
            }
        }

        return merged
    }

    private func placeholderCodexSlot(for profile: CodexAccountProfile) -> CodexAccountSlot {
        let identity = CodexIdentity.from(profile: profile)
        return CodexAccountSlot(
            slotID: profile.slotID,
            accountKey: identity.identityKey,
            displayName: profile.displayName,
            lastSnapshot: placeholderCodexSnapshot(for: profile),
            lastSeenAt: profile.lastImportedAt,
            isActive: profile.isCurrentSystemAccount
        )
    }

    private func placeholderCodexSnapshot(for profile: CodexAccountProfile) -> UsageSnapshot {
        let identity = CodexIdentity.from(profile: profile)
        var rawMeta: [String: String] = [
            "codex.slotID": profile.slotID.rawValue,
            "codex.menuPlaceholder": "true",
            "codex.tenantKey": identity.tenantKey,
            "codex.principalKey": identity.principalKey,
            "codex.identityKey": identity.identityKey
        ]
        if let accountId = profile.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            rawMeta["codex.accountId"] = accountId
            rawMeta["codex.teamId"] = accountId
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
        guard let index = CodexAccountProfileStore.matchingIndex(for: snapshot, in: codexProfiles) else {
            return nil
        }
        return codexProfiles[index]
    }

    private func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        var copy = snapshot
        let fallbackProfile = claudeProfiles.first(where: { $0.isCurrentSystemAccount })
        let matchedProfile = matchedClaudeProfile(for: copy) ?? fallbackProfile

        if let accountId = matchedProfile?.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            copy.rawMeta["claude.accountId"] = accountId
        }
        if let fingerprint = matchedProfile?.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty,
           (copy.rawMeta["claude.credentialFingerprint"]?.isEmpty ?? true) {
            copy.rawMeta["claude.credentialFingerprint"] = fingerprint
        }
        if let configDir = matchedProfile?.configDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            copy.rawMeta["claude.configDir"] = configDir
        }
        if (copy.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let email = matchedProfile?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            copy.accountLabel = email
            copy.rawMeta["claude.accountLabel"] = email
        }

        let resolvedSlotID = preferredSlotID
            ?? matchedProfile?.slotID
            ?? claudeProfiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID

        let accountKey = ClaudeAccountSlotStore.accountKey(from: copy)
        let label = ClaudeAccountSlotStore.accountLabel(from: copy)
        if let resolvedSlotID {
            copy.rawMeta["claude.slotID"] = resolvedSlotID.rawValue
        }
        copy.rawMeta["claude.accountKey"] = accountKey
        copy.rawMeta["claude.accountLabel"] = label
        copy.rawMeta["claude.lastSeenAt"] = ISO8601DateFormatter().string(from: Date())
        copy.rawMeta["claude.isActive"] = isActive ? "true" : "false"
        if copy.accountLabel == nil || copy.accountLabel?.isEmpty == true {
            copy.accountLabel = label == "Unknown" ? nil : label
        }
        return copy
    }

    private func bootstrapClaudeProfileState() {
        if !didRunClaudeAutoCaptureCompaction {
            didRunClaudeAutoCaptureCompaction = true
            let compactionResult = claudeProfileStore.compactAutoCapturedProfiles(
                defaultConfigDir: claudeDesktopAuthService.currentSystemConfigDirectory(),
                currentFingerprint: claudeDesktopAuthService.currentCredentialFingerprint()
            )
            claudeProfiles = compactionResult.profiles
            removeClaudeSlotState(slotIDs: compactionResult.removedSlotIDs)
        }
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: true)
    }

    private func syncClaudeProfilesCurrentState(triggerPrefetchOnChange: Bool = true) {
        let previousProfileSetIdentity = claudeProfileSetIdentity(claudeProfiles)
        let latestProfiles = claudeProfileStore.captureCurrentCredentialsIfNeeded(
            credentialsJSON: claudeDesktopAuthService.currentCredentialsJSON(),
            defaultConfigDir: claudeDesktopAuthService.currentSystemConfigDirectory()
        )
        if latestProfiles != claudeProfiles {
            claudeProfiles = latestProfiles
        }

        let visibleSlotIDs = Set(latestProfiles.map(\.slotID))
        claudePrefetchAttemptedIdentity = claudePrefetchAttemptedIdentity.filter { visibleSlotIDs.contains($0.key) }
        claudePrefetchInFlightSlots = claudePrefetchInFlightSlots.intersection(visibleSlotIDs)
        claudeInactiveRefreshRetryState.prune(keeping: visibleSlotIDs)

        if triggerPrefetchOnChange,
           previousProfileSetIdentity != claudeProfileSetIdentity(latestProfiles) {
            triggerClaudeProfileSnapshotPrefetchIfNeeded()
        }
    }

    private func claudeMenuTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    private func refreshClaudeProfileCardsAfterManualRefresh(descriptor: ProviderDescriptor) async {
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
        let activeSlotIDs = Set(claudeSlots.filter(\.isActive).map(\.slotID))
        for profile in claudeProfiles.sorted(by: { $0.slotID < $1.slotID }) where !activeSlotIDs.contains(profile.slotID) {
            _ = await refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
        }
    }

    private func refreshClaudeProfileSnapshotSlot(
        _ profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> InactiveProfileRefreshResult {
        if claudePrefetchInFlightSlots.contains(profile.slotID) {
            return .skipped
        }
        claudePrefetchInFlightSlots.insert(profile.slotID)
        defer { claudePrefetchInFlightSlots.remove(profile.slotID) }

        guard let result = try? await claudeProfileSnapshotService.fetchSnapshot(
            profile: profile,
            descriptor: descriptor
        ) else {
            return .failed
        }

        if let refreshed = result.refreshedCredentialsJSON, !refreshed.isEmpty {
            _ = claudeProfileStore.updateStoredCredentials(
                slotID: profile.slotID,
                credentialsJSON: refreshed
            )
            syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
        }

        let snapshot = boundedSnapshot(
            markClaudeSnapshotActive(
                result.snapshot,
                preferredSlotID: profile.slotID,
                isActive: false
            )
        )
        claudeSlots = claudeSlotStore.upsertInactive(
            snapshot: snapshot,
            preferredSlotID: profile.slotID
        )
        return .success
    }

    private func triggerClaudeProfileSnapshotPrefetchIfNeeded() {
        guard let descriptor = config.providers.first(where: { $0.type == .claude && $0.family == .official }) else {
            return
        }

        let preferredActiveSlotID = claudeProfiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID
        let activeRuntimeSlotIDs = Set(claudeSlots.filter(\.isActive).map(\.slotID))
        let schedulingBudget = max(
            0,
            RuntimeDiagnosticsLimits.claudePrefetchMaxConcurrent - claudePrefetchInFlightSlots.count
        )
        let candidates = ClaudePrefetchPlanner.selectCandidates(
            profiles: claudeProfiles,
            preferredActiveSlotID: preferredActiveSlotID,
            activeRuntimeSlotIDs: activeRuntimeSlotIDs,
            inFlightSlots: claudePrefetchInFlightSlots,
            attemptedIdentity: claudePrefetchAttemptedIdentity,
            maxNewTasks: schedulingBudget
        )
        guard !candidates.isEmpty else {
            return
        }
        let profilesBySlotID = Dictionary(uniqueKeysWithValues: claudeProfiles.map { ($0.slotID, $0) })

        for candidate in candidates {
            guard let profile = profilesBySlotID[candidate.slotID] else {
                continue
            }
            claudePrefetchAttemptedIdentity[candidate.slotID] = candidate.identityKey

            Task { [weak self] in
                guard let self else { return }
                _ = await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
    }

    private func removeClaudeSlotState(slotIDs: [CodexSlotID]) {
        guard !slotIDs.isEmpty else { return }
        let uniqueSlotIDs = Array(Set(slotIDs)).sorted()
        for slotID in uniqueSlotIDs {
            claudeSlots = claudeSlotStore.remove(slotID: slotID)
            claudePrefetchAttemptedIdentity.removeValue(forKey: slotID)
            claudePrefetchInFlightSlots.remove(slotID)
            claudeInactiveRefreshRetryState.remove(slotID: slotID)
            claudeSwitchFeedback.removeValue(forKey: slotID)
        }
    }

    private func claudeProfileSetIdentity(_ profiles: [ClaudeAccountProfile]) -> [String] {
        profiles
            .map { profile in
                "\(profile.slotID.rawValue)|\(ClaudePrefetchPlanner.identityKey(for: profile))"
            }
            .sorted()
    }

    private func mergedClaudeSlotsForMenu() -> [ClaudeAccountSlot] {
        let profileSlotIDs = Set(claudeProfiles.map(\.slotID))
        let visibleRuntimeSlots = claudeSlots.filter { $0.isActive || profileSlotIDs.contains($0.slotID) }
        var mergedBySlotID = Dictionary(uniqueKeysWithValues: visibleRuntimeSlots.map { ($0.slotID, $0) })

        for profile in claudeProfiles where mergedBySlotID[profile.slotID] == nil {
            mergedBySlotID[profile.slotID] = placeholderClaudeSlot(for: profile)
        }

        let preferredActiveSlotID = claudeProfiles
            .filter(\.isCurrentSystemAccount)
            .sorted { lhs, rhs in
                if lhs.lastImportedAt != rhs.lastImportedAt {
                    return lhs.lastImportedAt > rhs.lastImportedAt
                }
                return lhs.slotID < rhs.slotID
            }
            .first?.slotID

        var merged = mergedBySlotID.values.map { slot -> ClaudeAccountSlot in
            var updated = slot
            if let preferredActiveSlotID {
                updated.isActive = updated.slotID == preferredActiveSlotID
            }
            return updated
        }

        if preferredActiveSlotID == nil {
            let activeSlots = merged.filter(\.isActive)
            if activeSlots.count > 1 {
                let keep = activeSlots
                    .sorted { lhs, rhs in
                        if lhs.lastSeenAt != rhs.lastSeenAt {
                            return lhs.lastSeenAt > rhs.lastSeenAt
                        }
                        return lhs.slotID < rhs.slotID
                    }
                    .first?.slotID
                merged = merged.map { slot in
                    var updated = slot
                    updated.isActive = updated.slotID == keep
                    return updated
                }
            }
        }

        return merged
    }

    private func placeholderClaudeSlot(for profile: ClaudeAccountProfile) -> ClaudeAccountSlot {
        ClaudeAccountSlot(
            slotID: profile.slotID,
            accountKey: profile.credentialFingerprint
                .map { "fingerprint:\($0.lowercased())" }
                ?? profile.accountEmail
                .map { "email:\($0.lowercased())" }
                ?? "profile:\(profile.slotID.rawValue.lowercased())",
            displayName: profile.displayName,
            lastSnapshot: placeholderClaudeSnapshot(for: profile),
            lastSeenAt: profile.lastImportedAt,
            isActive: profile.isCurrentSystemAccount
        )
    }

    private func placeholderClaudeSnapshot(for profile: ClaudeAccountProfile) -> UsageSnapshot {
        var rawMeta: [String: String] = [
            "claude.slotID": profile.slotID.rawValue,
            "claude.menuPlaceholder": "true"
        ]
        if let accountId = profile.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            rawMeta["claude.accountId"] = accountId
        }
        if let fingerprint = profile.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty {
            rawMeta["claude.credentialFingerprint"] = fingerprint
        }
        if let configDir = profile.configDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            rawMeta["claude.configDir"] = configDir
        }

        return UsageSnapshot(
            source: "claude-placeholder-\(profile.slotID.rawValue.lowercased())",
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
            sourceLabel: "Claude",
            accountLabel: profile.accountEmail,
            authSourceLabel: nil,
            diagnosticCode: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    private func setClaudeSwitchFeedback(_ feedback: ClaudeSwitchFeedback?, for slotID: CodexSlotID) {
        claudeFeedbackTasks[slotID]?.cancel()
        claudeFeedbackTasks.removeValue(forKey: slotID)

        guard let feedback else {
            claudeSwitchFeedback.removeValue(forKey: slotID)
            return
        }

        claudeSwitchFeedback[slotID] = feedback
        claudeFeedbackTasks[slotID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.claudeSwitchFeedback[slotID] == feedback {
                self.claudeSwitchFeedback.removeValue(forKey: slotID)
            }
            self.claudeFeedbackTasks.removeValue(forKey: slotID)
        }
    }

    private func matchedClaudeProfile(for slot: ClaudeAccountSlot) -> ClaudeAccountProfile? {
        matchedClaudeProfile(for: slot.lastSnapshot) ?? claudeProfiles.first(where: { $0.slotID == slot.slotID })
    }

    private func matchedClaudeProfile(for snapshot: UsageSnapshot) -> ClaudeAccountProfile? {
        guard let index = ClaudeAccountProfileStore.matchingIndex(for: snapshot, in: claudeProfiles) else {
            return nil
        }
        return claudeProfiles[index]
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
