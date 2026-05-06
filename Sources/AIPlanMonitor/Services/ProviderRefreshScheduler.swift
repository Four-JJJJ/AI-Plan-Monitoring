import Foundation

@MainActor
final class ProviderRefreshScheduler {
    typealias DescriptorProvider = @MainActor (_ providerID: String) -> ProviderDescriptor?
    typealias ProvidersProvider = @MainActor () -> [ProviderDescriptor]
    typealias ActiveProviderIDsProvider = @MainActor () -> Set<String>
    typealias FailureCountProvider = @MainActor (_ providerID: String) -> Int
    typealias RefreshAction = @MainActor (_ descriptor: ProviderDescriptor, _ forceRefresh: Bool) async -> Void
    typealias SleepAction = @Sendable (_ seconds: TimeInterval) async throws -> Void

    private let descriptorProvider: DescriptorProvider
    private let providersProvider: ProvidersProvider
    private let activeProviderIDsProvider: ActiveProviderIDsProvider
    private let failureCountProvider: FailureCountProvider
    private let refreshAction: RefreshAction
    private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator
    private let startupJitterProvider: @Sendable () -> TimeInterval
    private let sleepAction: SleepAction
    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var localSessionMonitorTask: Task<Void, Never>?

    init(
        descriptorProvider: @escaping DescriptorProvider,
        providersProvider: @escaping ProvidersProvider,
        activeProviderIDsProvider: @escaping ActiveProviderIDsProvider = { [] },
        failureCountProvider: @escaping FailureCountProvider,
        refreshAction: @escaping RefreshAction,
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator,
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
        self.startupJitterProvider = startupJitterProvider
        self.sleepAction = sleepAction
    }

    var pollTaskCount: Int {
        pollTasks.count
    }

    var scheduledProviderIDs: Set<String> {
        Set(pollTasks.keys)
    }

    func restart(providers: [ProviderDescriptor]) {
        stop()

        for provider in providers where provider.enabled {
            pollTasks[provider.id] = Task { @MainActor [weak self] in
                await self?.pollLoop(providerID: provider.id)
            }
        }

        restartLocalSessionSignalMonitor(providers: providers)
    }

    func stop() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
    }

    func refreshNow(providers: [ProviderDescriptor]) {
        let enabled = providers.filter(\.enabled)
        guard !enabled.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for descriptor in enabled {
                await refreshAction(descriptor, true)
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
            guard let descriptor = descriptorProvider(providerID), descriptor.enabled else {
                return
            }

            await refreshAction(descriptor, false)

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

    private func restartLocalSessionSignalMonitor(providers: [ProviderDescriptor]) {
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
        guard Self.hasLocalSessionWatchTargets(providers) else {
            return
        }
        localSessionMonitorTask = Task { @MainActor [weak self] in
            await self?.localSessionSignalLoop()
        }
    }

    private func localSessionSignalLoop() async {
        var idleCycles = 0
        while !Task.isCancelled {
            let watchTargets = providersProvider().filter(Self.isLocalSessionWatchTarget)
            if watchTargets.isEmpty {
                return
            }

            let refreshTargets = localSessionRefreshCoordinator.refreshCandidates(from: watchTargets)
            if refreshTargets.isEmpty {
                idleCycles += 1
            } else {
                idleCycles = 0
                for descriptor in refreshTargets {
                    await refreshAction(descriptor, false)
                }
            }

            let sleepSeconds = idleCycles <= 2
                ? RuntimeDiagnosticsLimits.localSessionSignalActiveSleepSeconds
                : RuntimeDiagnosticsLimits.localSessionSignalIdleSleepSeconds
            do {
                try await sleepAction(sleepSeconds)
            } catch {
                return
            }
        }
    }

    private func pollBaseInterval(for descriptor: ProviderDescriptor) -> Int {
        let base = max(1, descriptor.pollIntervalSec)
        let activeIDs = activeProviderIDsProvider()
        if activeIDs.isEmpty || activeIDs.contains(descriptor.id) {
            return base
        }
        let stretched = base * max(1, RuntimeDiagnosticsLimits.backgroundProviderPollIntervalMultiplier)
        return max(stretched, RuntimeDiagnosticsLimits.backgroundProviderPollIntervalFloorSeconds)
    }

    private static func hasLocalSessionWatchTargets(_ providers: [ProviderDescriptor]) -> Bool {
        providers.contains(where: isLocalSessionWatchTarget)
    }

    private static func isLocalSessionWatchTarget(_ provider: ProviderDescriptor) -> Bool {
        provider.enabled
            && provider.family == .official
            && (provider.type == .codex || provider.type == .claude)
    }
}
