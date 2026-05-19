import Foundation

struct KimiDetectedToken: Equatable {
    let token: String
    let source: String
}

final class KimiBrowserCookieService {
    private let cookieReader: BrowserCookieDatabaseReader
    private let storageReader: BrowserStorageCredentialReader
    private let browserOrderDefault: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]

    init(fileManager: FileManager = .default) {
        self.cookieReader = BrowserCookieDatabaseReader(fileManager: fileManager, sqliteTimeout: nil)
        self.storageReader = BrowserStorageCredentialReader(fileManager: fileManager)
    }

    func detectKimiAuthToken(order: [KimiBrowserKind], refreshPaths: Bool = false) -> KimiDetectedToken? {
        for browser in order {
            if let token = tokenFromBrowser(
                browser,
                cookieName: "kimi-auth",
                hostContains: "kimi.com",
                refreshPaths: refreshPaths
            ) {
                return KimiDetectedToken(token: token, source: browserLabel(browser))
            }
            if let token = storageReader.bearerTokenCandidates(
                for: browser,
                hostCandidates: ["www.kimi.com", "kimi.com"],
                source: "\(browserLabel(browser)):localStorage",
                refreshPaths: refreshPaths
            ).first {
                return KimiDetectedToken(token: token.value, source: token.source)
            }
        }
        return nil
    }

    func detectCookieHeader(
        host: String,
        order: [KimiBrowserKind]? = nil,
        refreshPaths: Bool = false
    ) -> KimiDetectedToken? {
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in cookieReader.candidateCookiePaths(for: browser, bypassCache: refreshPaths) {
                if let header = cookieReader.cookieHeader(fromDatabaseAt: path, browser: browser, hostContains: host),
                   !header.isEmpty {
                    return KimiDetectedToken(token: header, source: "\(browserLabel(browser)):cookie")
                }
            }
        }
        return nil
    }

    private func tokenFromBrowser(
        _ browser: KimiBrowserKind,
        cookieName: String,
        hostContains: String,
        refreshPaths: Bool
    ) -> String? {
        for path in cookieReader.candidateCookiePaths(for: browser, bypassCache: refreshPaths) {
            if let token = cookieReader.namedCookieValue(fromDatabaseAt: path, browser: browser, cookieName: cookieName, hostContains: hostContains) {
                return token
            }
        }
        return nil
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
        case .firefox:
            return "auto:Firefox"
        case .opera:
            return "auto:Opera"
        case .operaGX:
            return "auto:OperaGX"
        case .vivaldi:
            return "auto:Vivaldi"
        }
    }
}
