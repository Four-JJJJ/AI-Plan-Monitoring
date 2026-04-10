import Foundation

struct KimiDetectedToken: Equatable {
    let token: String
    let source: String
}

final class KimiBrowserCookieService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectKimiAuthToken(order: [KimiBrowserKind]) -> KimiDetectedToken? {
        for browser in order {
            if let token = tokenFromBrowser(browser) {
                return KimiDetectedToken(token: token, source: browserLabel(browser))
            }
        }
        return nil
    }

    private func tokenFromBrowser(_ browser: KimiBrowserKind) -> String? {
        for path in candidateCookiePaths(for: browser) {
            if let token = tokenFromCookieDatabase(path: path) {
                return token
            }
        }
        return nil
    }

    private func candidateCookiePaths(for browser: KimiBrowserKind) -> [String] {
        let home = NSHomeDirectory()
        switch browser {
        case .arc:
            return [
                "\(home)/Library/Application Support/Arc/User Data/Default/Network/Cookies",
                "\(home)/Library/Application Support/Arc/User Data/Profile 1/Network/Cookies",
            ]
        case .chrome:
            return [
                "\(home)/Library/Application Support/Google/Chrome/Default/Network/Cookies",
                "\(home)/Library/Application Support/Google/Chrome/Profile 1/Network/Cookies",
            ]
        case .safari:
            return [
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies/Cookies.sqlite",
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.sqlite",
            ]
        case .edge:
            return [
                "\(home)/Library/Application Support/Microsoft Edge/Default/Network/Cookies",
                "\(home)/Library/Application Support/Microsoft Edge/Profile 1/Network/Cookies",
            ]
        case .brave:
            return [
                "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Network/Cookies",
                "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Profile 1/Network/Cookies",
            ]
        case .chromium:
            return [
                "\(home)/Library/Application Support/Chromium/Default/Network/Cookies",
                "\(home)/Library/Application Support/Chromium/Profile 1/Network/Cookies",
            ]
        }
    }

    private func tokenFromCookieDatabase(path: String) -> String? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let sqlite = resolvedSQLitePath() else { return nil }

        let tempDB = "\(NSTemporaryDirectory())/kimi_cookie_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }

        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        let queries = [
            "SELECT value FROM cookies WHERE name='kimi-auth' AND host_key LIKE '%kimi.com%' ORDER BY LENGTH(value) DESC LIMIT 1;",
            "SELECT value FROM cookies WHERE name='kimi-auth' AND domain LIKE '%kimi.com%' ORDER BY LENGTH(value) DESC LIMIT 1;",
            "SELECT value FROM Cookies WHERE name='kimi-auth' AND host LIKE '%kimi.com%' ORDER BY LENGTH(value) DESC LIMIT 1;",
            "SELECT value FROM Cookies WHERE name='kimi-auth' AND domain LIKE '%kimi.com%' ORDER BY LENGTH(value) DESC LIMIT 1;",
        ]

        for query in queries {
            guard let raw = runProcess(executable: sqlite, arguments: [tempDB, query]) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let decoded = trimmed.removingPercentEncoding, decoded.contains(".") {
                return decoded
            }
            if trimmed.contains(".") {
                return trimmed
            }
        }

        return nil
    }

    private func resolvedSQLitePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/sqlite3",
            "/usr/local/bin/sqlite3",
            "/usr/bin/sqlite3",
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "auto:Arc"
        case .chrome:
            return "auto:Chrome"
        case .safari:
            return "auto:Safari"
        case .edge:
            return "auto:Edge"
        case .brave:
            return "auto:Brave"
        case .chromium:
            return "auto:Chromium"
        }
    }
}
