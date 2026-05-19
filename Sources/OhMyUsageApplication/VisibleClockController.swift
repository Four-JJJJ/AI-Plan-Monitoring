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
        stopClock(existingTask: &existingTask)
        guard isVisible else { return }

        tick(Date())
        existingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
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
