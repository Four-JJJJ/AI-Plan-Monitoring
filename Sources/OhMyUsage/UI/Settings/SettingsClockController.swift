import OhMyUsageApplication
import Foundation

@MainActor
final class SettingsClockController {
    func restartClockIfNeeded(
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

    func stopClock(existingTask: inout Task<Void, Never>?) {
        existingTask?.cancel()
        existingTask = nil
    }

    func tick(
        referenceDate: Date = Date(),
        update: (Date) -> Void
    ) {
        update(referenceDate)
    }
}
