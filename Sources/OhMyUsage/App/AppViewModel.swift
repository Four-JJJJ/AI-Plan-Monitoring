import AppKit
import OhMyUsageApplication
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppViewModel {
    static let statusBarDisplayConfigDidChangeNotification = Notification.Name("OhMyUsage.StatusBarDisplayConfigDidChange")

    private let keychain: KeychainService
    private let configurationRepository: any AppConfigurationRepositorying
    @ObservationIgnored private let credentialAccessService: CredentialAccessService
    private let thirdPartyBalanceBaselineStore = ThirdPartyBalanceBaselineStore()
    private let codexSlotStore: CodexAccountSlotStore
    private let codexProfileStore: CodexAccountProfileStore
    private let codexProfileSnapshotService = CodexProfileSnapshotService()
    private let codexDesktopAuthService: CodexDesktopAuthService
    private let codexDesktopAppService: CodexDesktopAppService
    private let oauthImportOrchestrator = OAuthImportOrchestrator()
    private let claudeSlotStore = ClaudeAccountSlotStore()
    private let claudeProfileStore = ClaudeAccountProfileStore()
    private let claudeProfileSnapshotService = ClaudeProfileSnapshotService()
    private let claudeDesktopAuthService = ClaudeDesktopAuthService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let notifications: NotificationService
    @ObservationIgnored private let localSessionSignalMonitor = LocalSessionCompletionSignalMonitor()
    private let providerFactory: any ProviderFactorying
    @ObservationIgnored private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator
    @ObservationIgnored private let localUsageHistoryRepository: LocalUsageHistoryRepository
    @ObservationIgnored private var refreshScheduler: ProviderRefreshScheduler?
    @ObservationIgnored private let providerRefreshCoordinator: AppProviderRefreshCoordinator
    @ObservationIgnored private let officialAccountImportCoordinator = AppOfficialAccountImportCoordinator()
    @ObservationIgnored private let officialAccountSwitchCoordinator = AppOfficialAccountSwitchCoordinator()
    @ObservationIgnored private let officialProfileLifecycleCoordinator = AppOfficialProfileLifecycleCoordinator()
    @ObservationIgnored private let officialProfileRefreshCoordinator = AppOfficialProfileRefreshCoordinator()
    @ObservationIgnored private let officialProfileDisplayCoordinator = AppOfficialProfileDisplayCoordinator()
    @ObservationIgnored private let officialProfileSyncCoordinator = AppOfficialProfileSyncCoordinator()
    @ObservationIgnored private let codexFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, CodexSwitchFeedback>()
    @ObservationIgnored private let claudeFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, ClaudeSwitchFeedback>()
    @ObservationIgnored private let officialProviderSettingsCoordinator = AppOfficialProviderSettingsCoordinator()
    @ObservationIgnored private let providerListMutationCoordinator = AppProviderListMutationCoordinator()
    @ObservationIgnored private let providerCredentialCoordinator = AppProviderCredentialCoordinator()
    @ObservationIgnored private let credentialLookupCoordinator = AppCredentialLookupCoordinator()
    @ObservationIgnored private let permissionCoordinator = AppPermissionCoordinator()
    @ObservationIgnored private let resetCoordinator = AppResetCoordinator()
    @ObservationIgnored private let relayProviderSettingsCoordinator = AppRelayProviderSettingsCoordinator()
    @ObservationIgnored private let relayDescriptorPreviewBuilder = RelayDescriptorPreviewBuilder()
    @ObservationIgnored private let statusBarPreferencesCoordinator = AppStatusBarPreferencesCoordinator()
    @ObservationIgnored private let configurationMutationCoordinator = AppConfigurationMutationCoordinator()
    @ObservationIgnored private let settingsPersistenceFeedbackCoordinator: AppSettingsPersistenceFeedbackCoordinator
    @ObservationIgnored private let localProviderDiscoveryCoordinator = LocalProviderDiscoveryCoordinator()
    @ObservationIgnored private let localUsageHistoryRefreshCoordinator = LocalUsageHistoryRefreshCoordinator()
    @ObservationIgnored private let codexOfficialProfileRefreshRuntime = CodexOfficialProfileRefreshRuntime()
    @ObservationIgnored private let claudeOfficialProfileRefreshRuntime = ClaudeOfficialProfileRefreshRuntime()
    @ObservationIgnored let updateCoordinator: AppUpdateCoordinator
    @ObservationIgnored private let codexSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
    @ObservationIgnored private let claudeSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
    private var sessionStore = AppSessionStore()

    private var settingsPersistenceStatus = SettingsPersistenceDisplayState(
        kind: .idle,
        statusText: nil,
        tone: .neutral
    )
    private(set) var settingsPersistenceErrorMessage: String?

    private(set) var config: AppConfig
    private(set) var snapshots: [String: UsageSnapshot] {
        get { sessionStore.providerState.snapshots }
        set { sessionStore.providerState.snapshots = newValue }
    }
    private(set) var codexSlots: [CodexAccountSlot] {
        get { sessionStore.accountState.codexSlots }
        set { sessionStore.accountState.codexSlots = newValue }
    }
    private(set) var codexProfiles: [CodexAccountProfile] {
        get { sessionStore.accountState.codexProfiles }
        set { sessionStore.accountState.codexProfiles = newValue }
    }
    private(set) var codexSwitchFeedback: [CodexSlotID: CodexSwitchFeedback] {
        get { sessionStore.accountState.codexSwitchFeedback }
        set { sessionStore.accountState.codexSwitchFeedback = newValue }
    }
    private(set) var codexOAuthImportState: OAuthImportState? {
        get { sessionStore.accountState.codexOAuthImportState }
        set { sessionStore.accountState.codexOAuthImportState = newValue }
    }
    private(set) var claudeSlots: [ClaudeAccountSlot] {
        get { sessionStore.accountState.claudeSlots }
        set { sessionStore.accountState.claudeSlots = newValue }
    }
    private(set) var claudeProfiles: [ClaudeAccountProfile] {
        get { sessionStore.accountState.claudeProfiles }
        set { sessionStore.accountState.claudeProfiles = newValue }
    }
    private(set) var claudeSwitchFeedback: [CodexSlotID: ClaudeSwitchFeedback] {
        get { sessionStore.accountState.claudeSwitchFeedback }
        set { sessionStore.accountState.claudeSwitchFeedback = newValue }
    }
    private(set) var claudeOAuthImportState: OAuthImportState? {
        get { sessionStore.accountState.claudeOAuthImportState }
        set { sessionStore.accountState.claudeOAuthImportState = newValue }
    }
    private(set) var errors: [String: String] {
        get { sessionStore.providerState.errors }
        set { sessionStore.providerState.errors = newValue }
    }
    private(set) var lastUpdatedAt: Date? {
        get { sessionStore.providerState.lastUpdatedAt }
        set { sessionStore.providerState.lastUpdatedAt = newValue }
    }
    private(set) var notificationAuthorizationStatus: UNAuthorizationStatus {
        get { sessionStore.permissionState.notificationAuthorizationStatus }
        set { sessionStore.permissionState.notificationAuthorizationStatus = newValue }
    }
    private(set) var secureStorageReady: Bool {
        get { sessionStore.permissionState.secureStorageReady }
        set { sessionStore.permissionState.secureStorageReady = newValue }
    }
    private(set) var fullDiskAccessGranted: Bool {
        get { sessionStore.permissionState.fullDiskAccessGranted }
        set { sessionStore.permissionState.fullDiskAccessGranted = newValue }
    }
    private(set) var fullDiskAccessRelevant: Bool {
        get { sessionStore.permissionState.fullDiskAccessRelevant }
        set { sessionStore.permissionState.fullDiskAccessRelevant = newValue }
    }
    private(set) var fullDiskAccessRequested: Bool {
        get { sessionStore.permissionState.fullDiskAccessRequested }
        set { sessionStore.permissionState.fullDiskAccessRequested = newValue }
    }
    private(set) var currentAppVersion: String {
        get { sessionStore.updateState.currentAppVersion }
        set { sessionStore.updateState.currentAppVersion = newValue }
    }
    private(set) var availableUpdate: AppUpdateInfo? {
        get { sessionStore.updateState.availableUpdate }
        set { sessionStore.updateState.availableUpdate = newValue }
    }
    private(set) var lastUpdateCheckAt: Date? {
        get { sessionStore.updateState.lastUpdateCheckAt }
        set { sessionStore.updateState.lastUpdateCheckAt = newValue }
    }
    private(set) var updateCheckInFlight: Bool {
        get { sessionStore.updateState.updateCheckInFlight }
        set { sessionStore.updateState.updateCheckInFlight = newValue }
    }
    private(set) var lastCheckedLatestVersion: String? {
        get { sessionStore.updateState.lastCheckedLatestVersion }
        set { sessionStore.updateState.lastCheckedLatestVersion = newValue }
    }
    private(set) var updateCheckErrorMessage: String? {
        get { sessionStore.updateState.updateCheckErrorMessage }
        set { sessionStore.updateState.updateCheckErrorMessage = newValue }
    }
    private(set) var updateDownloadInFlight: Bool {
        get { sessionStore.updateState.updateDownloadInFlight }
        set { sessionStore.updateState.updateDownloadInFlight = newValue }
    }
    private(set) var updateInstallBufferingInFlight: Bool {
        get { sessionStore.updateState.updateInstallBufferingInFlight }
        set { sessionStore.updateState.updateInstallBufferingInFlight = newValue }
    }
    private(set) var updateInstallationInFlight: Bool {
        get { sessionStore.updateState.updateInstallationInFlight }
        set { sessionStore.updateState.updateInstallationInFlight = newValue }
    }
    private(set) var updatePreparedVersion: String? {
        get { sessionStore.updateState.updatePreparedVersion }
        set { sessionStore.updateState.updatePreparedVersion = newValue }
    }
    private(set) var updateInstallErrorMessage: String? {
        get { sessionStore.updateState.updateInstallErrorMessage }
        set { sessionStore.updateState.updateInstallErrorMessage = newValue }
    }
    private(set) var localUsageHistoryVersion: Int {
        get { sessionStore.providerState.localUsageHistoryVersion }
        set { sessionStore.providerState.localUsageHistoryVersion = newValue }
    }
    private(set) var menuPanelVisible: Bool {
        get { sessionStore.menuPanelVisible }
        set { sessionStore.menuPanelVisible = newValue }
    }
    private(set) var settingsWindowVisible: Bool {
        get { sessionStore.settingsWindowVisible }
        set { sessionStore.settingsWindowVisible = newValue }
    }
    var updateStateStorage: UpdateStore {
        get { sessionStore.updateState }
        set { sessionStore.updateState = newValue }
    }

    private var codexOAuthImportTask: Task<Void, Never>?
    private var claudeOAuthImportTask: Task<Void, Never>?
    private var didRunClaudeAutoCaptureCompaction = false
    private var notificationPermissionPollingTask: Task<Void, Never>?
    @ObservationIgnored private var permissionRefreshTask: Task<Void, Never>?
    private(set) var credentialLookupVersion: Int {
        get { sessionStore.credentialLookupVersion }
        set { sessionStore.credentialLookupVersion = newValue }
    }
    private var consecutiveFailures: [String: Int] {
        get { sessionStore.providerState.consecutiveFailures }
        set { sessionStore.providerState.consecutiveFailures = newValue }
    }
    private var activeAlerts: Set<String> {
        get { sessionStore.providerState.activeAlerts }
        set { sessionStore.providerState.activeAlerts = newValue }
    }
    private var thirdPartyBalanceBaselineTracker: ThirdPartyBalanceBaselineTracker {
        get { sessionStore.providerState.thirdPartyBalanceBaselineTracker }
        set { sessionStore.providerState.thirdPartyBalanceBaselineTracker = newValue }
    }
    private var hasStarted: Bool {
        get { sessionStore.hasStarted }
        set { sessionStore.hasStarted = newValue }
    }
    private var lastPermissionStatusRefreshAt: Date {
        get { sessionStore.permissionState.lastPermissionStatusRefreshAt }
        set { sessionStore.permissionState.lastPermissionStatusRefreshAt = newValue }
    }
    private var preparedUpdate: PreparedAppUpdate? {
        get { sessionStore.updateState.preparedUpdate }
        set { sessionStore.updateState.preparedUpdate = newValue }
    }
    private var preparedUpdateInfo: AppUpdateInfo? {
        get { sessionStore.updateState.preparedUpdateInfo }
        set { sessionStore.updateState.preparedUpdateInfo = newValue }
    }
    private var updateFlowVersionInFlight: String? {
        get { sessionStore.updateState.updateFlowVersionInFlight }
        set { sessionStore.updateState.updateFlowVersionInFlight = newValue }
    }

    init(
        configurationRepository: any AppConfigurationRepositorying = AppConfigurationRepository(),
        appUpdateService: any AppUpdateServicing = AppUpdateService(),
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        self.keychain = keychain
        self.configurationRepository = configurationRepository
        self.credentialAccessService = CredentialAccessService(keychain: keychain)
        self.codexSlotStore = codexSlotStore
        self.codexProfileStore = codexProfileStore
        self.codexDesktopAuthService = codexDesktopAuthService
        self.codexDesktopAppService = codexDesktopAppService
        self.notifications = notificationService
        self.providerRefreshCoordinator = AppProviderRefreshCoordinator(
            providerFactory: providerFactory ?? ProviderFactory(keychain: keychain),
            notifications: notificationService
        )
        self.updateCoordinator = AppUpdateCoordinator(
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
        )
        self.settingsPersistenceFeedbackCoordinator = AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        let shouldPersistConfigDuringBootstrap: Bool
        var loadedConfig: AppConfig
        do {
            loadedConfig = try configurationRepository.load()
            shouldPersistConfigDuringBootstrap = !configurationRepository.lastLoadWasLossy
        } catch {
            loadedConfig = .default
            shouldPersistConfigDuringBootstrap = false
        }
        self.config = loadedConfig
        self.providerFactory = providerFactory ?? ProviderFactory(keychain: keychain)
        self.localUsageHistoryRepository = localUsageHistoryRepository
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.refreshScheduler = makeRefreshScheduler()
        self.currentAppVersion = AppVersionResolver.detectCurrentAppVersion()
        self.codexSlots = codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        thirdPartyBalanceBaselineTracker.restore(entries: thirdPartyBalanceBaselineStore.load())
        let preNormalizedConfig = self.config
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        if shouldPersistConfigDuringBootstrap && self.config != preNormalizedConfig {
            _ = configurationRepository.saveDuringBootstrapResult(self.config)
        }
        launchAtLoginService.migrateLegacyLaunchAgentsIfNeeded()
        let launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
            self.config.launchAtLoginEnabled = launchAtLoginEnabled
            if shouldPersistConfigDuringBootstrap {
                _ = configurationRepository.saveDuringBootstrapResult(self.config)
            }
        }
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        restorePersistedOfficialProvidersIfNeeded()
        refreshPermissionStatuses(force: true)
    }

