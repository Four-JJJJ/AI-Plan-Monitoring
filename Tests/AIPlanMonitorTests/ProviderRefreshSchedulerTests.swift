import Foundation
import XCTest
@testable import AIPlanMonitor

@MainActor
final class ProviderRefreshSchedulerTests: XCTestCase {
    func testRestartSchedulesOnlyEnabledProvidersAndStopCancels() {
        let enabled = makeProvider(id: "enabled", enabled: true)
        let disabled = makeProvider(id: "disabled", enabled: false)
        let scheduler = makeScheduler(providers: [enabled, disabled])

        scheduler.restart(providers: [enabled, disabled])

        XCTAssertEqual(scheduler.scheduledProviderIDs, ["enabled"])
        XCTAssertEqual(scheduler.pollTaskCount, 1)

        scheduler.stop()

        XCTAssertTrue(scheduler.scheduledProviderIDs.isEmpty)
        XCTAssertEqual(scheduler.pollTaskCount, 0)
    }

    func testManualRefreshRefreshesEnabledProvidersInOrder() async throws {
        let first = makeProvider(id: "first", enabled: true)
        let second = makeProvider(id: "second", enabled: true)
        let disabled = makeProvider(id: "disabled", enabled: false)
        let recorder = RefreshRecorder()
        let scheduler = makeScheduler(
            providers: [first, second, disabled],
            refreshRecorder: recorder
        )

        scheduler.refreshNow(providers: [first, second, disabled])

        try await waitUntil {
            await recorder.snapshot().count == 2
        }
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["first:true", "second:true"])
    }

    func testPollLoopUsesFailureBackoff() async throws {
        var provider = makeProvider(id: "poll", enabled: true)
        provider.pollIntervalSec = 60
        let recorder = RefreshRecorder()
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            failureCounts: ["poll": 1],
            refreshRecorder: recorder,
            startupJitterProvider: { 0 },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let events = await recorder.snapshot()
            let sleeps = await sleepRecorder.snapshot()
            return events == ["poll:false"] && sleeps == [120]
        }
        scheduler.stop()
    }

    func testBackgroundProviderUsesStretchedPollInterval() async throws {
        var foreground = makeProvider(id: "foreground", enabled: true)
        foreground.pollIntervalSec = 60
        var background = makeProvider(id: "background", enabled: true)
        background.pollIntervalSec = 60
        let recorder = RefreshRecorder()
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [foreground, background],
            activeProviderIDs: ["foreground"],
            refreshRecorder: recorder,
            startupJitterProvider: { 0 },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [foreground, background])

        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return sleeps.contains(60)
                && sleeps.contains(TimeInterval(RuntimeDiagnosticsLimits.backgroundProviderPollIntervalFloorSeconds))
        }
        scheduler.stop()
    }

    func testLocalSessionSignalTriggersRefresh() async throws {
        var provider = makeProvider(id: "codex-official", type: .codex, enabled: true)
        provider.pollIntervalSec = 60
        let recorder = RefreshRecorder()
        let sleepRecorder = SleepRecorder()
        let signalSource = FakeLocalSessionSignalSource(codexCompletionAt: Date(timeIntervalSince1970: 100))
        let coordinator = LocalSessionRefreshCoordinator(
            signalSource: signalSource,
            minimumEventRefreshGap: 1
        )
        let scheduler = makeScheduler(
            providers: [provider],
            refreshRecorder: recorder,
            localSessionRefreshCoordinator: coordinator,
            startupJitterProvider: { 999 },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            await recorder.snapshot() == ["codex-official:false"]
        }
        scheduler.stop()
    }

    private func makeScheduler(
        providers: [ProviderDescriptor],
        activeProviderIDs: Set<String> = [],
        failureCounts: [String: Int] = [:],
        refreshRecorder: RefreshRecorder = RefreshRecorder(),
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: FakeLocalSessionSignalSource()
        ),
        startupJitterProvider: @escaping @Sendable () -> TimeInterval = { 999 },
        sleepAction: @escaping ProviderRefreshScheduler.SleepAction = { _ in throw CancellationError() }
    ) -> ProviderRefreshScheduler {
        let currentProviders = providers
        return ProviderRefreshScheduler(
            descriptorProvider: { providerID in
                currentProviders.first { $0.id == providerID }
            },
            providersProvider: {
                currentProviders
            },
            activeProviderIDsProvider: {
                activeProviderIDs
            },
            failureCountProvider: { providerID in
                failureCounts[providerID, default: 0]
            },
            refreshAction: { descriptor, forceRefresh in
                await refreshRecorder.record(descriptor: descriptor, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            startupJitterProvider: startupJitterProvider,
            sleepAction: sleepAction
        )
    }

    private func makeProvider(
        id: String,
        type: ProviderType = .relay,
        enabled: Bool
    ) -> ProviderDescriptor {
        var provider = ProviderDescriptor.makeOpenRelay(name: id, baseURL: "https://example.com")
        provider.id = id
        provider.type = type
        provider.family = type == .relay ? .thirdParty : .official
        provider.enabled = enabled
        return provider
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for scheduler state")
    }
}

private actor RefreshRecorder {
    private var events: [String] = []

    func record(descriptor: ProviderDescriptor, forceRefresh: Bool) {
        events.append("\(descriptor.id):\(forceRefresh)")
    }

    func snapshot() -> [String] {
        events
    }
}

private actor SleepRecorder {
    private var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }

    func snapshot() -> [TimeInterval] {
        values
    }
}

private final class FakeLocalSessionSignalSource: LocalSessionCompletionSignalSource {
    var codexCompletionAt: Date?
    var claudeCompletionAt: Date?

    init(codexCompletionAt: Date? = nil, claudeCompletionAt: Date? = nil) {
        self.codexCompletionAt = codexCompletionAt
        self.claudeCompletionAt = claudeCompletionAt
    }

    func latestCodexCompletionAt() -> Date? {
        codexCompletionAt
    }

    func latestClaudeCompletionAt() -> Date? {
        claudeCompletionAt
    }
}
