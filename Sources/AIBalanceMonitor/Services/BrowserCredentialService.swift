import Foundation

struct BrowserDetectedCredential: Equatable {
    let value: String
    let source: String
}

final class BrowserCredentialService {
    private let bearerService: KimiBrowserCookieService
    private let cookieService: BrowserCookieService
    private let bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])?
    private let cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)?
    private let namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)?

    init(
        bearerService: KimiBrowserCookieService = KimiBrowserCookieService(),
        cookieService: BrowserCookieService = BrowserCookieService(),
        bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])? = nil,
        cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)? = nil,
        namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)? = nil
    ) {
        self.bearerService = bearerService
        self.cookieService = cookieService
        self.bearerCandidatesOverride = bearerCandidatesOverride
        self.cookieHeaderOverride = cookieHeaderOverride
        self.namedCookieOverride = namedCookieOverride
    }

    func detectBearerTokenCandidates(host: String) -> [BrowserDetectedCredential] {
        if let bearerCandidatesOverride {
            return bearerCandidatesOverride(host)
        }
        return bearerService.detectBearerTokenCandidates(host: host).map {
            BrowserDetectedCredential(value: $0.token, source: $0.source)
        }
    }

    func detectCookieHeader(host: String) -> BrowserDetectedCredential? {
        if let cookieHeaderOverride {
            for candidateHost in hostCandidates(for: host) {
                if let detected = cookieHeaderOverride(candidateHost) {
                    return detected
                }
            }
            return nil
        }
        for candidateHost in hostCandidates(for: host) {
            if let detected = cookieService.detectCookieHeader(hostContains: candidateHost) {
                return BrowserDetectedCredential(value: detected.header, source: detected.source)
            }
        }
        for candidateHost in hostCandidates(for: host) {
            if let detected = bearerService.detectCookieHeader(host: candidateHost) {
                return BrowserDetectedCredential(value: detected.token, source: detected.source)
            }
        }
        return nil
    }

    func detectNamedCookie(name: String, host: String) -> BrowserDetectedCredential? {
        if let namedCookieOverride {
            for candidateHost in hostCandidates(for: host) {
                if let detected = namedCookieOverride(name, candidateHost) {
                    return detected
                }
            }
            return nil
        }
        for candidateHost in hostCandidates(for: host) {
            if let detected = cookieService.detectNamedCookie(name: name, hostContains: candidateHost) {
                return BrowserDetectedCredential(value: detected.header, source: detected.source)
            }
        }
        return nil
    }

    private func hostCandidates(for host: String) -> [String] {
        let normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
}
