import AppKit
import Foundation
import XCTest
@testable import AIPlanMonitor

@MainActor
final class AppViewModelCodexSwitchTests: XCTestCase {
    func testSwitchCodexProfileKeepsAutoApplyWhenDesktopRelaunches() async throws {
        let fixture = try makeFixture(restartResult: .relaunched)
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .b,
            displayName: "Codex B",
            note: "工作",
            authJSON: Self.sampleAuthJSON(accountID: "acc-b", email: "b@example.com")
        )

        await viewModel.switchCodexProfile(slotID: .b)

        XCTAssertEqual(fixture.restartCounter.value, 1)
        XCTAssertEqual(viewModel.codexSwitchFeedback[.b]?.message, viewModel.text(.codexSwitchSuccess))
        XCTAssertEqual(viewModel.codexSlots.first?.slotID, .b)
        XCTAssertTrue(viewModel.codexSlots.first?.isActive == true)
        XCTAssertEqual(viewModel.snapshots["codex-official"]?.rawMeta["codex.slotID"], "B")
    }

    func testSwitchCodexProfileMarksDesktopRestartIncompleteWhenShutdownTimesOut() async throws {
        try await assertSwitchPersistsAndWarnsForManualRelaunch(restartResult: .shutdownTimedOut)
    }

    func testSwitchCodexProfileMarksDesktopRestartIncompleteWhenRelaunchFails() async throws {
        try await assertSwitchPersistsAndWarnsForManualRelaunch(restartResult: .relaunchFailed)
    }

    private func assertSwitchPersistsAndWarnsForManualRelaunch(
        restartResult: CodexDesktopAppRestartResult
    ) async throws {
        let fixture = try makeFixture(restartResult: restartResult)
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: Self.sampleAuthJSON(accountID: "acc-a", email: "a@example.com")
        )

        await viewModel.switchCodexProfile(slotID: .a)

        XCTAssertEqual(fixture.restartCounter.value, 1)
        XCTAssertEqual(
            viewModel.codexSwitchFeedback[.a]?.message,
            viewModel.text(.codexSwitchDesktopRestartIncomplete)
        )
        XCTAssertEqual(viewModel.codexSlots.first?.slotID, .a)
        XCTAssertTrue(viewModel.codexSlots.first?.isActive == true)
        XCTAssertEqual(viewModel.snapshots["codex-official"]?.rawMeta["codex.slotID"], "A")
    }

    private func makeFixture(
        restartResult: CodexDesktopAppRestartResult
    ) throws -> (viewModel: AppViewModel, restartCounter: LockedCounter) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("app-view-model-codex-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let profileStore = CodexAccountProfileStore(
            fileURL: root.appendingPathComponent("codex_profiles.json")
        )
        let slotStore = CodexAccountSlotStore(
            fileURL: root.appendingPathComponent("codex_slots.json")
        )
        let authService = CodexDesktopAuthService(
            homeDirectory: { root.path },
            environment: { ["CODEX_HOME": root.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )
        let restartCounter = LockedCounter()
        let runningState = LockedRunningState(true)
        let appService = makeAppService(
            result: restartResult,
            runningState: runningState,
            restartCounter: restartCounter
        )
        let providerFactory = StubProviderFactory(
            snapshot: Self.makeSnapshot(accountID: "team-a", email: "test@example.com")
        )

        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [codex]),
            appUpdateService: NoopCodexSwitchAppUpdateService(),
            codexSlotStore: slotStore,
            codexProfileStore: profileStore,
            codexDesktopAuthService: authService,
            codexDesktopAppService: appService,
            providerFactory: providerFactory
        )
        return (viewModel, restartCounter)
    }

    private func makeAppService(
        result: CodexDesktopAppRestartResult,
        runningState: LockedRunningState,
        restartCounter: LockedCounter
    ) -> CodexDesktopAppService {
        CodexDesktopAppService(
            runningAppsProvider: {
                runningState.currentValue ? [NSRunningApplication.current] : []
            },
            bundleURLResolver: {
                URL(fileURLWithPath: "/Applications/Codex.app")
            },
            appMatcher: { _ in true },
            gracefulTerminator: { _ in
                restartCounter.increment()
                switch result {
                case .relaunched, .relaunchFailed:
                    Task {
                        try? await Task.sleep(nanoseconds: 15_000_000)
                        runningState.setRunning(false)
                    }
                case .shutdownTimedOut, .notRunning:
                    break
                }
                return true
            },
            forceTerminator: { _ in
                if result == .relaunched {
                    Task {
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        runningState.setRunning(false)
                    }
                }
                return true
            },
            openApplication: { _, _ in
                if result == .relaunchFailed {
                    throw CodexSwitchLaunchFailure()
                }
                return NSRunningApplication.current
            },
            gracefulShutdownTimeout: 0.05,
            forcedShutdownTimeout: 0.05,
            shutdownPollInterval: 0.01,
            relaunchStabilizationDelay: 0.01,
            relaunchRetryDelay: 0.01,
            relaunchAttempts: 3
        )
    }

    private static func makeSnapshot(accountID: String, email: String) -> UsageSnapshot {
        UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 70,
            used: 30,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Official",
            accountLabel: email,
            rawMeta: [
                "codex.accountId": accountID,
                "codex.teamId": accountID,
                "codex.accountKey": "tenant::\(email)",
                "codex.identityKey": "tenant::\(email)",
                "codex.accountLabel": email
            ]
        )
    }

    private static func sampleAuthJSON(accountID: String, email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "access-token-\#(accountID)",
            "refresh_token": "refresh-token-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }
}

private struct StubProviderFactory: ProviderFactorying {
    let snapshot: UsageSnapshot

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        StubUsageProvider(descriptor: descriptor, snapshot: snapshot)
    }
}

private struct StubUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }
}

private actor NoopCodexSwitchAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}

private final class LockedRunningState {
    private let lock = NSLock()
    private var isRunning: Bool

    init(_ isRunning: Bool) {
        self.isRunning = isRunning
    }

    var currentValue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    func setRunning(_ value: Bool) {
        lock.lock()
        isRunning = value
        lock.unlock()
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private struct CodexSwitchLaunchFailure: Error {
}
