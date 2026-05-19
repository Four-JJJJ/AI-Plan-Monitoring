import OhMyUsageDomain
import Foundation

struct OfficialBrowserCookieImportStrategy {
    let providerKey: String
    let hostContains: String
    let namedCookie: String?
    let autoImportMissingCredential: String
    let manualCredentialFallback: String
    let normalizeManualHeader: (String) -> String?
    let normalizeDetectedHeader: (String) -> String?
}

enum OfficialProviderWebOverlayRuntime {
    static func resolveCookieHeader(
        official: OfficialProviderConfig,
        descriptorID: String,
        keychain: KeychainService,
        browserCookieService: BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff? = nil,
        webRetryBackoffInterval: TimeInterval? = nil,
        forceRefresh: Bool,
        strategy: OfficialBrowserCookieImportStrategy
    ) async throws -> BrowserCookieHeader {
        let service = KeychainService.defaultServiceName
        let browserAccessIntent: BrowserCredentialAccessIntent = forceRefresh ? .interactiveImport : .background

        if let account = official.manualCookieAccount,
           let stored = keychain.readToken(service: service, account: account),
           let header = strategy.normalizeManualHeader(stored),
           !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return BrowserCookieHeader(header: header, source: "Manual")
        }

        guard official.webMode != .manual else {
            throw ProviderError.missingCredential(official.manualCookieAccount ?? strategy.manualCredentialFallback)
        }

        guard official.webMode == .autoImport else {
            throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
        }

        let backoffKey = backoffKey(
            providerKey: strategy.providerKey,
            descriptorID: descriptorID,
            manualCookieAccount: official.manualCookieAccount
        )
        if let webReadBackoff {
            guard await webReadBackoff.shouldAttempt(for: backoffKey, forceRefresh: forceRefresh) else {
                throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
            }
        }

        if let namedCookie = strategy.namedCookie,
           let detected = browserCookieService.detectNamedCookie(
               name: namedCookie,
               hostContains: strategy.hostContains,
               order: nil,
               accessIntent: browserAccessIntent
           ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(normalized, service: service, account: account)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            return BrowserCookieHeader(header: normalized, source: detected.source)
        }

        if let detected = browserCookieService.detectCookieHeader(
            hostContains: strategy.hostContains,
            order: nil,
            accessIntent: browserAccessIntent
        ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(normalized, service: service, account: account)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            return BrowserCookieHeader(header: normalized, source: detected.source)
        }

        if let webReadBackoff, let webRetryBackoffInterval {
            await webReadBackoff.markFailure(for: backoffKey, interval: webRetryBackoffInterval)
        }
        throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
    }

    static func hasStoredManualCookie(
        official: OfficialProviderConfig,
        keychain: KeychainService,
        normalizeManualHeader: (String) -> String?
    ) -> Bool {
        guard let account = official.manualCookieAccount,
              let stored = keychain.readToken(service: KeychainService.defaultServiceName, account: account),
              let header = normalizeManualHeader(stored),
              !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    static func merge(primary: UsageSnapshot, overlay: UsageSnapshot, sourceLabel: String) -> UsageSnapshot {
        var merged = primary
        merged.sourceLabel = sourceLabel
        merged.accountLabel = primary.accountLabel ?? overlay.accountLabel

        var existing = Set(merged.quotaWindows.map(\.id))
        for window in overlay.quotaWindows where !existing.contains(window.id) {
            merged.quotaWindows.append(window)
            existing.insert(window.id)
        }

        for (key, value) in overlay.extras where merged.extras[key] == nil {
            merged.extras[key] = value
        }
        if merged.note.isEmpty {
            merged.note = overlay.note
        }
        return merged
    }

    private static func backoffKey(
        providerKey: String,
        descriptorID: String,
        manualCookieAccount: String?
    ) -> String {
        let account = manualCookieAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (account?.isEmpty == false ? account! : descriptorID)
        return "\(providerKey):\(normalized)"
    }
}
