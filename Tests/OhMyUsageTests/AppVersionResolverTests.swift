import XCTest
@testable import OhMyUsage

final class AppVersionResolverTests: XCTestCase {
    func testIsVersionComparesNormalizedComponents() {
        XCTAssertTrue(AppVersionResolver.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertTrue(AppVersionResolver.isVersion("v2.0", newerThan: "1.99.99"))
        XCTAssertFalse(AppVersionResolver.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(AppVersionResolver.isVersion("1.2", newerThan: "1.2.5"))
    }

    func testIsVersionIgnoresNonDigitSuffixesAfterNormalization() {
        XCTAssertTrue(AppVersionResolver.isVersion("1.2.3-beta4", newerThan: "1.2.2"))
        XCTAssertFalse(AppVersionResolver.isVersion("1.2.3-alpha", newerThan: "1.2.3"))
    }

    func testDetectNewestInstalledAppVersionIncludesLegacyBundleName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let legacyBundle = home
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("AI Plan Monitor.app", isDirectory: true)
        try writeBundleVersion("2.0.0", to: legacyBundle)

        let detected = AppVersionResolver.detectNewestInstalledAppVersion(
            fallbackVersion: "1.8.6",
            fileManager: HomeDirectoryFileManager(homeDirectory: home)
        )

        XCTAssertEqual(detected, "2.0.0")
    }

    private func writeBundleVersion(_ version: String, to bundleURL: URL) throws {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleExecutable": "OhMyUsage",
            "CFBundleIdentifier": "com.oh-myusage.app",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }
}

private final class HomeDirectoryFileManager: FileManager {
    private let homeDirectory: URL

    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        homeDirectory
    }

    override func fileExists(atPath path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedPath.hasPrefix(homeDirectory.path) else {
            return false
        }
        return super.fileExists(atPath: path)
    }
}
