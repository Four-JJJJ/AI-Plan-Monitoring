import Foundation

extension AppConfig {
    func migratedWithSiteDefaults() -> AppConfig {
        AppConfigSiteDefaultsMigrator.migrated(self)
    }
}