#if DEBUG
    init(
        testingConfig: AppConfig = .default,
        testingCurrentAppVersion: String = "0.0.0",
        configurationRepository: any AppConfigurationRepositorying = AppViewModel.makeTestingConfigurationRepository(),
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        self.keychain = keychain
        self.configurationRepository = configurationRepository
        self.credentialAccessService = CredentialAccessService(keychain: keychain)
        self.codexSlotStore = codexSlotStore
        self.codexProfileStore = codexProfileStore
        self.codexDesktopAuthService = codexDesktopAuthService
        self.codexDesktopAppService = codexDesktopAppService
        self.notifications = notificationService
        self.providerRefreshCoordinator = AppProviderRefreshCoordinator(
            providerFactory: providerFactory ?? ProviderFactory(keychain: keychain),
            notifications: notificationService
        )
        self.updateCoordinator = AppUpdateCoordinator(
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
        )
        self.settingsPersistenceFeedbackCoordinator = AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        self.config = testingConfig.migratedWithSiteDefaults()
        self.providerFactory = providerFactory ?? ProviderFactory(keychain: keychain)
        self.localUsageHistoryRepository = localUsageHistoryRepository
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.refreshScheduler = makeRefreshScheduler()
        self.currentAppVersion = testingCurrentAppVersion
        self.codexSlots = codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        restorePersistedOfficialProvidersIfNeeded()
    }

    private static func makeTestingConfigurationRepository() -> AppConfigurationRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppConfigurationRepository(store: ConfigStore(baseDirectoryURL: root))
    }
