import Foundation

package enum LocalSessionWatchKind: Equatable, Sendable {
    case codex
    case claude
}

package protocol LocalSessionCompletionSignalSource {
    func latestCodexCompletionAt() -> Date?
    func latestClaudeCompletionAt() -> Date?
}

package struct ProviderRefreshScheduleDescriptor: Equatable, Sendable {
    package var id: String
    package var isEnabled: Bool
    package var pollIntervalSec: Int
    package var localSessionWatchKind: LocalSessionWatchKind?

    package init(
        id: String,
        isEnabled: Bool,
        pollIntervalSec: Int,
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.pollIntervalSec = pollIntervalSec
        self.localSessionWatchKind = localSessionWatchKind
    }
}

package struct ProviderRefreshSchedulerConfig: Equatable, Sendable {
    package var backgroundProviderPollIntervalMultiplier: Int
    package var backgroundProviderPollIntervalFloorSeconds: Int
    package var localSessionSignalActiveSleepSeconds: TimeInterval
    package var localSessionSignalIdleSleepSeconds: TimeInterval

    package init(
        backgroundProviderPollIntervalMultiplier: Int,
        backgroundProviderPollIntervalFloorSeconds: Int,
        localSessionSignalActiveSleepSeconds: TimeInterval,
        localSessionSignalIdleSleepSeconds: TimeInterval
    ) {
        self.backgroundProviderPollIntervalMultiplier = backgroundProviderPollIntervalMultiplier
        self.backgroundProviderPollIntervalFloorSeconds = backgroundProviderPollIntervalFloorSeconds
        self.localSessionSignalActiveSleepSeconds = localSessionSignalActiveSleepSeconds
        self.localSessionSignalIdleSleepSeconds = localSessionSignalIdleSleepSeconds
    }
}

package final class LocalSessionRefreshCoordinator {
    private let signalSource: LocalSessionCompletionSignalSource
    private let minimumEventRefreshGap: TimeInterval
    private let nowProvider: () -> Date
    private var lastProcessedSignalAt: [String: Date] = [:]
    private var lastTriggeredRefreshAt: [String: Date] = [:]

    package init(
        signalSource: LocalSessionCompletionSignalSource,
        minimumEventRefreshGap: TimeInterval = 15,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.signalSource = signalSource
        self.minimumEventRefreshGap = max(1, minimumEventRefreshGap)
        self.nowProvider = nowProvider
    }

    package func refreshCandidates(from providers: [ProviderRefreshScheduleDescriptor]) -> [String] {
        let now = nowProvider()
        var output: [String] = []

        for descriptor in providers where descriptor.isEnabled {
            guard let signalAt = latestSignal(for: descriptor.localSessionWatchKind) else {
                continue
            }
            let lastProcessed = lastProcessedSignalAt[descriptor.id] ?? .distantPast
            guard signalAt > lastProcessed else {
                continue
            }
            if let lastTriggered = lastTriggeredRefreshAt[descriptor.id],
               now.timeIntervalSince(lastTriggered) < minimumEventRefreshGap {
                continue
            }

            lastProcessedSignalAt[descriptor.id] = signalAt
            lastTriggeredRefreshAt[descriptor.id] = now
            output.append(descriptor.id)
        }

        return output
    }

    private func latestSignal(for watchKind: LocalSessionWatchKind?) -> Date? {
        switch watchKind {
        case .codex:
            return signalSource.latestCodexCompletionAt()
        case .claude:
            return signalSource.latestClaudeCompletionAt()
        case nil:
            return nil
        }
    }
}

