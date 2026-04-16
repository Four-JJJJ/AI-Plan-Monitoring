import XCTest
@testable import AIPlanMonitor

final class LaunchAtLoginServiceTests: XCTestCase {
    func testEnableWritesLaunchAgentPlist() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var commands: [(String, [String])] = []
        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/AI Plan Monitor.app" },
            commandRunner: { executable, arguments in
                commands.append((executable, arguments))
            }
        )

        try service.setEnabled(true)

        let plistURL = tempRoot
            .appendingPathComponent("Library/LaunchAgents/com.aiplanmonitor.app.launchatlogin.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, "com.aiplanmonitor.app.launchatlogin")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/open", "/Applications/AI Plan Monitor.app"])
        XCTAssertEqual(commands.count, 2)
    }

    func testDisableRemovesLaunchAgentPlist() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = LaunchAtLoginService(
            fileManager: .default,
            homeDirectory: { tempRoot.path },
            bundlePathProvider: { "/Applications/AI Plan Monitor.app" },
            commandRunner: { _, _ in }
        )

        try service.setEnabled(true)
        try service.setEnabled(false)

        let plistURL = tempRoot
            .appendingPathComponent("Library/LaunchAgents/com.aiplanmonitor.app.launchatlogin.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(service.isEnabled())
    }
}
