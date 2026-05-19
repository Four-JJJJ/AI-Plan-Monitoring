import Foundation
import UserNotifications

@MainActor
final class AppPermissionCoordinator {
    typealias FullDiskProbeResult = (isGranted: Bool, isRelevant: Bool)

    private struct FullDiskProbeCache {
        var result: FullDiskProbeResult
        var checkedAt: Date
    }

    private let fullDiskProbeCacheDuration: TimeInterval
    private let fullDiskProbeThrottleInterval: TimeInterval
    private let dateProvider: () -> Date
    private var fullDiskProbeCache: FullDiskProbeCache?
    private var fullDiskProbeInFlight: Task<FullDiskProbeResult, Never>?
    private var fullDiskProbeGeneration = 0
    private var lastFullDiskProbeStartedAt = Date.distantPast

    init(
        fullDiskProbeCacheDuration: TimeInterval = 30,
        fullDiskProbeThrottleInterval: TimeInterval = 5,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.fullDiskProbeCacheDuration = fullDiskProbeCacheDuration
        self.fullDiskProbeThrottleInterval = fullDiskProbeThrottleInterval
        self.dateProvider = dateProvider
    }

    static func shouldShowPermissionGuide(
        hasEnabledProviders: Bool,
        hasPersistedOfficialMonitoringState: Bool,
        hasNotificationPermission: Bool,
        secureStorageReady: Bool,
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool,
        fullDiskAccessGranted: Bool
    ) -> Bool {
        guard !hasEnabledProviders else { return false }
        guard !hasPersistedOfficialMonitoringState else { return false }
        if !hasNotificationPermission { return true }
        if !secureStorageReady { return true }
        if (fullDiskAccessRelevant || fullDiskAccessRequested) && !fullDiskAccessGranted { return true }
        return false
    }

    func requestNotificationPermission(
        requestPermissionIfNeeded: () -> Void,
        fetchNotificationAuthorizationStatus: @escaping () async -> UNAuthorizationStatus,
        updateNotificationAuthorizationStatus: @escaping @MainActor (UNAuthorizationStatus) -> Void,
        refreshPermissionStatuses: @escaping @MainActor () -> Void,
        pollAttempts: Int = 20,
        pollIntervalNanoseconds: UInt64 = 500_000_000
    ) -> Task<Void, Never> {
        requestPermissionIfNeeded()
        return Task { @MainActor in
            for _ in 0..<pollAttempts {
                if Task.isCancelled { break }
                let status = await fetchNotificationAuthorizationStatus()
                updateNotificationAuthorizationStatus(status)
                if status != .notDetermined {
                    break
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
            refreshPermissionStatuses()
        }
    }

    func refreshPermissionStatuses(
        checkSecureStorageReady: @escaping () async -> Bool,
        fetchNotificationAuthorizationStatus: @escaping () async -> UNAuthorizationStatus,
        previousSecureStorageReady: Bool,
        updateSecureStorageReady: @escaping @MainActor (Bool) -> Void,
        onSecureStorageBecameReady: @escaping @MainActor () -> Void,
        fullDiskProbe: @escaping @Sendable () -> FullDiskProbeResult = { AppPermissionCoordinator.probeFullDiskAccess() },
        applyFullDiskProbe: @escaping @MainActor (_ isGranted: Bool, _ isRelevant: Bool) -> Void,
        updateNotificationAuthorizationStatus: @escaping @MainActor (UNAuthorizationStatus) -> Void,
        forceFullDiskProbe: Bool = false
    ) -> Task<Void, Never> {
        let fullDiskTask = fullDiskProbeTask(
            force: forceFullDiskProbe,
            fullDiskProbe: fullDiskProbe,
            applyCachedResult: applyFullDiskProbe
        )

        return Task { @MainActor in
            let ready = await checkSecureStorageReady()

            guard !Task.isCancelled else { return }
            updateSecureStorageReady(ready)
            if ready && !previousSecureStorageReady {
                onSecureStorageBecameReady()
            }

            let status = await fetchNotificationAuthorizationStatus()
            updateNotificationAuthorizationStatus(status)

            if let fullDiskTask {
                let fullDisk = await fullDiskTask.value
                guard !Task.isCancelled else { return }
                applyFullDiskProbe(fullDisk.isGranted, fullDisk.isRelevant)
            }
        }
    }

    nonisolated static func probeFullDiskAccess(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> FullDiskProbeResult {
        let fileCandidates = [
            "\(homeDirectory)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(homeDirectory)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.sqlite",
            "\(homeDirectory)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies/Cookies.sqlite",
            "\(homeDirectory)/Library/Application Support/Google/Chrome/Default/Network/Cookies",
            "\(homeDirectory)/Library/Application Support/Arc/User Data/Default/Network/Cookies",
            "\(homeDirectory)/Library/Application Support/Microsoft Edge/Default/Network/Cookies",
            "\(homeDirectory)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Network/Cookies",
            "\(homeDirectory)/Library/Application Support/Chromium/Default/Network/Cookies"
        ]
        let directoryCandidates = [
            "\(homeDirectory)/Library/Application Support/Google/Chrome",
            "\(homeDirectory)/Library/Application Support/Arc/User Data",
            "\(homeDirectory)/Library/Application Support/Microsoft Edge",
            "\(homeDirectory)/Library/Application Support/BraveSoftware/Brave-Browser",
            "\(homeDirectory)/Library/Application Support/Chromium",
            "\(homeDirectory)/Library/Containers/com.apple.Safari/Data/Library/Cookies",
            "\(homeDirectory)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies"
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

    private func fullDiskProbeTask(
        force: Bool,
        fullDiskProbe: @escaping @Sendable () -> FullDiskProbeResult,
        applyCachedResult: @escaping @MainActor (_ isGranted: Bool, _ isRelevant: Bool) -> Void
    ) -> Task<FullDiskProbeResult, Never>? {
        let now = dateProvider()

        if !force, let cached = fullDiskProbeCache {
            applyCachedResult(cached.result.isGranted, cached.result.isRelevant)
            if now.timeIntervalSince(cached.checkedAt) < fullDiskProbeCacheDuration {
                return nil
            }
        }

        if let inFlight = fullDiskProbeInFlight {
            return inFlight
        }

        guard force || now.timeIntervalSince(lastFullDiskProbeStartedAt) >= fullDiskProbeThrottleInterval else {
            return nil
        }

        fullDiskProbeGeneration += 1
        let generation = fullDiskProbeGeneration
        lastFullDiskProbeStartedAt = now
        let completeProbe: @MainActor @Sendable (FullDiskProbeResult) -> Void = { [weak self] result in
            guard let self, generation == self.fullDiskProbeGeneration else { return }
            self.fullDiskProbeCache = FullDiskProbeCache(result: result, checkedAt: self.dateProvider())
            self.fullDiskProbeInFlight = nil
        }
        let task = Task.detached(priority: .utility) {
            let result = fullDiskProbe()
            await completeProbe(result)
            return result
        }
        fullDiskProbeInFlight = task

        return task
    }
}
