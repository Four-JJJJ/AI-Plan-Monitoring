import XCTest
@testable import OhMyUsage

final class LaunchAtLoginServiceTests: XCTestCase {
    func testEnableWritesLaunchAgentPlist() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var commands: [(String, [String])] = []
        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/oh-myusage.app" },
            commandRunner: { executable, arguments in
                commands.append((executable, arguments))
            }
        )

        try service.setEnabled(true)

        let plistURL = tempRoot
            .appendingPathComponent("Library/LaunchAgents/com.oh-myusage.app.launchatlogin.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, "com.oh-myusage.app.launchatlogin")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/open", "/Applications/oh-myusage.app"])
        XCTAssertEqual(commands.count, 2)
    }

    func testDisableRemovesLaunchAgentPlist() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/oh-myusage.app" },
            commandRunner: { _, _ in }
        )

        try service.setEnabled(true)
        try service.setEnabled(false)

        let plistURL = tempRoot
            .appendingPathComponent("Library/LaunchAgents/com.oh-myusage.app.launchatlogin.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(service.isEnabled())
    }

    func testIsEnabledReturnsTrueWhenLegacyLaunchAgentExists() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let legacyURL = try writeLegacyLaunchAgent(
            filename: "com.aiplanmonitor.app.launchatlogin.plist",
            in: tempRoot
        )
        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/oh-myusage.app" },
            commandRunner: { _, _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(service.isEnabled())
    }

    func testMigrateLegacyLaunchAgentsWritesCurrentPlistAndRemovesLegacyPlists() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try writeLegacyLaunchAgent(
            filename: "com.aiplanmonitor.app.launchatlogin.plist",
            in: tempRoot
        )
        _ = try writeLegacyLaunchAgent(
            filename: "com.aibalancemonitor.app.launchatlogin.plist",
            in: tempRoot
        )
        var commands: [(String, [String])] = []
        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/oh-myusage.app" },
            commandRunner: { executable, arguments in
                commands.append((executable, arguments))
            }
        )

        service.migrateLegacyLaunchAgentsIfNeeded()

        let currentURL = launchAgentsDirectory(in: tempRoot)
            .appendingPathComponent("com.oh-myusage.app.launchatlogin.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: launchAgentsDirectory(in: tempRoot)
                    .appendingPathComponent("com.aiplanmonitor.app.launchatlogin.plist")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: launchAgentsDirectory(in: tempRoot)
                    .appendingPathComponent("com.aibalancemonitor.app.launchatlogin.plist")
                    .path
            )
        )
        XCTAssertTrue(commands.contains { $0.1 == ["bootstrap", "gui/\(getuid())", currentURL.path] })
    }

    func testDisableRemovesLegacyLaunchAgentPlists() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try writeLegacyLaunchAgent(
            filename: "com.aiplanmonitor.app.launchatlogin.plist",
            in: tempRoot
        )
        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/oh-myusage.app" },
            commandRunner: { _, _ in }
        )

        try service.setEnabled(false)

        XCTAssertFalse(service.isEnabled())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: launchAgentsDirectory(in: tempRoot)
                    .appendingPathComponent("com.aiplanmonitor.app.launchatlogin.plist")
                    .path
            )
        )
    }

    private func makeTempRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    private func launchAgentsDirectory(in root: URL) -> URL {
        root.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private func writeLegacyLaunchAgent(filename: String, in root: URL) throws -> URL {
        let directory = launchAgentsDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try Data("legacy".utf8).write(to: url, options: .atomic)
        return url
    }
}
