import Foundation

struct BrowserDetectedCredential: Equatable {
    let value: String
    let source: String
}

final class BrowserCredentialService {
    private struct ExpiringCacheEntry<T> {
        let value: T
        let expiresAt: Date
    }

    private let bearerService: KimiBrowserCookieService
    private let cookieService: BrowserCookieService
    private let bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])?
    private let cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)?
    private let namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)?
    private let cacheTTL: TimeInterval
    private let lock = NSLock()
    private var bearerCache: [String: ExpiringCacheEntry<[BrowserDetectedCredential]>] = [:]
    private var cookieHeaderCache: [String: ExpiringCacheEntry<BrowserDetectedCredential?>] = [:]
    private var namedCookieCache: [String: ExpiringCacheEntry<BrowserDetectedCredential?>] = [:]

    init(
        bearerService: KimiBrowserCookieService = KimiBrowserCookieService(),
        cookieService: BrowserCookieService = BrowserCookieService(),
        bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])? = nil,
        cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)? = nil,
        namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)? = nil,
        cacheTTL: TimeInterval = 5
    ) {
        self.bearerService = bearerService
        self.cookieService = cookieService
        self.bearerCandidatesOverride = bearerCandidatesOverride
        self.cookieHeaderOverride = cookieHeaderOverride
        self.namedCookieOverride = namedCookieOverride
        self.cacheTTL = max(0, cacheTTL)
    }

    func detectBearerTokenCandidates(host: String) -> [BrowserDetectedCredential] {
        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return [] }

        let now = Date()
        if let cached = cachedBearerCandidates(for: normalizedHost, now: now) {
            return cached
        }

        let resolved: [BrowserDetectedCredential]
        if let bearerCandidatesOverride {
            resolved = bearerCandidatesOverride(normalizedHost)
        } else {
            resolved = bearerService.detectBearerTokenCandidates(host: normalizedHost).map {
                BrowserDetectedCredential(value: $0.token, source: $0.source)
            }
        }
        cacheBearerCandidates(resolved, for: normalizedHost, now: now)
        return resolved
    }

    func detectCookieHeader(host: String) -> BrowserDetectedCredential? {
        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return nil }

        let now = Date()
        if let cached = cachedCookieHeader(for: normalizedHost, now: now) {
            return cached
        }

        let resolved: BrowserDetectedCredential?
        if let cookieHeaderOverride {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = cookieHeaderOverride(candidateHost) {
                    candidate = detected
                    break
                }
            }
            resolved = candidate
        } else {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = cookieService.detectCookieHeader(hostContains: candidateHost) {
                    candidate = BrowserDetectedCredential(value: detected.header, source: detected.source)
                    break
                }
            }
            if candidate == nil {
                for candidateHost in hostCandidates(for: normalizedHost) {
                    if let detected = bearerService.detectCookieHeader(host: candidateHost) {
                        candidate = BrowserDetectedCredential(value: detected.token, source: detected.source)
                        break
                    }
                }
            }
            resolved = candidate
        }

        cacheCookieHeader(resolved, for: normalizedHost, now: now)
        return resolved
    }

    func detectNamedCookie(name: String, host: String) -> BrowserDetectedCredential? {
        let normalizedHost = normalizedHost(host)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedName.isEmpty else { return nil }

        let cacheKey = "\(normalizedName.lowercased())|\(normalizedHost)"
        let now = Date()
        if let cached = cachedNamedCookie(for: cacheKey, now: now) {
            return cached
        }

        let resolved: BrowserDetectedCredential?
        if let namedCookieOverride {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = namedCookieOverride(normalizedName, candidateHost) {
                    candidate = detected
                    break
                }
            }
            resolved = candidate
        } else {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = cookieService.detectNamedCookie(name: normalizedName, hostContains: candidateHost) {
                    candidate = BrowserDetectedCredential(value: detected.header, source: detected.source)
                    break
                }
            }
            resolved = candidate
        }

        cacheNamedCookie(resolved, for: cacheKey, now: now)
        return resolved
    }

    private func hostCandidates(for host: String) -> [String] {
        let normalized = normalizedHost(host)
        guard !normalized.isEmpty else { return [] }

        var candidates: [String] = [normalized]
        let labels = normalized.split(separator: ".").map(String.init)
        if labels.count > 2 {
            for index in 1..<(labels.count - 1) {
                let suffix = labels[index...].joined(separator: ".")
                if suffix.isEmpty { continue }
                if candidates.contains(suffix) { continue }
                candidates.append(suffix)
            }
        }
        return candidates
    }

    private func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func cachedBearerCandidates(for host: String, now: Date) -> [BrowserDetectedCredential]? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLocked(now: now)
        return bearerCache[host]?.value
    }

    private func cacheBearerCandidates(_ candidates: [BrowserDetectedCredential], for host: String, now: Date) {
        lock.lock()
        bearerCache[host] = ExpiringCacheEntry(
            value: candidates,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLocked(now: now)
        lock.unlock()
    }

    private func cachedCookieHeader(for host: String, now: Date) -> BrowserDetectedCredential?? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLocked(now: now)
        guard let entry = cookieHeaderCache[host] else {
            return nil
        }
        return entry.value
    }

    private func cacheCookieHeader(_ credential: BrowserDetectedCredential?, for host: String, now: Date) {
        lock.lock()
        cookieHeaderCache[host] = ExpiringCacheEntry(
            value: credential,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLocked(now: now)
        lock.unlock()
    }

    private func cachedNamedCookie(for key: String, now: Date) -> BrowserDetectedCredential?? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLocked(now: now)
        guard let entry = namedCookieCache[key] else {
            return nil
        }
        return entry.value
    }

    private func cacheNamedCookie(_ credential: BrowserDetectedCredential?, for key: String, now: Date) {
        lock.lock()
        namedCookieCache[key] = ExpiringCacheEntry(
            value: credential,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLocked(now: now)
        lock.unlock()
    }

    private func purgeExpiredCacheLocked(now: Date) {
        bearerCache = bearerCache.filter { _, entry in
            entry.expiresAt > now
        }
        cookieHeaderCache = cookieHeaderCache.filter { _, entry in
            entry.expiresAt > now
        }
        namedCookieCache = namedCookieCache.filter { _, entry in
            entry.expiresAt > now
        }
    }
}
