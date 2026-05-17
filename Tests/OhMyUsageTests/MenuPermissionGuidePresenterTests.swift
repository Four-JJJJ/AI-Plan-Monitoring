import XCTest
import OhMyUsagePresentation
@testable import OhMyUsage

final class MenuPermissionGuidePresenterTests: XCTestCase {
    func testBuildHidesCompletedActionsAndOmitsIrrelevantFullDiskRow() {
        let presentation = MenuPermissionGuidePresenter.build(
            language: .en,
            hasNotificationPermission: true,
            secureStorageReady: true,
            fullDiskAccessRelevant: false,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: false,
            localDiscoveryState: .idle
        )

        XCTAssertEqual(presentation.title, "Permissions & auto-discovery")
        XCTAssertEqual(presentation.rows.map(\.kind), [.notifications, .keychain])
        XCTAssertEqual(presentation.rows.map(\.statusText), ["Allowed", "Allowed"])
        XCTAssertTrue(presentation.rows.allSatisfy { $0.actionTitle == nil })
    }

    func testBuildShowsActionablePendingRowsAndWaitingFullDiskState() {
        let presentation = MenuPermissionGuidePresenter.build(
            language: .zhHans,
            hasNotificationPermission: false,
            secureStorageReady: false,
            fullDiskAccessRelevant: true,
            fullDiskAccessRequested: true,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: false,
            localDiscoveryState: .idle
        )

        XCTAssertEqual(presentation.rows.map(\.kind), [.notifications, .keychain, .fullDisk])
        XCTAssertEqual(presentation.rows.map(\.statusText), ["待授权", "待授权", "待确认"])
        XCTAssertEqual(presentation.rows.map(\.tone), [.warning, .warning, .warning])
        XCTAssertEqual(
            presentation.rows.compactMap(\.actionKind),
            [.requestNotifications, .prepareKeychain, .openFullDiskSettings]
        )
    }

    func testBuildReflectsLocalDiscoveryStateWithoutOwningDiscoveryMessage() {
        let idle = MenuPermissionGuidePresenter.build(
            language: .en,
            hasNotificationPermission: true,
            secureStorageReady: true,
            fullDiskAccessRelevant: false,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: true,
            localDiscoveryState: .idle
        )
        let inFlight = MenuPermissionGuidePresenter.build(
            language: .en,
            hasNotificationPermission: true,
            secureStorageReady: true,
            fullDiskAccessRelevant: false,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: true,
            localDiscoveryState: .inFlight
        )
        let completed = MenuPermissionGuidePresenter.build(
            language: .en,
            hasNotificationPermission: true,
            secureStorageReady: true,
            fullDiskAccessRelevant: false,
            fullDiskAccessRequested: false,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: true,
            localDiscoveryState: .completed
        )

        XCTAssertEqual(idle.rows.last?.kind, .localDiscovery)
        XCTAssertEqual(idle.rows.last?.statusText, "Ready")
        XCTAssertEqual(idle.rows.last?.actionKind, .runLocalDiscovery)
        XCTAssertEqual(inFlight.rows.last?.statusText, "Waiting")
        XCTAssertNil(inFlight.rows.last?.actionTitle)
        XCTAssertEqual(completed.rows.last?.statusText, "Done")
        XCTAssertEqual(completed.rows.last?.actionKind, .runLocalDiscovery)
    }

    func testPresentationModelOwnsPermissionRowFormattingRules() {
        let presentation = OhMyUsagePresentation.MenuPermissionGuidePresentation.build(
            strings: OhMyUsagePresentation.MenuPermissionGuideStrings(
                title: "Permissions",
                privacyPromise: "Local only",
                notifications: .init(title: "Notifications", hint: "Alert on changes", actionTitle: "Allow"),
                keychain: .init(title: "Keychain", hint: "Store secrets", actionTitle: "Prepare"),
                fullDisk: .init(title: "Full Disk", hint: "Read local logs", actionTitle: "Open Settings"),
                localDiscovery: .init(title: "Discovery", hint: "Find local sources", actionTitle: "Scan"),
                grantedStatusText: "Allowed",
                pendingStatusText: "Pending",
                waitingStatusText: "Waiting",
                localDiscoveryReadyStatusText: "Ready",
                localDiscoveryDoneStatusText: "Done"
            ),
            hasNotificationPermission: false,
            secureStorageReady: true,
            fullDiskAccessRelevant: true,
            fullDiskAccessRequested: true,
            fullDiskAccessGranted: false,
            canRunLocalDiscovery: true,
            localDiscoveryState: .inFlight
        )

        XCTAssertEqual(presentation.rows.map(\.kind), [.notifications, .keychain, .fullDisk, .localDiscovery])
        XCTAssertEqual(presentation.rows.map(\.statusText), ["Pending", "Allowed", "Waiting", "Waiting"])
        XCTAssertEqual(presentation.rows.map(\.tone), [.warning, .success, .warning, .warning])
        XCTAssertEqual(
            presentation.rows.map(\.actionKind),
            [.requestNotifications, nil, .openFullDiskSettings, nil]
        )
    }
}
