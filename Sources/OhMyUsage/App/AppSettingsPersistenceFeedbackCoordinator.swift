import Foundation

@MainActor
final class AppSettingsPersistenceFeedbackCoordinator {
    typealias DisplayState = SettingsPersistenceDisplayState
    typealias DisplayKind = SettingsPersistenceDisplayState.Kind
    typealias DisplayTone = UpdateDisplayTone
    typealias StateUpdater = @MainActor (_ state: DisplayState, _ errorMessage: String?) -> Void

    private static let idleState = DisplayState(
        kind: .idle,
        statusText: nil,
        tone: .neutral
    )

    private let clearDelaySeconds: TimeInterval
    private var clearTask: Task<Void, Never>?

    init(clearDelaySeconds: TimeInterval) {
        self.clearDelaySeconds = max(0, clearDelaySeconds)
    }

    @discardableResult
    func apply(
        _ outcome: AppConfigurationPersistenceOutcome,
        update: @escaping StateUpdater
    ) -> Bool {
        if let feedback = outcome.feedback {
            setStatus(
                kind: feedback.kind,
                statusText: feedback.statusText,
                tone: feedback.tone,
                detail: feedback.detail,
                update: update
            )
        }
        return outcome.success
    }

    func setStatus(
        kind: DisplayKind,
        statusText: String?,
        tone: DisplayTone,
        detail: String? = nil,
        update: @escaping StateUpdater
    ) {
        clearTask?.cancel()
        clearTask = nil
        update(
            DisplayState(
                kind: kind,
                statusText: statusText,
                tone: tone
            ),
            detail
        )

        guard kind != .idle else { return }
        let clearDelayNanoseconds = UInt64(clearDelaySeconds * 1_000_000_000)
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: clearDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.clearTask = nil
            update(Self.idleState, nil)
        }
    }
}
