import Foundation

final class AppConfigurationRepository {
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
    }

    func load() throws -> AppConfig {
        try store.load()
    }

    func save(_ config: AppConfig) throws {
        try store.save(config)
    }

    func reset() throws {
        try store.reset()
    }
}
