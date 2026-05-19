import Foundation

@MainActor
package final class VisibleClockController {
    package init() {}

    package func restartClockIfNeeded(
        isVisible: Bool,
        existingTask: inout Task<Void, Never>?,
        intervalSeconds: TimeInterval = RuntimeDiagnosticsLimits.settingsClockIntervalSeconds,
        tick: @escaping @MainActor (Date) -> Void
    ) {
        guard isVisible else {
            stopClock(existingTask: &existingTask)
            return
        }

        if let task = existingTask, !task.isCancelled {
            return
        }

        stopClock(existingTask: &existingTask)

        tick(Date())
        existingTask = Task { @MainActor in
            let interval = max(1, intervalSeconds)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                tick(Date())
            }
        }
    }

    package func stopClock(existingTask: inout Task<Void, Never>?) {
        existingTask?.cancel()
        existingTask = nil
    }

    package func tick(
        referenceDate: Date = Date(),
        update: (Date) -> Void
    ) {
        update(referenceDate)
    }
}
