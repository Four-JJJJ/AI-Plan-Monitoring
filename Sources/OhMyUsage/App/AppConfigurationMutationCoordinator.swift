import Foundation

struct AppConfigurationPersistenceFeedback: Equatable {
    var kind: SettingsPersistenceDisplayState.Kind
    var statusText: String
    var tone: UpdateDisplayTone
    var detail: String?
}

struct AppConfigurationPersistenceOutcome: Equatable {
    var success: Bool
    var feedback: AppConfigurationPersistenceFeedback?
}

struct AppLaunchAtLoginMutationOutcome: Equatable {
    var persistence: AppConfigurationPersistenceOutcome?
    var errorMessage: String?
}

@MainActor
final class AppConfigurationMutationCoordinator {
    func setLanguage(
        _ language: AppLanguage,
        config: inout AppConfig,
        repository: any AppConfigurationRepositorying,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppConfigurationPersistenceOutcome? {
        guard config.language != language else { return nil }
        config.language = language
        return persistConfiguration(
            config,
            repository: repository,
            showFeedback: showFeedback,
            successText: successText,
            failureText: failureText
        )
    }

    func setResourceMode(
        _ resourceMode: ResourceMode,
        config: inout AppConfig,
        repository: any AppConfigurationRepositorying,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppConfigurationPersistenceOutcome? {
        guard config.resourceMode != resourceMode else { return nil }
        config.resourceMode = resourceMode
        return persistConfiguration(
            config,
            repository: repository,
            showFeedback: showFeedback,
            successText: successText,
            failureText: failureText
        )
    }

    func setLaunchAtLoginEnabled(
        _ enabled: Bool,
        config: inout AppConfig,
        setLaunchAtLogin: (Bool) throws -> Void,
        repository: any AppConfigurationRepositorying,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppLaunchAtLoginMutationOutcome? {
        guard config.launchAtLoginEnabled != enabled else { return nil }
        do {
            try setLaunchAtLogin(enabled)
            config.launchAtLoginEnabled = enabled
            return AppLaunchAtLoginMutationOutcome(
                persistence: persistConfiguration(
                    config,
                    repository: repository,
                    showFeedback: showFeedback,
                    successText: successText,
                    failureText: failureText
                ),
                errorMessage: nil
            )
        } catch {
            return AppLaunchAtLoginMutationOutcome(
                persistence: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    func persistConfiguration(
        _ config: AppConfig,
        repository: any AppConfigurationRepositorying,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppConfigurationPersistenceOutcome {
        mapMutationResult(
            repository.saveResult(config),
            showFeedback: showFeedback,
            successText: successText,
            failureText: failureText
        )
    }

    func resetConfiguration(
        repository: any AppConfigurationRepositorying,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppConfigurationPersistenceOutcome {
        mapMutationResult(
            repository.resetResult(),
            showFeedback: showFeedback,
            successText: successText,
            failureText: failureText
        )
    }

    private func mapMutationResult(
        _ result: ConfigurationMutationResult,
        showFeedback: Bool,
        successText: String,
        failureText: String
    ) -> AppConfigurationPersistenceOutcome {
        switch result {
        case .success:
            let feedback = showFeedback
                ? AppConfigurationPersistenceFeedback(
                    kind: .saved,
                    statusText: successText,
                    tone: .positive,
                    detail: nil
                )
                : nil
            return AppConfigurationPersistenceOutcome(success: true, feedback: feedback)
        case .failure(let message):
            let feedback = showFeedback
                ? AppConfigurationPersistenceFeedback(
                    kind: .failed,
                    statusText: failureText,
                    tone: .negative,
                    detail: message
                )
                : nil
            return AppConfigurationPersistenceOutcome(success: false, feedback: feedback)
        }
    }
}
