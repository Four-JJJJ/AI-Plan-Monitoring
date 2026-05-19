import Foundation
import UserNotifications
import XCTest
@testable import OhMyUsage

@MainActor
final class AppPermissionCoordinatorTests: XCTestCase {
    func testRequestNotificationPermissionPollsUntilResolvedThenRefreshes() async {
        let coordinator = AppPermissionCoordinator()
        var didRequest = false
        var statuses: [UNAuthorizationStatus] = []
        var refreshCount = 0
        let source = LockedStatusSequence([.notDetermined, .authorized])

        let task = coordinator.requestNotificationPermission(
            requestPermissionIfNeeded: { didRequest = true },
            fetchNotificationAuthorizationStatus: { await source.next() },
            updateNotificationAuthorizationStatus: { statuses.append($0) },
            refreshPermissionStatuses: { refreshCount += 1 },
            pollAttempts: 3,
            pollIntervalNanoseconds: 1_000
        )
        await task.value

        XCTAssertTrue(didRequest)
        XCTAssertEqual(statuses, [.notDetermined, .authorized])
        XCTAssertEqual(refreshCount, 1)
    }

    func testRefreshPermissionStatusesAppliesProbeAndSecureStorageTransition() async {
        let coordinator = AppPermissionCoordinator()
        var secureStorageReady = false
        var didInvalidate = false
        var fullDisk: (Bool, Bool)?
        var notificationStatus: UNAuthorizationStatus?

        let task = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: false,
            updateSecureStorageReady: { secureStorageReady = $0 },
            onSecureStorageBecameReady: { didInvalidate = true },
            fullDiskProbe: { (false, false) },
            applyFullDiskProbe: { fullDisk = ($0, $1) },
            updateNotificationAuthorizationStatus: { notificationStatus = $0 }
        )
        await task.value

        XCTAssertTrue(secureStorageReady)
        XCTAssertTrue(didInvalidate)
        XCTAssertEqual(fullDisk?.0, false)
        XCTAssertEqual(fullDisk?.1, false)
        XCTAssertEqual(notificationStatus, .authorized)
    }

    func testRefreshPermissionStatusesReusesInFlightFullDiskProbeForRepeatedRefreshes() async {
        let coordinator = AppPermissionCoordinator()
        let probe = BlockingFullDiskProbe(result: (false, true))
        var appliedResults: [(Bool, Bool)] = []

        let first = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in }
        )
        XCTAssertTrue(probe.waitForStart())

        let second = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in }
        )

        XCTAssertEqual(probe.callCount, 1)
        probe.release()
        await first.value
        await second.value

        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(appliedResults.map(\.0), [false, false])
        XCTAssertEqual(appliedResults.map(\.1), [true, true])
    }

    func testRefreshPermissionStatusesUsesCachedFullDiskProbeUnlessForced() async {
        let probe = SequencedFullDiskProbe(results: [(false, true), (true, true)])
        let coordinator = AppPermissionCoordinator(
            fullDiskProbeCacheDuration: 60,
            fullDiskProbeThrottleInterval: 5
        )
        var appliedResults: [(Bool, Bool)] = []

        let first = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in },
            forceFullDiskProbe: true
        )
        await first.value

        let cached = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in }
        )
        await cached.value

        let forced = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in },
            forceFullDiskProbe: true
        )
        await forced.value

        XCTAssertEqual(probe.callCount, 2)
        XCTAssertEqual(appliedResults.map(\.0), [false, false, true])
        XCTAssertEqual(appliedResults.map(\.1), [true, true, true])
    }

    func testRefreshPermissionStatusesRefreshesExpiredFullDiskCache() async {
        let clock = MutableDate(Date(timeIntervalSince1970: 1_000))
        let probe = SequencedFullDiskProbe(results: [(false, true), (true, true)])
        let coordinator = AppPermissionCoordinator(
            fullDiskProbeCacheDuration: 10,
            fullDiskProbeThrottleInterval: 1,
            dateProvider: { clock.now }
        )
        var appliedResults: [(Bool, Bool)] = []

        let first = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in }
        )
        await first.value

        clock.advance(by: 11)
        let second = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { true },
            fetchNotificationAuthorizationStatus: { .authorized },
            previousSecureStorageReady: true,
            updateSecureStorageReady: { _ in },
            onSecureStorageBecameReady: {},
            fullDiskProbe: { probe.run() },
            applyFullDiskProbe: { appliedResults.append(($0, $1)) },
            updateNotificationAuthorizationStatus: { _ in }
        )
        await second.value

        XCTAssertEqual(probe.callCount, 2)
        XCTAssertEqual(appliedResults.map(\.0), [false, false, true])
        XCTAssertEqual(appliedResults.map(\.1), [true, true, true])
    }

    func testProbeFullDiskAccessReturnsFalseFalseWhenNoCandidatePathsExist() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("permission-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let result = AppPermissionCoordinator.probeFullDiskAccess(
            fileManager: .default,
            homeDirectory: tempRoot.path
        )

        XCTAssertFalse(result.isGranted)
        XCTAssertFalse(result.isRelevant)
    }
}

private actor LockedStatusSequence {
    private var values: [UNAuthorizationStatus]
    private var index = 0

    init(_ values: [UNAuthorizationStatus]) {
        self.values = values
    }

    func next() -> UNAuthorizationStatus {
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

private final class BlockingFullDiskProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let result: (isGranted: Bool, isRelevant: Bool)
    private var count = 0

    init(result: (isGranted: Bool, isRelevant: Bool)) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { count }
    }

    func run() -> (isGranted: Bool, isRelevant: Bool) {
        lock.withLock { count += 1 }
        started.signal()
        released.wait()
        return result
    }

    func waitForStart(timeout: TimeInterval = 1) -> Bool {
        started.wait(timeout: .now() + timeout) == .success
    }

    func release() {
        released.signal()
    }
}

private final class SequencedFullDiskProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let results: [(isGranted: Bool, isRelevant: Bool)]
    private var count = 0

    init(results: [(isGranted: Bool, isRelevant: Bool)]) {
        self.results = results
    }

    var callCount: Int {
        lock.withLock { count }
    }

    func run() -> (isGranted: Bool, isRelevant: Bool) {
        lock.withLock {
            let index = min(count, results.count - 1)
            count += 1
            return results[index]
        }
    }
}

private final class MutableDate {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
