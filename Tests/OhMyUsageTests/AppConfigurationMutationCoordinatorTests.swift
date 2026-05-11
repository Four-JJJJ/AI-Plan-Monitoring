import XCTest
@testable import OhMyUsage

@MainActor
final class AppConfigurationMutationCoordinatorTests: XCTestCase {
    func testPersistConfigurationFailureMapsToFailedFeedback() {
        let coordinator = AppConfigurationMutationCoordinator()
        let repository = StubRepository(
            initialConfig: .default,
            saveError: StubMutationError.failed
        )

        let outcome = coordinator.persistConfiguration(
            .default,
            repository: repository,
            showFeedback: true,
            successText: "saved",
            failureText: "failed"
        )

        XCTAssertFalse(outcome.success)
        XCTAssertEqual(outcome.feedback?.kind, .failed)
        XCTAssertEqual(outcome.feedback?.statusText, "failed")
        XCTAssertEqual(outcome.feedback?.detail, StubMutationError.failed.localizedDescription)
    }

    func testSetLanguageMutatesConfigAndReturnsSavedFeedback() {
        let coordinator = AppConfigurationMutationCoordinator()
        let repository = StubRepository(initialConfig: .default)
        var config = AppConfig.default

        let outcome = coordinator.setLanguage(
            .en,
            config: &config,
            repository: repository,
            showFeedback: true,
            successText: "saved",
            failureText: "failed"
        )

        XCTAssertEqual(config.language, .en)
        XCTAssertEqual(outcome?.success, true)
        XCTAssertEqual(outcome?.feedback?.kind, .saved)
        XCTAssertEqual(outcome?.feedback?.statusText, "saved")
    }

    func testSetResourceModeMutatesConfigAndReturnsSavedFeedback() {
        let coordinator = AppConfigurationMutationCoordinator()
        let repository = StubRepository(initialConfig: .default)
        var config = AppConfig.default

        let outcome = coordinator.setResourceMode(
            .background15Minutes,
            config: &config,
            repository: repository,
            showFeedback: true,
            successText: "saved",
            failureText: "failed"
        )

        XCTAssertEqual(config.resourceMode, .background15Minutes)
        XCTAssertEqual(repository.storedConfig.resourceMode, .background15Minutes)
        XCTAssertEqual(outcome?.success, true)
        XCTAssertEqual(outcome?.feedback?.kind, .saved)
    }

    func testSetLaunchAtLoginEnabledReturnsErrorWithoutMutatingConfigWhenToggleFails() {
        let coordinator = AppConfigurationMutationCoordinator()
        let repository = StubRepository(initialConfig: .default)
        var config = AppConfig.default

        let outcome = coordinator.setLaunchAtLoginEnabled(
            true,
            config: &config,
            setLaunchAtLogin: { _ in throw LaunchAtLoginError.unableToWrite },
            repository: repository,
            showFeedback: true,
            successText: "saved",
            failureText: "failed"
        )

        XCTAssertFalse(config.launchAtLoginEnabled)
        XCTAssertNil(outcome?.persistence)
        XCTAssertEqual(outcome?.errorMessage, LaunchAtLoginError.unableToWrite.localizedDescription)
    }
}

private final class StubRepository: AppConfigurationRepositorying {
    var lastLoadWasLossy = false

    private(set) var storedConfig: AppConfig
    private let saveError: Error?
    private let resetError: Error?

    init(
        initialConfig: AppConfig,
        saveError: Error? = nil,
        resetError: Error? = nil
    ) {
        self.storedConfig = initialConfig
        self.saveError = saveError
        self.resetError = resetError
    }

    func load() throws -> AppConfig {
        storedConfig
    }

    func save(_ config: AppConfig) throws {
        storedConfig = config
        if let saveError { throw saveError }
    }

    func saveDuringBootstrap(_ config: AppConfig) throws {
        try save(config)
    }

    func reset() throws {
        if let resetError { throw resetError }
        storedConfig = .default
    }
}

private enum StubMutationError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "stub mutation failed"
        }
    }
}
