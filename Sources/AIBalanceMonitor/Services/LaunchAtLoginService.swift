import Foundation

enum LaunchAtLoginError: LocalizedError {
    case missingBundlePath
    case unableToWrite

    var errorDescription: String? {
        switch self {
        case .missingBundlePath:
            return "Unable to locate the current app bundle."
        case .unableToWrite:
            return "Unable to update the launch-at-login agent."
        }
    }
}

final class LaunchAtLoginService {
    private let fileManager: FileManager
    private let homeDirectory: () -> String
    private let bundlePathProvider: () -> String
    private let commandRunner: (String, [String]) -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        bundlePathProvider: @escaping () -> String = { Bundle.main.bundlePath },
        commandRunner: @escaping (String, [String]) -> Void = { executable, arguments in
            _ = ShellCommand.run(executable: executable, arguments: arguments, timeout: 5)
        }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.bundlePathProvider = bundlePathProvider
        self.commandRunner = commandRunner
    }

    func isEnabled() -> Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writeLaunchAgent()
            loadLaunchAgent()
        } else {
            unloadLaunchAgent()
            removeLaunchAgent()
        }
    }

    private var plistURL: URL {
        URL(fileURLWithPath: homeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.aibalancemonitor.app.launchatlogin.plist")
    }

    private var launchAgentLabel: String {
        "com.aibalancemonitor.app.launchatlogin"
    }

    private func writeLaunchAgent() throws {
        let bundlePath = bundlePathProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundlePath.isEmpty else {
            throw LaunchAtLoginError.missingBundlePath
        }

        let directory = plistURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LaunchAtLoginError.unableToWrite
        }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", bundlePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": ["Aqua"]
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            throw LaunchAtLoginError.unableToWrite
        }
    }

    private func removeLaunchAgent() {
        try? fileManager.removeItem(at: plistURL)
    }

    private func loadLaunchAgent() {
        let domain = "gui/\(getuid())"
        commandRunner("/bin/launchctl", ["bootout", domain, plistURL.path])
        commandRunner("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    private func unloadLaunchAgent() {
        let domain = "gui/\(getuid())"
        commandRunner("/bin/launchctl", ["bootout", domain, plistURL.path])
    }
}
