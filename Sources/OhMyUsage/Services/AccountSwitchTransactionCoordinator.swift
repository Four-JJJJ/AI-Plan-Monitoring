import Foundation

enum AccountSwitchTransactionFailure {
    case prepare(Error)
    case apply(Error)
    case restart(Error)
    case verify(Error)

    var error: Error {
        switch self {
        case .prepare(let error), .apply(let error), .restart(let error), .verify(let error):
            return error
        }
    }
}

struct AccountSwitchTransactionUserMessageError: LocalizedError, Equatable {
    var message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
final class AccountSwitchTransactionCoordinator<SlotID: Hashable> {
    private var runningSlotIDs: Set<SlotID> = []

    var activeSlotIDs: Set<SlotID> {
        runningSlotIDs
    }

    func isRunning(slotID: SlotID) -> Bool {
        runningSlotIDs.contains(slotID)
    }

    func reset() {
        runningSlotIDs.removeAll()
    }

    func run<Context, RestartResult>(
        slotID: SlotID,
        prepare: () throws -> Context,
        apply: (Context) async throws -> Void,
        restart: (Context) async throws -> RestartResult,
        verify: (Context, RestartResult) async throws -> Void,
        finalize: (Context, RestartResult) async -> Void,
        fail: (AccountSwitchTransactionFailure) async -> Void
    ) async {
        guard runningSlotIDs.insert(slotID).inserted else { return }
        defer { runningSlotIDs.remove(slotID) }

        let context: Context
        do {
            context = try prepare()
        } catch {
            await fail(.prepare(error))
            return
        }

        do {
            try await apply(context)
        } catch {
            await fail(.apply(error))
            return
        }

        let restartResult: RestartResult
        do {
            restartResult = try await restart(context)
        } catch {
            await fail(.restart(error))
            return
        }

        do {
            try await verify(context, restartResult)
        } catch {
            await fail(.verify(error))
            return
        }

        await finalize(context, restartResult)
    }
}
