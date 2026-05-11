import Foundation

@MainActor
final class AppResetCoordinator {
    struct ResetHooks {
        var stopPollingAndTransientTasks: @MainActor () -> Void
        var cancelOAuthImports: @MainActor () -> Void
        var resetRuntimeComponents: @MainActor () -> Void
        var clearInMemoryState: @MainActor () -> Void
        var resetPersistentState: @MainActor () -> Void
        var restoreDefaultState: @MainActor () -> Void
        var rebootstrap: @MainActor () -> Void
    }

    func resetLocalAppData(using hooks: ResetHooks) {
        hooks.stopPollingAndTransientTasks()
        hooks.cancelOAuthImports()
        hooks.resetRuntimeComponents()
        hooks.clearInMemoryState()
        hooks.resetPersistentState()
        hooks.restoreDefaultState()
        hooks.rebootstrap()
    }
}
