import Foundation

enum CodexAuthPathResolver {
    static func resolveAuthPaths(homeDirectory: String, environment: [String: String]) -> [String] {
        let codexHome = normalizedPath(environment["CODEX_HOME"])
        let xdgConfigHome = normalizedPath(environment["XDG_CONFIG_HOME"])
        let normalizedHome = normalizedPath(homeDirectory)

        let candidates: [String?] = [
            codexHome.map(authPath(in:)),
            xdgConfigHome.map(xdgAuthPath(in:)),
            normalizedHome.map(homeConfigAuthPath(in:)),
            normalizedHome.map(homeCodexAuthPath(in:))
        ]

        var deduplicated: [String] = []
        var seen: Set<String> = []
        for path in candidates.compactMap({ $0 }) {
            if seen.insert(path).inserted {
                deduplicated.append(path)
            }
        }
        return deduplicated
    }

    private static func normalizedPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func authPath(in directory: String) -> String {
        URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private static func xdgAuthPath(in directory: String) -> String {
        URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private static func homeConfigAuthPath(in homeDirectory: String) -> String {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    private static func homeCodexAuthPath(in homeDirectory: String) -> String {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }
}
