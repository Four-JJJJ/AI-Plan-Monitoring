import Foundation
import XCTest
import OhMyUsageApplication

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
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
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

    func testBackgroundProviderUsesConfiguredBackgroundInterval() async throws {
        let foreground = makeProvider(id: "foreground", enabled: true, pollIntervalSec: 300)
        let background = makeProvider(id: "background", enabled: true, pollIntervalSec: 300)
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
            return sleeps.contains(300) && sleeps.contains(180)
        }
        scheduler.stop()
    }

    func testLocalSessionSignalTriggersRefresh() async throws {
        let provider = makeProvider(
            id: "codex-official",
            enabled: true,
            pollIntervalSec: 60,
            localSessionWatchKind: .codex
        )
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
        providers: [ProviderRefreshScheduleDescriptor],
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
            refreshAction: { providerID, forceRefresh in
                await refreshRecorder.record(providerID: providerID, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            config: ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: 180,
                localSessionSignalActiveSleepSeconds: 15,
                localSessionSignalIdleSleepSeconds: 60
            ),
            startupJitterProvider: startupJitterProvider,
            sleepAction: sleepAction
        )
    }

    private func makeProvider(
        id: String,
        enabled: Bool,
        pollIntervalSec: Int = 60,
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) -> ProviderRefreshScheduleDescriptor {
        ProviderRefreshScheduleDescriptor(
            id: id,
            isEnabled: enabled,
            pollIntervalSec: pollIntervalSec,
            localSessionWatchKind: localSessionWatchKind
        )
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

    func record(providerID: String, forceRefresh: Bool) {
        events.append("\(providerID):\(forceRefresh)")
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
