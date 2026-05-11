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
