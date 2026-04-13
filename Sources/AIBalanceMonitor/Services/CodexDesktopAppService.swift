import AppKit
import Foundation

@MainActor
final class CodexDesktopAppService {
    private let runningAppsProvider: () -> [NSRunningApplication]
    private let bundleURLResolver: () -> URL?
    private let openApplication: (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication

    init(
        runningAppsProvider: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
        bundleURLResolver: @escaping () -> URL? = { CodexDesktopAppService.defaultBundleURL() },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication = { url, configuration in
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    ) {
        self.runningAppsProvider = runningAppsProvider
        self.bundleURLResolver = bundleURLResolver
        self.openApplication = openApplication
    }

    @discardableResult
    func restartIfRunning() async -> Bool {
        let initialRunningApps = runningAppsProvider().filter(Self.matches)
        let bundleURL = initialRunningApps.compactMap(\.bundleURL).first ?? bundleURLResolver()
        guard let bundleURL else {
            return false
        }

        // Use force-quit first so apps like Codex do not surface a "confirm quit"
        // sheet that blocks the relaunch path.
        for app in initialRunningApps {
            _ = app.forceTerminate()
        }

        let shutdownDeadline = Date().addingTimeInterval(6.0)
        while Date() < shutdownDeadline {
            let stillRunning = runningAppsProvider().contains(where: Self.matches)
            if !stillRunning {
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        for _ in 0..<3 {
            do {
                _ = try await openApplication(bundleURL, configuration)
                return true
            } catch {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        return false
    }

    private static func defaultBundleURL() -> URL? {
        let workspace = NSWorkspace.shared
        let fileManager = FileManager.default
        let knownBundleIDs = [
            "com.openai.codex",
            "com.openai.chatgpt.codex"
        ]
        for bundleID in knownBundleIDs {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        let candidatePaths = [
            "/Applications/Codex.app",
            "\(NSHomeDirectory())/Applications/Codex.app"
        ]
        if let path = candidatePaths.first(where: { fileManager.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        return workspace.runningApplications.first(where: matches)?.bundleURL
    }

    private static func matches(_ app: NSRunningApplication) -> Bool {
        let localizedName = (app.localizedName ?? "").lowercased()
        let bundleIdentifier = (app.bundleIdentifier ?? "").lowercased()
        let bundleName = app.bundleURL?.lastPathComponent.lowercased() ?? ""
        return localizedName == "codex"
            || bundleName == "codex.app"
            || bundleIdentifier == "com.openai.codex"
            || bundleIdentifier == "com.openai.chatgpt.codex"
    }
}
