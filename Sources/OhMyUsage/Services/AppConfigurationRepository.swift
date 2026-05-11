import Foundation

enum ConfigurationMutationResult: Equatable {
    case success
    case failure(String)
}

protocol AppConfigurationRepositorying {
    var lastLoadWasLossy: Bool { get }

    func load() throws -> AppConfig
    func save(_ config: AppConfig) throws
    func saveDuringBootstrap(_ config: AppConfig) throws
    func reset() throws
}

extension AppConfigurationRepositorying {
    func saveResult(_ config: AppConfig) -> ConfigurationMutationResult {
        do {
            try save(config)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func saveDuringBootstrapResult(_ config: AppConfig) -> ConfigurationMutationResult {
        do {
            try saveDuringBootstrap(config)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func resetResult() -> ConfigurationMutationResult {
        do {
            try reset()
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

final class AppConfigurationRepository {
    private let store: ConfigStore

    var lastLoadWasLossy: Bool {
        store.lastLoadWasLossy
    }

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
    }

    func load() throws -> AppConfig {
        try store.load()
    }

    func save(_ config: AppConfig) throws {
        try store.save(config)
    }

    func saveDuringBootstrap(_ config: AppConfig) throws {
        try store.saveDuringBootstrap(config)
    }

    func reset() throws {
        try store.reset()
    }
}

extension AppConfigurationRepository: AppConfigurationRepositorying {}
