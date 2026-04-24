import AppKit
import XCTest
@testable import AIPlanMonitor

@MainActor
final class CodexDesktopAppServiceTests: XCTestCase {
    func testRestartIfRunningDoesNotLaunchCodexWhenNotAlreadyRunning() async {
        var openCallCount = 0
        let service = CodexDesktopAppService(
            runningAppsProvider: { [] },
            bundleURLResolver: { URL(fileURLWithPath: "/Applications/Codex.app") },
            openApplication: { _, _ in
                openCallCount += 1
                return NSRunningApplication.current
            }
        )

        let restarted = await service.restartIfRunning()

        XCTAssertFalse(restarted)
        XCTAssertEqual(openCallCount, 0)
    }

    func testRestartIfRunningRelaunchesWhenCodexIsAlreadyRunning() async {
        let runningApp = NSRunningApplication.current
        var runningApps = [runningApp]
        var forceTerminateCallCount = 0
        var openedURL: URL?
        var openActivates: Bool?

        let service = CodexDesktopAppService(
            runningAppsProvider: { runningApps },
            bundleURLResolver: { URL(fileURLWithPath: "/Applications/Codex.app") },
            appMatcher: { $0 == runningApp },
            forceTerminator: { app in
                XCTAssertEqual(app, runningApp)
                forceTerminateCallCount += 1
                runningApps = []
                return true
            },
            openApplication: { url, configuration in
                openedURL = url
                openActivates = configuration.activates
                return runningApp
            }
        )

        let restarted = await service.restartIfRunning()

        XCTAssertTrue(restarted)
        XCTAssertEqual(forceTerminateCallCount, 1)
        XCTAssertEqual(openedURL, URL(fileURLWithPath: "/Applications/Codex.app"))
        XCTAssertEqual(openActivates, true)
    }
}
