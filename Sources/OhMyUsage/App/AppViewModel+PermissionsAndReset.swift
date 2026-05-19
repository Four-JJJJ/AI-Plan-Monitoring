import AppKit
import Foundation
import UserNotifications

@MainActor
extension AppViewModel {
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

    func refreshPermissionStatusesIfNeeded(referenceDate: Date = Date()) {
        guard referenceDate.timeIntervalSince(lastPermissionStatusRefreshAt) >= 5 else { return }
        refreshPermissionStatuses(force: false)
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

    func refreshPermissionStatuses(force: Bool) {
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
            updateNotificationAuthorizationStatus: { self.notificationAuthorizationStatus = $0 },
            forceFullDiskProbe: force
        )
    }
}

private extension AppViewModel {
    func openSystemSettings(urlCandidates: [String], fallbackBundleIDs: [String] = ["com.apple.systemsettings", "com.apple.systempreferences"]) {
        for raw in urlCandidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettingsApplication(bundleIDs: fallbackBundleIDs)
    }

    func openSystemSettingsApplication(bundleIDs: [String]) {
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
}
