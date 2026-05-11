import Foundation

@MainActor
final class AppTransientFeedbackCoordinator<Key: Hashable, Feedback: Equatable> {
    private var tasks: [Key: Task<Void, Never>] = [:]
    private let clearDelayNanoseconds: UInt64

    init(clearDelayNanoseconds: UInt64 = 5_000_000_000) {
        self.clearDelayNanoseconds = clearDelayNanoseconds
    }

    func set(
        _ feedback: Feedback?,
        for key: Key,
        currentValue: @escaping @MainActor (Key) -> Feedback?,
        setValue: @escaping @MainActor (Key, Feedback?) -> Void
    ) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)

        guard let feedback else {
            setValue(key, nil)
            return
        }

        setValue(key, feedback)
        tasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.clearDelayNanoseconds ?? 0)
            guard let self, !Task.isCancelled else { return }
            if currentValue(key) == feedback {
                setValue(key, nil)
            }
            self.tasks.removeValue(forKey: key)
        }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
