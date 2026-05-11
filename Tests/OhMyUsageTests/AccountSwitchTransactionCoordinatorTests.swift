import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AccountSwitchTransactionCoordinatorTests: XCTestCase {
    func testSuccessfulTransactionRunsAllStagesInOrder() async {
        let coordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
        var events: [String] = []

        await coordinator.run(
            slotID: .a,
            prepare: {
                events.append("prepare")
                return "context"
            },
            apply: { context in
                events.append("apply:\(context)")
            },
            restart: { context in
                events.append("restart:\(context)")
                return "restart"
            },
            verify: { context, restart in
                events.append("verify:\(context):\(restart)")
            },
            finalize: { context, restart in
                events.append("finalize:\(context):\(restart)")
            },
            fail: { failure in
                events.append("fail:\(failure.error.localizedDescription)")
            }
        )

        XCTAssertEqual(
            events,
            [
                "prepare",
                "apply:context",
                "restart:context",
                "verify:context:restart",
                "finalize:context:restart"
            ]
        )
        XCTAssertFalse(coordinator.isRunning(slotID: .a))
    }

    func testPrepareFailureSkipsLaterStages() async {
        let coordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
        var events: [String] = []

        await coordinator.run(
            slotID: .a,
            prepare: {
                events.append("prepare")
                throw AccountSwitchTransactionUserMessageError(message: "missing")
            },
            apply: { (_: String) in
                events.append("apply")
            },
            restart: { (_: String) in
                events.append("restart")
            },
            verify: { (_: String, _: Void) in
                events.append("verify")
            },
            finalize: { (_: String, _: Void) in
                events.append("finalize")
            },
            fail: { failure in
                if case .prepare = failure {
                    events.append("fail:prepare")
                }
            }
        )

        XCTAssertEqual(events, ["prepare", "fail:prepare"])
    }

    func testConcurrentSameSlotIsDeduplicated() async throws {
        let coordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
        let counter = SwitchCounter()
        let release = AsyncGate()

        async let first: Void = coordinator.run(
            slotID: .a,
            prepare: {
                "context"
            },
            apply: { _ in
                await counter.increment()
                await release.wait()
            },
            restart: { _ in () },
            verify: { _, _ in },
            finalize: { _, _ in },
            fail: { _ in }
        )

        try await waitUntil {
            await counter.snapshot() == 1
        }

        await coordinator.run(
            slotID: .a,
            prepare: { "duplicate" },
            apply: { _ in await counter.increment() },
            restart: { _ in () },
            verify: { _, _ in },
            finalize: { _, _ in },
            fail: { _ in }
        )

        await release.open()
        await first

        let finalCount = await counter.snapshot()
        XCTAssertEqual(finalCount, 1)
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
        XCTFail("Timed out waiting for transaction state")
    }
}

private actor SwitchCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func snapshot() -> Int {
        value
    }
}

private actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