@MainActor
package final class ProviderRefreshScheduler {
    package typealias DescriptorProvider = @MainActor (_ providerID: String) -> ProviderRefreshScheduleDescriptor?
    package typealias ProvidersProvider = @MainActor () -> [ProviderRefreshScheduleDescriptor]
    package typealias ActiveProviderIDsProvider = @MainActor () -> Set<String>
    package typealias FailureCountProvider = @MainActor (_ providerID: String) -> Int
    package typealias RefreshAction = @MainActor (_ providerID: String, _ forceRefresh: Bool) async -> Void
    package typealias SleepAction = @Sendable (_ seconds: TimeInterval) async throws -> Void

    private let descriptorProvider: DescriptorProvider
    private let providersProvider: ProvidersProvider
    private let activeProviderIDsProvider: ActiveProviderIDsProvider
    private let failureCountProvider: FailureCountProvider
    private let refreshAction: RefreshAction
    private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator
    private let startupJitterProvider: @Sendable () -> TimeInterval
    private let sleepAction: SleepAction
    private let config: ProviderRefreshSchedulerConfig
    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var localSessionMonitorTask: Task<Void, Never>?

    package init(
        descriptorProvider: @escaping DescriptorProvider,
        providersProvider: @escaping ProvidersProvider,
        activeProviderIDsProvider: @escaping ActiveProviderIDsProvider = { [] },
        failureCountProvider: @escaping FailureCountProvider,
        refreshAction: @escaping RefreshAction,
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator,
        config: ProviderRefreshSchedulerConfig,
        startupJitterProvider: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0...20) },
        sleepAction: @escaping SleepAction = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.descriptorProvider = descriptorProvider
        self.providersProvider = providersProvider
        self.activeProviderIDsProvider = activeProviderIDsProvider
        self.failureCountProvider = failureCountProvider
        self.refreshAction = refreshAction
        self.localSessionRefreshCoordinator = localSessionRefreshCoordinator
        self.config = config
        self.startupJitterProvider = startupJitterProvider
        self.sleepAction = sleepAction
    }

    package var pollTaskCount: Int {
        pollTasks.count
    }

    package var scheduledProviderIDs: Set<String> {
        Set(pollTasks.keys)
    }

    package func restart(providers: [ProviderRefreshScheduleDescriptor]) {
        stop()

        for provider in providers where provider.isEnabled {
            pollTasks[provider.id] = Task { @MainActor [weak self] in
                await self?.pollLoop(providerID: provider.id)
            }
        }

        restartLocalSessionSignalMonitor(providers: providers)
    }

    package func stop() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
    }

    package func refreshNow(providers: [ProviderRefreshScheduleDescriptor]) {
        let enabled = providers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for descriptor in enabled {
                await refreshAction(descriptor.id, true)
            }
        }
    }

    private func pollLoop(providerID: String) async {
        let startupJitterSeconds = startupJitterProvider()
        if startupJitterSeconds > 0 {
            do {
                try await sleepAction(startupJitterSeconds)
            } catch {
                return
            }
        }

        while !Task.isCancelled {
            guard let descriptor = descriptorProvider(providerID), descriptor.isEnabled else {
                return
            }

            await refreshAction(providerID, false)

            let failureCount = failureCountProvider(providerID)
            let baseInterval = pollBaseInterval(for: descriptor)
            let delay = TimeInterval(BackoffPolicy.delaySeconds(
                baseInterval: baseInterval,
                consecutiveFailures: failureCount
            ))

            do {
                try await sleepAction(delay)
            } catch {
                return
            }
        }
    }

    private func restartLocalSessionSignalMonitor(providers: [ProviderRefreshScheduleDescriptor]) {
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
        guard providers.contains(where: { $0.isEnabled && $0.localSessionWatchKind != nil }) else {
            return
        }
        localSessionMonitorTask = Task { @MainActor [weak self] in
            await self?.localSessionSignalLoop()
        }
    }

    private func localSessionSignalLoop() async {
        var idleCycles = 0
        while !Task.isCancelled {
            let watchTargets = providersProvider().filter { $0.isEnabled && $0.localSessionWatchKind != nil }
            if watchTargets.isEmpty {
                return
            }

            let refreshTargetIDs = localSessionRefreshCoordinator.refreshCandidates(from: watchTargets)
            if refreshTargetIDs.isEmpty {
                idleCycles += 1
            } else {
                idleCycles = 0
                for providerID in refreshTargetIDs {
                    await refreshAction(providerID, false)
                }
            }

            let sleepSeconds = idleCycles <= 2
                ? config.localSessionSignalActiveSleepSeconds
                : config.localSessionSignalIdleSleepSeconds
            do {
                try await sleepAction(sleepSeconds)
            } catch {
                return
            }
        }
    }

    private func pollBaseInterval(for descriptor: ProviderRefreshScheduleDescriptor) -> Int {
        let base = max(1, descriptor.pollIntervalSec)
        let activeIDs = activeProviderIDsProvider()
        if activeIDs.isEmpty || activeIDs.contains(descriptor.id) {
            return base
        }
        let stretched = base * max(1, config.backgroundProviderPollIntervalMultiplier)
        return max(stretched, config.backgroundProviderPollIntervalFloorSeconds)
    }
}
