import AppKit
import Foundation

enum CodexDesktopAppRestartResult: Equatable {
    case notRunning
    case relaunched
    case shutdownTimedOut
    case relaunchFailed

    var requiresManualRelaunch: Bool {
        switch self {
        case .shutdownTimedOut, .relaunchFailed:
            return true
        case .notRunning, .relaunched:
            return false
        }
    }
}

@MainActor
final class CodexDesktopAppService {
    private let runningAppsProvider: () -> [NSRunningApplication]
    private let bundleURLResolver: () -> URL?
    private let appMatcher: (NSRunningApplication) -> Bool
    private let gracefulTerminator: (NSRunningApplication) -> Bool
    private let forceTerminator: (NSRunningApplication) -> Bool
    private let openApplication: (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication
    private let gracefulShutdownTimeout: TimeInterval
    private let forcedShutdownTimeout: TimeInterval
    private let shutdownPollInterval: TimeInterval
    private let relaunchStabilizationDelay: TimeInterval
    private let relaunchRetryDelay: TimeInterval
    private let relaunchAttempts: Int

    init(
        runningAppsProvider: @escaping () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications },
        bundleURLResolver: @escaping () -> URL? = { CodexDesktopAppService.defaultBundleURL() },
        appMatcher: @escaping (NSRunningApplication) -> Bool = CodexDesktopAppService.matches,
        gracefulTerminator: @escaping (NSRunningApplication) -> Bool = { $0.terminate() },
        forceTerminator: @escaping (NSRunningApplication) -> Bool = { $0.forceTerminate() },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication = { url, configuration in
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        },
        gracefulShutdownTimeout: TimeInterval = 4.0,
        forcedShutdownTimeout: TimeInterval = 2.0,
        shutdownPollInterval: TimeInterval = 0.25,
        relaunchStabilizationDelay: TimeInterval = 0.35,
        relaunchRetryDelay: TimeInterval = 0.8,
        relaunchAttempts: Int = 3
    ) {
        self.runningAppsProvider = runningAppsProvider
        self.bundleURLResolver = bundleURLResolver
        self.appMatcher = appMatcher
        self.gracefulTerminator = gracefulTerminator
        self.forceTerminator = forceTerminator
        self.openApplication = openApplication
        self.gracefulShutdownTimeout = gracefulShutdownTimeout
        self.forcedShutdownTimeout = forcedShutdownTimeout
        self.shutdownPollInterval = shutdownPollInterval
        self.relaunchStabilizationDelay = relaunchStabilizationDelay
        self.relaunchRetryDelay = relaunchRetryDelay
        self.relaunchAttempts = max(1, relaunchAttempts)
    }

    func isRunning() -> Bool {
        runningAppsProvider().contains(where: appMatcher)
    }

    @discardableResult
    func restartIfRunning() async -> CodexDesktopAppRestartResult {
        let initialRunningApps = runningAppsProvider().filter(appMatcher)
        guard !initialRunningApps.isEmpty else {
            return .notRunning
        }
        let bundleURL = initialRunningApps.compactMap(\.bundleURL).first ?? bundleURLResolver()
        guard let bundleURL else { return .relaunchFailed }

        for app in initialRunningApps {
            _ = gracefulTerminator(app)
        }

        let didGracefullyExit = await waitUntilAppStopsRunning(timeout: gracefulShutdownTimeout)
        if !didGracefullyExit {
            for app in runningAppsProvider().filter(appMatcher) {
                _ = forceTerminator(app)
            }
        }

        let didFullyExit: Bool
        if didGracefullyExit {
            didFullyExit = true
        } else {
            didFullyExit = await waitUntilAppStopsRunning(timeout: forcedShutdownTimeout)
        }
        guard didFullyExit else {
            return .shutdownTimedOut
        }

        if relaunchStabilizationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(relaunchStabilizationDelay * 1_000_000_000))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        for attempt in 0..<relaunchAttempts {
            do {
                _ = try await openApplication(bundleURL, configuration)
                return .relaunched
            } catch {
                guard attempt < relaunchAttempts - 1 else { break }
                if relaunchRetryDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(relaunchRetryDelay * 1_000_000_000))
                }
            }
        }
        return .relaunchFailed
    }

    private func waitUntilAppStopsRunning(timeout: TimeInterval) async -> Bool {
        guard timeout > 0 else {
            return !isRunning()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(shutdownPollInterval * 1_000_000_000))
        }
        return !isRunning()
    }

    nonisolated private static func defaultBundleURL() -> URL? {
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

    nonisolated private static func matches(_ app: NSRunningApplication) -> Bool {
        let localizedName = (app.localizedName ?? "").lowercased()
        let bundleIdentifier = (app.bundleIdentifier ?? "").lowercased()
        let bundleName = app.bundleURL?.lastPathComponent.lowercased() ?? ""
        return localizedName == "codex"
            || bundleName == "codex.app"
            || bundleIdentifier == "com.openai.codex"
            || bundleIdentifier == "com.openai.chatgpt.codex"
    }
}
