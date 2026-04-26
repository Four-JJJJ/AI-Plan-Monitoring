import Foundation
import XCTest
@testable import AIPlanMonitor

final class CodexAuthPathResolverTests: XCTestCase {
    func testResolveAuthPathsIncludesExpectedSourcesInOrder() {
        let home = "/tmp/home-user"
        let environment = [
            "CODEX_HOME": " /tmp/codex-home/ ",
            "XDG_CONFIG_HOME": "/tmp/xdg-config"
        ]

        let paths = CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: home,
            environment: environment
        )

        XCTAssertEqual(
            paths,
            [
                authPath(in: "/tmp/codex-home"),
                xdgAuthPath(in: "/tmp/xdg-config"),
                homeConfigAuthPath(in: home),
                homeCodexAuthPath(in: home)
            ]
        )
    }

    func testResolveAuthPathsDeduplicatesOverlappingDirectories() {
        let home = "/tmp/home-user"
        let environment = [
            "CODEX_HOME": "/tmp/home-user/.codex",
            "XDG_CONFIG_HOME": "/tmp/home-user/.config"
        ]

        let paths = CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: home,
            environment: environment
        )

        XCTAssertEqual(
            paths,
            [
                authPath(in: "/tmp/home-user/.codex"),
                xdgAuthPath(in: "/tmp/home-user/.config")
            ]
        )
    }

    func testDesktopServiceAndProviderShareResolvedAuthPaths() {
        let home = "/tmp/shared-home"
        let environment = [
            "CODEX_HOME": "/tmp/shared-codex",
            "XDG_CONFIG_HOME": "/tmp/shared-xdg"
        ]
        let service = CodexDesktopAuthService(
            homeDirectory: { home },
            environment: { environment }
        )

        let servicePaths = service.resolvedAuthPaths()
        let providerPaths = CodexProvider.resolvedAuthPaths(
            homeDirectory: home,
            environment: environment
        )

        XCTAssertEqual(servicePaths, providerPaths)
    }

    func testResolveAuthPathsFallsBackToInjectedHomeWhenEnvironmentIsEmpty() {
        let home = "/tmp/injected-home"

        let paths = CodexProvider.resolvedAuthPaths(
            homeDirectory: home,
            environment: [:]
        )

        XCTAssertEqual(
            paths,
            [
                homeConfigAuthPath(in: home),
                homeCodexAuthPath(in: home)
            ]
        )
    }

    private func authPath(in directory: String) -> String {
        URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private func xdgAuthPath(in directory: String) -> String {
        URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private func homeConfigAuthPath(in home: String) -> String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private func homeCodexAuthPath(in home: String) -> String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }
}