#endif

    private func makeRefreshScheduler() -> ProviderRefreshScheduler {
        ProviderRefreshScheduler(
            descriptorProvider: { [weak self] providerID in
                guard let descriptor = self?.descriptor(for: providerID) else {
                    return nil
                }
                return self?.providerRefreshCoordinator.refreshScheduleDescriptor(for: descriptor)
            },
            providersProvider: { [weak self] in
                self?.providerRefreshCoordinator.refreshScheduleDescriptors(from: self?.config.providers ?? []) ?? []
            },
            activeProviderIDsProvider: { [weak self] in
                Set(self?.statusBarProvidersForDisplay().map(\.id) ?? [])
            },
            failureCountProvider: { [weak self] providerID in
                self?.consecutiveFailures[providerID, default: 0] ?? 0
            },
            refreshAction: { [weak self] providerID, forceRefresh in
                guard let descriptor = self?.descriptor(for: providerID) else { return }
                await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            config: config.resourceMode.refreshSchedulerConfig
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissionStatuses(force: true)
        restartPolling()
        refreshDisplayedStatusBarProviders()
    }

    func restartPolling() {
        refreshScheduler?.restart(
            providers: providerRefreshCoordinator.refreshScheduleDescriptors(from: config.providers)
        )
    }

    func refreshNow() {
        refreshScheduler?.refreshNow(
            providers: providerRefreshCoordinator.refreshScheduleDescriptors(from: config.providers)
        )
    }

    func setMenuPanelVisible(_ visible: Bool) {
        guard menuPanelVisible != visible else { return }
        menuPanelVisible = visible
    }

    func setSettingsWindowVisible(_ visible: Bool) {
        guard settingsWindowVisible != visible else { return }
        settingsWindowVisible = visible
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

    var language: AppLanguage {
        config.language
    }

    var resourceMode: ResourceMode {
        config.resourceMode
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

    var globalRefreshIntervalSeconds: Int {
        let intervals = Set(config.providers.map(\.pollIntervalSec))
        if intervals.count == 1, let value = intervals.first {
            return value
        }

        for candidate in [15, 30, 60, 300] {
            if intervals.contains(candidate) {
                return candidate
            }
        }
        return 60
    }

    var showOfficialAccountEmailInMenuBar: Bool {
        config.showOfficialAccountEmailInMenuBar
    }

    var claudeStatusBarDisplaySlotID: CodexSlotID? {
        config.claudeStatusBarDisplaySlotID
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
        return AppPermissionCoordinator.shouldShowPermissionGuide(
            hasEnabledProviders: hasEnabledProviders,
            hasPersistedOfficialMonitoringState: hasPersistedOfficialMonitoringState,
            hasNotificationPermission: hasNotificationPermission,
            secureStorageReady: secureStorageReady,
            fullDiskAccessRelevant: fullDiskAccessRelevant,
            fullDiskAccessRequested: fullDiskAccessRequested,
            fullDiskAccessGranted: fullDiskAccessGranted
        )
    }

    var canRunLocalDiscoveryFromOnboarding: Bool {
        guard secureStorageReady else { return false }
        if fullDiskAccessRelevant || fullDiskAccessRequested {
            return fullDiskAccessGranted
        }
        return true
    }

    func setLanguage(_ language: AppLanguage) {
        guard let outcome = configurationMutationCoordinator.setLanguage(
            language,
            config: &config,
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        applyConfigurationPersistenceOutcome(outcome)
    }

    func setResourceMode(_ resourceMode: ResourceMode) {
        guard let outcome = configurationMutationCoordinator.setResourceMode(
            resourceMode,
            config: &config,
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        if applyConfigurationPersistenceOutcome(outcome) {
            refreshScheduler = makeRefreshScheduler()
            restartPolling()
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard let outcome = configurationMutationCoordinator.setLaunchAtLoginEnabled(
            enabled,
            config: &config,
            setLaunchAtLogin: { try launchAtLoginService.setEnabled($0) },
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        if let persistence = outcome.persistence {
            _ = applyConfigurationPersistenceOutcome(persistence)
        }
        if let errorMessage = outcome.errorMessage {
            errors["launch-at-login"] = errorMessage
        }
    }

    func isStatusBarProvider(providerID: String) -> Bool {
        guard config.providers.first(where: { $0.id == providerID })?.showsInMenuBar == true else {
            return false
        }
        if config.statusBarMultiUsageEnabled {
            return config.statusBarMultiProviderIDs.contains(providerID)
        }
        return config.statusBarProviderID == providerID
    }

    func setStatusBarMultiUsageEnabled(_ enabled: Bool) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarMultiUsageEnabled(
            enabled,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarDisplayStyle(_ style: StatusBarDisplayStyle) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayStyle(
            style,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarAppearanceMode(_ mode: StatusBarAppearanceMode) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarAppearanceMode(
            mode,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setGlobalRefreshIntervalSeconds(_ seconds: Int) {
        let supported = [15, 30, 60, 300]
        let normalized = supported.contains(seconds) ? seconds : 60
        guard config.providers.contains(where: { $0.pollIntervalSec != normalized }) else { return }

        for index in config.providers.indices {
            config.providers[index].pollIntervalSec = normalized
        }

        if persistConfiguration(showFeedback: true) {
            restartPolling()
        }
    }

    func setStatusBarDisplayEnabled(_ enabled: Bool, providerID: String) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayEnabled(
            enabled,
            providerID: providerID,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarProvider(providerID: String?) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarProvider(
            providerID: providerID,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        let outcome = statusBarPreferencesCoordinator.setShowOfficialAccountEmailInMenuBar(
            enabled,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
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
        let outcome = statusBarPreferencesCoordinator.setShowOfficialPlanTypeInMenuBar(
            enabled,
            providerID: providerID,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func claudeStatusBarResolvedDisplaySlotID() -> CodexSlotID? {
        resolvedClaudeStatusBarDisplaySlotID()
    }

    func isClaudeStatusBarDisplaySlot(slotID: CodexSlotID) -> Bool {
        resolvedClaudeStatusBarDisplaySlotID() == slotID
    }

    func setClaudeStatusBarDisplaySlotID(_ slotID: CodexSlotID?) {
        let selectionOutcome = officialProfileDisplayCoordinator.updateClaudeStatusBarDisplaySelection(
            requestedSlotID: slotID,
            configuredSlotID: config.claudeStatusBarDisplaySlotID,
            profiles: claudeProfiles,
            slots: claudeSlots
        )
        guard selectionOutcome.shouldPersist else {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(
                slotID: selectionOutcome.resolvedDisplaySlotID
            )
            return
        }
        config.claudeStatusBarDisplaySlotID = selectionOutcome.normalizedConfiguredSlotID
        normalizeStatusBarSelections()
        _ = persistConfiguration(showFeedback: true)
        triggerClaudeStatusBarDisplayPrefetchIfNeeded(
            slotID: selectionOutcome.resolvedDisplaySlotID
        )
        if selectionOutcome.shouldNotify {
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func statusBarProvider() -> ProviderDescriptor? {
        if let id = config.statusBarProviderID,
           let selected = config.providers.first(where: { $0.id == id && $0.enabled && $0.showsInMenuBar }) {
            return selected
        }
        guard let fallbackID = AppConfig.defaultStatusBarProviderID(from: config.providers) else {
            return nil
        }
        return config.providers.first(where: { $0.id == fallbackID && $0.enabled && $0.showsInMenuBar })
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
            guard let provider = providersByID[id], provider.enabled, provider.showsInMenuBar else { return nil }
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
            codexPrefetchAttemptedIdentityCount: codexOfficialProfileRefreshRuntime.attemptedIdentityCount,
            codexPrefetchInFlightCount: codexOfficialProfileRefreshRuntime.inFlightCount,
            claudePrefetchAttemptedIdentityCount: claudeOfficialProfileRefreshRuntime.attemptedIdentityCount,
            claudePrefetchInFlightCount: claudeOfficialProfileRefreshRuntime.inFlightCount,
            pollTaskCount: refreshScheduler?.pollTaskCount ?? 0,
            enabledProviderCount: config.providers.filter(\.enabled).count,
            providerErrorCount: errors.count,
            consecutiveFailureTotal: consecutiveFailures.values.reduce(0, +)
        )
    }

    struct SettingsPersistenceDisplayState: Equatable {
        enum Kind: Equatable {
            case idle
            case saved
            case failed
        }

        var kind: Kind
        var statusText: String?
        var tone: UpdateDisplayTone
    }

    var settingsPersistenceDisplayState: SettingsPersistenceDisplayState {
        settingsPersistenceStatus
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
            if let task = officialAccountImportCoordinator.startCodexImport(
                slotID: slotID,
                currentTask: codexOAuthImportTask,
                currentState: { self.codexOAuthImportState },
                importAccount: { [oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    self.codexProfileStore.matchingProfile(authJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Codex \(resolvedSlotID.rawValue)"
                    let detail = self.saveCodexProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        authJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { self.codexOAuthImportState = $0 },
                clearTask: { self.codexOAuthImportTask = nil }
            ) {
                codexOAuthImportTask = task
            }
        case .claude:
            if let task = officialAccountImportCoordinator.startClaudeImport(
                slotID: slotID,
                currentTask: claudeOAuthImportTask,
                currentState: { self.claudeOAuthImportState },
                importAccount: { [oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    self.claudeProfileStore.matchingProfile(credentialsJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Claude \(resolvedSlotID.rawValue)"
                    let detail = self.saveClaudeProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        source: .manualCredentials,
                        configDir: existing?.configDir,
                        credentialsJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { self.claudeOAuthImportState = $0 },
                clearTask: { self.claudeOAuthImportTask = nil }
            ) {
                claudeOAuthImportTask = task
            }
        default:
            return
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
            activateOfficialProviderAfterProfileSave(type: .codex)
            return text(.codexProfileImported)
        } catch {
            return "\(text(.codexProfileImportFailed)): \(error.localizedDescription)"
        }
    }

    func removeCodexProfile(slotID: CodexSlotID) {
        syncCodexProfilesCurrentState()
        codexProfiles = codexProfileStore.removeProfile(slotID: slotID)
        codexSlots = codexSlotStore.remove(slotID: slotID)
        codexOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setCodexSwitchFeedback(nil, for: slotID)
    }

    func claudeSlotViewModels() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func claudeSlotViewModelsForSettings() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func claudeProfilesForSettings() -> [ClaudeAccountProfile] {
        claudeDisplayableProfiles()
    }

    func refreshSettingsProfileState() {
        syncCodexProfilesCurrentState()
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
    }

    func localUsageHistoryState(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        _ = localUsageHistoryVersion
        return localUsageHistoryRepository.snapshot(for: query)
    }

    func refreshLocalUsageHistoryIfNeeded(
        query: LocalUsageHistoryQuery,
        codexIdentity: CodexTrendIdentityContext? = nil,
        claudeCurrentConfigDir: String? = nil,
        claudeAllConfigDirs: [String] = [],
        force: Bool = false
    ) {
        localUsageHistoryRefreshCoordinator.refreshLocalUsageHistoryIfNeeded(
            query: query,
            repository: localUsageHistoryRepository,
            codexIdentity: codexIdentity,
            claudeCurrentConfigDir: claudeCurrentConfigDir,
            claudeAllConfigDirs: claudeAllConfigDirs,
            force: force
        ) { [weak self] in
            self?.localUsageHistoryVersion += 1
        }
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
            officialProfileLifecycleCoordinator.scheduleCodexPrefetchIfNeeded(
                descriptor: config.providers.first(where: { $0.type == .codex && $0.family == .official }),
                profiles: codexProfiles,
                slots: codexSlots,
                runtime: codexOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        return AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: codexProfiles,
            slots: codexSlots,
            feedbackBySlotID: codexSwitchFeedback,
            isSwitching: { self.codexSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.codexMenuTitle(for: $0) }
        )
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
            officialProfileLifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
                descriptor: claudeOfficialProviderDescriptor(),
                profiles: claudeDisplayableProfiles(),
                slots: claudeSlots,
                runtime: claudeOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        return AppOfficialProfileMenuPresenter.claudeSlotViewModels(
            profiles: claudeProfiles,
            slots: claudeSlots,
            feedbackBySlotID: claudeSwitchFeedback,
            isSwitching: { self.claudeSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.claudeMenuTitle(for: $0) }
        )
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
            if try claudeProfileStore.updateProfileMetadataIfCredentialInputsUnchanged(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON
            ) != nil {
                syncClaudeProfilesCurrentState()
                return localizedText("Claude 账号备注已更新", "Claude profile note updated")
            }

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
        let previousConfiguredDisplaySlotID = config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        syncClaudeProfilesCurrentState()
        claudeProfiles = claudeProfileStore.removeProfile(slotID: slotID)
        claudeSlots = claudeSlotStore.remove(slotID: slotID)
        claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setClaudeSwitchFeedback(nil, for: slotID)
        normalizeStatusBarSelections()
        if config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = persistConfiguration(showFeedback: false)
        }
        let resolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func requestNotificationPermission() {
        notificationPermissionPollingTask?.cancel()
        notificationPermissionPollingTask = permissionCoordinator.requestNotificationPermission(
            requestPermissionIfNeeded: { notifications.requestPermissionIfNeeded() },
            fetchNotificationAuthorizationStatus: { await self.notifications.authorizationStatus() },
            updateNotificationAuthorizationStatus: { self.notificationAuthorizationStatus = $0 },
            refreshPermissionStatuses: { self.refreshPermissionStatuses(force: true) }
        )
    }

    @discardableResult
    func prepareSecureStorageAccess() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show(viewModel: self)
        let ok = keychain.prepareSecureStoreAccess()
        if ok {
            invalidateCredentialLookupCache()
        }
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
        resetCoordinator.resetLocalAppData(
            using: AppResetCoordinator.ResetHooks(
                stopPollingAndTransientTasks: {
                    self.notificationPermissionPollingTask?.cancel()
                    self.notificationPermissionPollingTask = nil
                    self.refreshScheduler?.stop()
                    self.codexFeedbackCoordinator.cancelAll()
                    self.codexOAuthImportTask?.cancel()
                    self.codexOAuthImportTask = nil
                    self.claudeFeedbackCoordinator.cancelAll()
                    self.claudeOAuthImportTask?.cancel()
                    self.claudeOAuthImportTask = nil
                },
                cancelOAuthImports: {
                    Task { await self.oauthImportOrchestrator.cancelImport(provider: .codex) }
                    Task { await self.oauthImportOrchestrator.cancelImport(provider: .claude) }
                },
                resetRuntimeComponents: {
                    self.codexSwitchCoordinator.reset()
                    self.codexOfficialProfileRefreshRuntime.reset()
                    self.codexSwitchFeedback.removeAll()
                    self.codexOAuthImportState = nil
                    self.claudeSwitchCoordinator.reset()
                    self.claudeOfficialProfileRefreshRuntime.reset()
                    self.didRunClaudeAutoCaptureCompaction = false
                    self.claudeSwitchFeedback.removeAll()
                    self.claudeOAuthImportState = nil
                },
                clearInMemoryState: {
                    self.snapshots.removeAll()
                    self.errors.removeAll()
                    self.consecutiveFailures.removeAll()
                    self.activeAlerts.removeAll()
                    self.thirdPartyBalanceBaselineTracker.removeAll()
                    self.thirdPartyBalanceBaselineStore.reset()
                    self.lastUpdatedAt = nil
                },
                resetPersistentState: {
                    self.launchAtLoginService.reset()
                    self.credentialAccessService.resetAllStoredCredentials()
                    self.codexProfileStore.reset()
                    self.codexSlotStore.reset()
                    self.claudeProfileStore.reset()
                    self.claudeSlotStore.reset()
                    _ = self.resetConfiguration(showFeedback: true)
                },
                restoreDefaultState: {
                    self.config = .default
                    self.codexSlots = []
                    self.codexProfiles = []
                    self.claudeSlots = []
                    self.claudeProfiles = []
                    self.syncCodexProfilesCurrentState()
                    self.bootstrapClaudeProfileState()
                    self.notificationAuthorizationStatus = .notDetermined
                    self.secureStorageReady = false
                    self.fullDiskAccessGranted = false
                    self.fullDiskAccessRelevant = false
                    self.fullDiskAccessRequested = false
                    self.lastPermissionStatusRefreshAt = .distantPast
                    self.hasStarted = false
                },
                rebootstrap: {
                    self.start()
                    self.refreshPermissionStatuses(force: true)
                }
            )
        )
    }

    func discoverLocalProviders() async -> String {
        let candidates = config.providers.filter { $0.family == .official }
        return await localProviderDiscoveryCoordinator.discoverLocalProviders(
            candidates: candidates,
            makeProvider: { self.providerFactory.makeProvider(for: $0) },
            handleFetchedSnapshot: { descriptor, fetched in
                if descriptor.type == .codex {
                    let snapshot = self.markCodexSnapshotActive(fetched)
                    self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                    self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                } else if descriptor.type == .claude {
                    let snapshot = self.markClaudeSnapshotActive(fetched)
                    self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                    self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                } else {
                    self.snapshots[descriptor.id] = self.boundedSnapshot(fetched)
                }
            },
            clearProviderError: { self.errors.removeValue(forKey: $0) },
            clearProviderFailures: { self.consecutiveFailures[$0] = 0 },
            markLastUpdatedAt: { self.lastUpdatedAt = $0 },
            setProviderEnabled: { providerID in
                if let index = self.config.providers.firstIndex(where: { $0.id == providerID }) {
                    self.config.providers[index].enabled = true
                }
            },
            normalizeStatusBarSelections: { self.normalizeStatusBarSelections() },
            persistConfiguration: { self.persistConfiguration(showFeedback: false) },
            restartPolling: { self.restartPolling() },
            notifyStatusBarDisplayConfigChanged: { self.notifyStatusBarDisplayConfigChanged() },
            displayNameForDiscovery: { self.displayNameForDiscovery($0) },
            nothingFoundText: text(.localDiscoveryNothingFound),
            language: config.language
        )
    }

    func switchCodexProfile(slotID: CodexSlotID) async {
        syncCodexProfilesCurrentState()
        await officialAccountSwitchCoordinator.switchCodexProfile(
            slotID: slotID,
            transactionCoordinator: codexSwitchCoordinator,
            prepare: { [self] in
                guard let profile = self.codexProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(message: self.text(.codexProfileMissing))
                }
                return profile
            },
            apply: { [self] profile in
                try self.codexDesktopAuthService.applyProfile(profile)
            },
            restart: { [self] _ in
                await self.codexDesktopAppService.restartIfRunning()
            },
            verify: { [self] _ in
                self.syncCodexProfilesCurrentState()
                guard let descriptor = self.config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
                    return .none
                }
                let provider = self.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = self.markCodexSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { [self] descriptor, snapshot in
                self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                self.errors.removeValue(forKey: descriptor.id)
                self.consecutiveFailures[descriptor.id] = 0
                self.lastUpdatedAt = Date()
                self.notifyStatusBarDisplayConfigChanged()
            },
            successMessage: { restartResult in
                self.codexSwitchMessage(
                    for: restartResult,
                    successKey: .codexSwitchSuccess
                )
            },
            setFeedback: { feedback, slotID in
                self.setCodexSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                self.errors[descriptor.id] = message
            },
            notify: { message in
                self.notifications.notify(
                    title: "Codex",
                    body: message,
                    identifier: "codex-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(self.text(.codexSwitchFailed)): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(self.text(.codexSwitchNeedsVerification)): \(error.localizedDescription)"
            }
        )
    }

    func switchClaudeProfile(slotID: CodexSlotID) async {
        syncClaudeProfilesCurrentState()
        await officialAccountSwitchCoordinator.switchClaudeProfile(
            slotID: slotID,
            transactionCoordinator: claudeSwitchCoordinator,
            prepare: { [self] in
                guard let profile = self.claudeProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(
                        message: self.localizedText("该槽位还没有导入可切换的 Claude 账号", "No imported Claude profile is available for this slot")
                    )
                }
                return profile
            },
            apply: { [self] profile in
                let credentialsJSON = try self.claudeProfileStore.resolvedCredentialsJSON(for: profile)
                try self.claudeDesktopAuthService.applyCredentialsJSON(credentialsJSON)
            },
            restart: { _ in () },
            verify: { [self] _ in
                self.syncClaudeProfilesCurrentState()
                guard let descriptor = self.config.providers.first(where: { $0.type == .claude && $0.family == .official }) else {
                    return .none
                }
                let provider = self.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = self.markClaudeSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { [self] descriptor, snapshot in
                self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                self.errors.removeValue(forKey: descriptor.id)
                self.consecutiveFailures[descriptor.id] = 0
                self.lastUpdatedAt = Date()
                self.notifyStatusBarDisplayConfigChanged()
            },
            verifiedSuccessMessage: self.localizedText("已切换 Claude 账号", "Claude account switched"),
            localSuccessMessage: self.localizedText("已写入本机 Claude 登录", "Local Claude credentials updated"),
            setFeedback: { feedback, slotID in
                self.setClaudeSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                self.errors[descriptor.id] = message
            },
            notify: { message in
                self.notifications.notify(
                    title: "Claude",
                    body: message,
                    identifier: "claude-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(self.localizedText("切换失败", "Switch failed")): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(self.localizedText("已切换到该账号，但需要重新验证", "Switched to this account, but re-verification is required")): \(error.localizedDescription)"
            }
        )
    }

    private func refreshPermissionStatuses(force: Bool) {
        if !force, Date().timeIntervalSince(lastPermissionStatusRefreshAt) < 5 {
            return
        }
        lastPermissionStatusRefreshAt = Date()
        permissionRefreshTask?.cancel()
        let previousSecureStorageReady = secureStorageReady
        permissionRefreshTask = permissionCoordinator.refreshPermissionStatuses(
            checkSecureStorageReady: {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        continuation.resume(returning: self.keychain.isSecureStoreReady())
                    }
                }
            },
            fetchNotificationAuthorizationStatus: { await self.notifications.authorizationStatus() },
            previousSecureStorageReady: previousSecureStorageReady,
            updateSecureStorageReady: { self.secureStorageReady = $0 },
            onSecureStorageBecameReady: { self.invalidateCredentialLookupCache() },
            applyFullDiskProbe: { granted, relevant in
                self.fullDiskAccessGranted = granted
                self.fullDiskAccessRelevant = relevant
            },
            updateNotificationAuthorizationStatus: { self.notificationAuthorizationStatus = $0 }
        )
    }

    func setEnabled(_ enabled: Bool, providerID: String) {
        let outcome = providerListMutationCoordinator.setEnabled(
            enabled,
            providerID: providerID,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func reorderEnabledProviders(
        family: ProviderFamily,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let outcome = providerListMutationCoordinator.reorderEnabledProviders(
            family: family,
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func setLowThreshold(_ value: Double, providerID: String) {
        commitProviderThreshold(value, providerID: providerID)
    }

    func commitProviderThreshold(_ value: Double, providerID: String) {
        let outcome = providerListMutationCoordinator.commitThreshold(
            value,
            providerID: providerID,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        credentialLookupCoordinator.credentialExists(
            for: descriptor,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? {
        credentialLookupCoordinator.savedCredentialLength(
            for: descriptor,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func hasToken(auth: AuthConfig) -> Bool {
        credentialLookupCoordinator.credentialExists(
            auth: auth,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        credentialLookupCoordinator.savedCredentialLength(
            auth: auth,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            descriptor: descriptor,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let ok = saveToken(token, for: descriptor)
        if ok {
            restartPolling()
        }
        return ok
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            auth: auth,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, auth: AuthConfig) -> Bool {
        let ok = saveToken(token, auth: auth)
        if ok {
            restartPolling()
        }
        return ok
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        credentialLookupCoordinator.manualCookieExists(
            for: provider,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        credentialLookupCoordinator.savedManualCookieLength(
            for: provider,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        let outcome = providerCredentialCoordinator.saveOfficialManualCookie(
            value,
            providerID: providerID,
            providers: config.providers,
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveOfficialManualCookieAndRestart(_ value: String, providerID: String) -> Bool {
        let ok = saveOfficialManualCookie(value, providerID: providerID)
        if ok {
            restartPolling()
        }
        return ok
    }

    private func invalidateCredentialLookupCache() {
        applyCredentialMutationOutcome(
            providerCredentialCoordinator.invalidateLookupCache {
                credentialAccessService.invalidateLookupCache()
            }
        )
    }

    @discardableResult
    func addRelaySiteDraft(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        userID: String,
        credentialInput: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .browserPreferred
    ) -> ProviderDescriptor? {
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(baseURL)
        guard !normalizedBaseURL.isEmpty else { return nil }

        let trimmedAdapterID = preferredAdapterID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAdapterID = (trimmedAdapterID?.isEmpty == false) ? trimmedAdapterID : nil
        let baseProvider = ProviderDescriptor.makeOpenRelay(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedBaseURL,
            preferredAdapterID: resolvedAdapterID
        )

        var draft = RelaySettingsDraft(provider: baseProvider, preferredAdapterID: resolvedAdapterID)
        draft.name = name
        draft.baseURL = normalizedBaseURL
        draft.balanceCredentialMode = balanceCredentialMode
        draft.userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.quotaDisplayMode = .remaining

        let provider = relayDescriptorPreviewBuilder.build(
            draft: draft,
            providers: config.providers + [baseProvider]
        ) ?? baseProvider

        config.providers.append(provider)
        if config.statusBarProviderID == nil {
            config.statusBarProviderID = provider.id
        }

        if let credentialInput {
            let trimmedCredential = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCredential.isEmpty, let balanceAuth = provider.relayConfig?.balanceAuth {
                _ = saveToken(trimmedCredential, auth: balanceAuth)
            }
        }

        persistAndRestart()
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
        return provider
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
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
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
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
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
        let resolvedQuotaDisplayMode = config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
            ?? quotaDisplayMode
            ?? .remaining
        let outcome = relayProviderSettingsCoordinator.updateOpenProviderSettings(
            draft: RelaySettingsDraft(
                providerID: providerID,
                name: name,
                baseURL: baseURL,
                preferredAdapterID: preferredAdapterID ?? "",
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
                quotaDisplayMode: resolvedQuotaDisplayMode
            ),
            providers: &config.providers,
            previewBuilder: relayDescriptorPreviewBuilder
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func saveRelayDraft(_ draft: RelaySettingsDraft) {
        let outcome = relayProviderSettingsCoordinator.updateOpenProviderSettings(
            draft: draft,
            providers: &config.providers,
            previewBuilder: relayDescriptorPreviewBuilder
        )
        applyGenericProviderSettingsMutation(outcome)
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
        let resolvedQuotaDisplayMode = config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
            ?? quotaDisplayMode
            ?? .remaining
        return relayDescriptorPreviewBuilder.build(
            draft: RelaySettingsDraft(
                providerID: providerID,
                name: name,
                baseURL: baseURL,
                preferredAdapterID: preferredAdapterID ?? "",
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
                quotaDisplayMode: resolvedQuotaDisplayMode
            ),
            providers: config.providers
        )
    }

    func relayDescriptorForPreview(draft: RelaySettingsDraft) -> ProviderDescriptor? {
        relayDescriptorPreviewBuilder.build(draft: draft, providers: config.providers)
    }

    func testRelayDraft(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        guard let descriptor = relayDescriptorForPreview(draft: draft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func importRelayDraftFromBrowser(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        var importDraft = draft
        importDraft.balanceCredentialMode = .browserPreferred
        guard let descriptor = relayDescriptorForPreview(draft: importDraft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        let outcome = relayProviderSettingsCoordinator.updateThirdPartyQuotaDisplayMode(
            providerID: providerID,
            quotaDisplayMode: quotaDisplayMode,
            providers: &config.providers
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func relayAdapterName(for provider: ProviderDescriptor) -> String? {
        provider.relayManifest?.displayName
    }

    func relayAuthSource(for providerID: String) -> String? {
        RelaySnapshotDisplayMetadata(snapshot: snapshots[providerID]).authSource
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
            notifyStatusBarDisplayConfigChanged()
            let relayMetadata = RelaySnapshotDisplayMetadata(
                snapshot: snapshot,
                fallbackAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID
            )
            return RelayDiagnosticResult(
                success: true,
                fetchHealth: snapshot.fetchHealth,
                resolvedAdapterID: relayMetadata.resolvedAdapterID,
                resolvedAuthSource: relayMetadata.authSource,
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
        let outcome = officialProviderSettingsCoordinator.updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode,
            providers: &config.providers
        )
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func saveOfficialDraft(_ draft: OfficialSettingsDraft) {
        updateOfficialProviderSettings(
            providerID: draft.providerID,
            sourceMode: draft.sourceMode,
            webMode: draft.webMode,
            quotaDisplayMode: draft.quotaDisplayMode,
            traeValueDisplayMode: draft.traeValueDisplayMode
        )
    }

    @discardableResult
    func saveOfficialCredentialAndSettings(
        providerID: String,
        credentialInput: String?,
        manualCookieInput: String?,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) -> Bool {
        var savedCredential = false
        if let provider = config.providers.first(where: { $0.id == providerID }),
           let credentialInput {
            savedCredential = saveToken(credentialInput, for: provider) || savedCredential
        }
        if let manualCookieInput {
            savedCredential = saveOfficialManualCookie(manualCookieInput, providerID: providerID) || savedCredential
        }
        updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
        return savedCredential
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

    @discardableResult
    private func persistConfiguration(
        showFeedback: Bool = false,
        successText: String? = nil
    ) -> Bool {
        applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.persistConfiguration(
                config,
                repository: configurationRepository,
                showFeedback: showFeedback,
                successText: successText ?? localizedText("已保存", "Saved"),
                failureText: localizedText("保存失败", "Save Failed")
            )
        )
    }

    @discardableResult
    private func resetConfiguration(showFeedback: Bool = false) -> Bool {
        applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.resetConfiguration(
                repository: configurationRepository,
                showFeedback: showFeedback,
                successText: localizedText("已重置", "Reset Complete"),
                failureText: localizedText("重置失败", "Reset Failed")
            )
        )
    }

    @discardableResult
    private func applyConfigurationPersistenceOutcome(
        _ outcome: AppConfigurationPersistenceOutcome
    ) -> Bool {
        settingsPersistenceFeedbackCoordinator.apply(outcome) { [weak self] state, errorMessage in
            self?.settingsPersistenceStatus = state
            self?.settingsPersistenceErrorMessage = errorMessage
        }
    }

    private func applyCredentialMutationOutcome(_ outcome: AppCredentialMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldBumpLookupVersion {
            credentialLookupVersion &+= 1
        }
    }

    private func persistAndRestart() {
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        _ = persistConfiguration(showFeedback: true)
        restartPolling()
        syncClaudeProfilesCurrentState()
        officialProfileLifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
            descriptor: claudeOfficialProviderDescriptor(),
            profiles: claudeDisplayableProfiles(),
            slots: claudeSlots,
            runtime: claudeOfficialProfileRefreshRuntime
        ) { [weak self] profile, descriptor in
            guard let self else { return .skipped }
            return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
        }
    }

    private func refreshDisplayedStatusBarProviders(forceRefresh: Bool = false) {
        providerRefreshCoordinator.refreshDisplayedStatusBarProviders(
            providers: statusBarProvidersForDisplay(),
            forceRefresh: forceRefresh
        ) { [weak self] descriptor, forceRefresh in
            await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
        }
    }

    private func applyStatusBarPreferencesMutation(_ outcome: StatusBarPreferencesMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldPersist {
            _ = persistConfiguration(showFeedback: true)
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            refreshDisplayedStatusBarProviders()
        }
    }

    private func applyProviderListMutation(_ outcome: AppProviderListMutationOutcome) {
        guard outcome != .none else { return }
        if !outcome.removedThirdPartyBaselineProviderIDs.isEmpty {
            for providerID in outcome.removedThirdPartyBaselineProviderIDs {
                thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
            }
            persistThirdPartyBalanceBaselines()
        }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            refreshDisplayedStatusBarProviders()
        }
    }

    private func applyGenericProviderSettingsMutation(_ outcome: AppProviderSettingsMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
    }

    private func normalizeStatusBarSelections() {
        statusBarPreferencesCoordinator.normalizeSelections(
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
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

    private func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        await providerRefreshCoordinator.refreshProvider(
            descriptor: descriptor,
            forceRefresh: forceRefresh,
            getState: { self.sessionStore.providerState },
            setState: { self.sessionStore.providerState = $0 },
            beforeRefresh: { descriptor in
                if descriptor.type == .codex, descriptor.family == .official {
                    self.syncCodexProfilesCurrentState()
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    self.syncClaudeProfilesCurrentState()
                }
            },
            transformFetchedSnapshot: { descriptor, fetched in
                if descriptor.type == .codex, descriptor.family == .official {
                    let snapshot = self.markCodexSnapshotActive(fetched)
                    self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    let snapshot = self.markClaudeSnapshotActive(fetched)
                    self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                return fetched
            },
            postOfficialRefresh: { descriptor, forceRefresh in
                guard descriptor.family == .official else { return }
                if forceRefresh {
                    await self.refreshOfficialProfileCardsAfterManualRefresh(for: descriptor)
                } else {
                    await self.refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for: descriptor)
                }
            },
            persistBaselineEntries: { entries in
                self.thirdPartyBalanceBaselineStore.save(entries)
            },
            afterRefresh: {
                self.pruneThirdPartyBalanceBaselines()
            },
            notifyStatusBarDisplayConfigChanged: {
                self.notifyStatusBarDisplayConfigChanged()
            },
            text: { key in
                self.text(key)
            },
            localizedText: { zhHans, en in
                self.localizedText(zhHans, en)
            },
            language: {
                self.config.language
            },
            boundedSnapshot: { snapshot in
                self.boundedSnapshot(snapshot)
            }
        )
    }

    nonisolated static func diagnosticCode(for health: FetchHealth) -> String {
        AppProviderRefreshCoordinator.diagnosticCode(for: health)
    }

    private func classifyFetchHealth(_ error: Error) -> FetchHealth {
        AppProviderRefreshCoordinator.classifyFetchHealth(error)
    }

    nonisolated static func emptySnapshotForFetchFailure(
        descriptor: ProviderDescriptor,
        health: FetchHealth,
        message: String,
        now: Date = Date()
    ) -> UsageSnapshot? {
        AppProviderRefreshCoordinator.emptySnapshotForFetchFailure(
            descriptor: descriptor,
            health: health,
            message: message,
            now: now
        )
    }

    nonisolated static func resolvedThirdPartyRemainingForBaseline(
        remaining: Double?,
        used: Double?,
        limit: Double?
    ) -> Double? {
        AppProviderRefreshCoordinator.resolvedThirdPartyRemainingForBaseline(
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
        AppOfficialProfileStateCoordinator.markCodexSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: codexProfiles
        )
    }

    private func syncCodexProfilesCurrentState() {
        let result = officialProfileSyncCoordinator.syncCodexProfiles(
            profileStore: codexProfileStore,
            desktopAuthService: codexDesktopAuthService
        )
        if result.profiles != codexProfiles {
            codexProfiles = result.profiles
        }
        codexOfficialProfileRefreshRuntime.pruneRetryState(keeping: result.visibleSlotIDs)
    }

    private func codexMenuTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    private func refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for descriptor: ProviderDescriptor) async {
        await officialProfileLifecycleCoordinator.refreshInactiveProfilesInBackgroundIfNeeded(
            descriptor: descriptor,
            codexSlots: codexSlots,
            claudeSlots: claudeSlots,
            codexRuntime: codexOfficialProfileRefreshRuntime,
            claudeRuntime: claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return self.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return self.claudeProfiles
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    private func refreshOfficialProfileCardsAfterManualRefresh(for descriptor: ProviderDescriptor) async {
        await officialProfileLifecycleCoordinator.refreshProfilesAfterManualRefresh(
            descriptor: descriptor,
            codexSlots: codexSlots,
            claudeSlots: claudeSlots,
            codexRuntime: codexOfficialProfileRefreshRuntime,
            claudeRuntime: claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return self.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return self.claudeDisplayableProfiles()
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(
                    profile,
                    descriptor: descriptor,
                    allowSessionWindowStabilization: false
                )
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    private func refreshCodexProfileSnapshotSlot(
        _ profile: CodexAccountProfile,
        descriptor: ProviderDescriptor,
        allowSessionWindowStabilization: Bool = true
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfileRefreshCoordinator.refreshCodexProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: codexOfficialProfileRefreshRuntime,
            allowSessionWindowStabilization: allowSessionWindowStabilization,
            fetchSnapshot: { profile, descriptor in
                try await self.codexProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedAuthJSON: { slotID, refreshedAuthJSON in
                _ = self.codexProfileStore.updateStoredAuthJSON(
                    slotID: slotID,
                    authJSON: refreshedAuthJSON
                )
            },
            syncProfiles: {
                self.syncCodexProfilesCurrentState()
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markCodexSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID, allowSessionWindowStabilization in
                self.codexSlots = self.codexSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID,
                    allowSessionWindowStabilization: allowSessionWindowStabilization
                )
            }
        )
    }

    private func setCodexSwitchFeedback(_ feedback: CodexSwitchFeedback?, for slotID: CodexSlotID) {
        codexFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { [weak self] in self?.codexSwitchFeedback[$0] },
            setValue: { [weak self] slotID, feedback in
                if let feedback {
                    self?.codexSwitchFeedback[slotID] = feedback
                } else {
                    self?.codexSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }

    private var hasPersistedOfficialMonitoringState: Bool {
        AppOfficialProfileStateCoordinator.hasPersistedOfficialMonitoringState(
            codexProfiles: codexProfiles,
            codexSlots: codexSlots,
            claudeProfiles: claudeProfiles,
            claudeSlots: claudeSlots
        )
    }

    private func restorePersistedOfficialProvidersIfNeeded() {
        if AppOfficialProfileStateCoordinator.restorePersistedOfficialProvidersIfNeeded(
            config: &config,
            codexProfiles: codexProfiles,
            codexSlots: codexSlots,
            claudeProfiles: claudeProfiles,
            claudeSlots: claudeSlots
        ) {
            normalizeStatusBarSelections()
        }
    }

    private func activateOfficialProviderAfterProfileSave(type: ProviderType) {
        let before = config
        if let index = config.providers.firstIndex(where: { $0.type == type && $0.family == .official }),
           !config.providers[index].enabled {
            config.providers[index].enabled = true
        }
        normalizeStatusBarSelections()
        if config != before {
            _ = persistConfiguration(showFeedback: true)
            restartPolling()
            refreshDisplayedStatusBarProviders()
        }
        notifyStatusBarDisplayConfigChanged()
    }

    private func codexSwitchMessage(
        for restartResult: CodexDesktopAppRestartResult,
        successKey: L10nKey
    ) -> String {
        if restartResult.requiresManualRelaunch {
            return text(.codexSwitchDesktopRestartIncomplete)
        }
        return text(successKey)
    }

    func claudeStatusBarDisplaySnapshot() -> UsageSnapshot? {
        let descriptor = claudeOfficialProviderDescriptor()
        return officialProfileDisplayCoordinator.claudeStatusBarDisplaySnapshot(
            resolvedSlotID: resolvedClaudeStatusBarDisplaySlotID(),
            slotViewModels: claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: false),
            providerSnapshot: descriptor.flatMap { snapshots[$0.id] }
        )
    }

    private func claudeOfficialProviderDescriptor() -> ProviderDescriptor? {
        config.providers.first(where: { $0.type == .claude && $0.family == .official })
    }

    private func claudeDisplayableProfiles() -> [ClaudeAccountProfile] {
        AppOfficialProfileStateCoordinator.displayableClaudeProfiles(claudeProfiles)
    }

    private func resolvedClaudeStatusBarDisplaySlotID() -> CodexSlotID? {
        AppOfficialProfileStateCoordinator.resolveClaudeStatusBarDisplaySlotID(
            configuredSlotID: config.claudeStatusBarDisplaySlotID,
            profiles: claudeProfiles,
            slots: claudeSlots
        )
    }

    private func normalizedClaudeStatusBarDisplaySlotID(_ slotID: CodexSlotID?) -> CodexSlotID? {
        AppOfficialProfileStateCoordinator.normalizedClaudeStatusBarDisplaySlotID(
            slotID,
            profiles: claudeProfiles
        )
    }

    private func triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: CodexSlotID?) {
        let action = officialProfileDisplayCoordinator.claudeStatusBarDisplayPrefetchAction(
            slotID: slotID,
            descriptor: claudeOfficialProviderDescriptor(),
            profiles: claudeProfiles
        )
        switch action {
        case .none:
            return
        case .notifyOnly:
            notifyStatusBarDisplayConfigChanged()
            return
        case .refresh(let slotID):
            guard let descriptor = claudeOfficialProviderDescriptor(),
                  let profile = claudeProfiles.first(where: { $0.slotID == slotID }) else {
                return
            }
            Task { [weak self] in
            guard let self else { return }
                _ = await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
                self.notifyStatusBarDisplayConfigChanged()
            }
        }
    }

    private func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        AppOfficialProfileStateCoordinator.markClaudeSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: claudeProfiles
        )
    }

    private func bootstrapClaudeProfileState() {
        let bootstrapResult = officialProfileSyncCoordinator.bootstrapClaudeProfilesIfNeeded(
            currentProfiles: claudeProfiles,
            didRunAutoCaptureCompaction: didRunClaudeAutoCaptureCompaction,
            profileStore: claudeProfileStore,
            desktopAuthService: claudeDesktopAuthService
        )
        didRunClaudeAutoCaptureCompaction = bootstrapResult.didRunAutoCaptureCompaction
        if bootstrapResult.profiles != claudeProfiles {
            claudeProfiles = bootstrapResult.profiles
        }
        if !bootstrapResult.removedSlotIDs.isEmpty {
            removeClaudeSlotState(slotIDs: bootstrapResult.removedSlotIDs)
        }
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: true)
    }

    private func syncClaudeProfilesCurrentState(triggerPrefetchOnChange: Bool = true) {
        let previousConfiguredDisplaySlotID = config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        let syncResult = officialProfileSyncCoordinator.syncClaudeProfiles(
            currentProfiles: claudeProfiles,
            slots: claudeSlots,
            configuredDisplaySlotID: config.claudeStatusBarDisplaySlotID,
            profileStore: claudeProfileStore,
            desktopAuthService: claudeDesktopAuthService
        )
        if syncResult.profiles != claudeProfiles {
            claudeProfiles = syncResult.profiles
        }

        claudeOfficialProfileRefreshRuntime.pruneVisibleSlots(keeping: syncResult.visibleSlotIDs)
        config.claudeStatusBarDisplaySlotID = syncResult.syncEvaluation.normalizedConfiguredDisplaySlotID

        if config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = persistConfiguration(showFeedback: false)
        }

        if triggerPrefetchOnChange,
           syncResult.syncEvaluation.didProfileIdentityChange {
            officialProfileLifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
                descriptor: claudeOfficialProviderDescriptor(),
                profiles: claudeDisplayableProfiles(),
                slots: claudeSlots,
                runtime: claudeOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        let resolvedDisplaySlotID = syncResult.syncEvaluation.resolvedDisplaySlotID
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            notifyStatusBarDisplayConfigChanged()
        }
    }

    private func claudeMenuTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    private func refreshClaudeProfileSnapshotSlot(
        _ profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfileRefreshCoordinator.refreshClaudeProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: claudeOfficialProfileRefreshRuntime,
            shouldRefreshProfile: { AppOfficialProfileStateCoordinator.canDisplayClaudeMonitoringProfile($0) },
            fetchSnapshot: { profile, descriptor in
                try await self.claudeProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedCredentialsJSON: { slotID, refreshedCredentialsJSON in
                _ = self.claudeProfileStore.updateStoredCredentials(
                    slotID: slotID,
                    credentialsJSON: refreshedCredentialsJSON
                )
            },
            syncProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markClaudeSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID in
                self.claudeSlots = self.claudeSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID
                )
                if self.resolvedClaudeStatusBarDisplaySlotID() == slotID {
                    self.notifyStatusBarDisplayConfigChanged()
                }
            }
        )
    }

    private func removeClaudeSlotState(slotIDs: [CodexSlotID]) {
        guard !slotIDs.isEmpty else { return }
        let uniqueSlotIDs = Array(Set(slotIDs)).sorted()
        for slotID in uniqueSlotIDs {
            claudeSlots = claudeSlotStore.remove(slotID: slotID)
            claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
            claudeSwitchFeedback.removeValue(forKey: slotID)
        }
    }

    private func setClaudeSwitchFeedback(_ feedback: ClaudeSwitchFeedback?, for slotID: CodexSlotID) {
        claudeFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { [weak self] in self?.claudeSwitchFeedback[$0] },
            setValue: { [weak self] slotID, feedback in
                if let feedback {
                    self?.claudeSwitchFeedback[slotID] = feedback
                } else {
                    self?.claudeSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }
}

extension ResourceMode {
    var refreshSchedulerConfig: ProviderRefreshSchedulerConfig {
        switch self {
        case .background3Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 10,
                localSessionSignalIdleSleepSeconds: 30
            )
        case .background5Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: RuntimeDiagnosticsLimits.localSessionSignalActiveSleepSeconds,
                localSessionSignalIdleSleepSeconds: RuntimeDiagnosticsLimits.localSessionSignalIdleSleepSeconds
            )
        case .background10Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 20,
                localSessionSignalIdleSleepSeconds: 90
            )
        case .background15Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 30,
                localSessionSignalIdleSleepSeconds: 120
            )
        }
    }
}

private enum LocalUsageHistoryError: LocalizedError {
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported local trend provider: \(provider)"
        }
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
