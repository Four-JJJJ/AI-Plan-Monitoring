import Foundation
import XCTest
@testable import OhMyUsage

final class AppConfigurationRepositoryTests: XCTestCase {
    func testRepositoryDelegatesLoadSaveAndReset() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppConfigurationRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = AppConfigurationRepository(store: ConfigStore(baseDirectoryURL: root))

        var config = AppConfig.default
        config.language = .en
        try repository.save(config)

        XCTAssertEqual(try repository.load().language, .en)

        try repository.reset()
        let reloaded = try repository.load()
        XCTAssertEqual(reloaded.language, AppConfig.default.language)
    }
}
