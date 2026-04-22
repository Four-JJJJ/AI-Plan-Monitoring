import Foundation

final class OllamaCloudProvider: UsageProvider, @unchecked Sendable {
    private static let webReadBackoff = WebOverlayRetryBackoff()

    private let session: URLSession
    private let keychain: KeychainService
    private let browserCookieService: BrowserCookieDetecting
    private let webReadBackoff: WebOverlayRetryBackoff
    private let webRetryBackoffInterval: TimeInterval = 15 * 60

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: KeychainService,
        browserCookieService: BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff = OllamaCloudProvider.webReadBackoff
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.webReadBackoff = webReadBackoff
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .ollamaCloud)
        guard official.sourceMode == .auto || official.sourceMode == .web else {
            throw ProviderError.unavailable("Ollama Cloud 官方来源当前仅支持 Web 检测")
        }

        return try await loadFromWeb(forceRefresh: forceRefresh)
    }

    private func loadFromWeb(forceRefresh: Bool) async throws -> UsageSnapshot {
        let cookie = try await resolveCookieHeader(forceRefresh: forceRefresh)
        let html = try await requestSettingsHTML(cookieHeader: cookie.header)
        var snapshot = try Self.parseSnapshot(html: html, descriptor: descriptor)
        snapshot.extras["webCookieSource"] = cookie.source
        return snapshot
    }

    private func requestSettingsHTML(cookieHeader: String) async throws -> String {
        guard let url = settingsURL() else {
            throw ProviderError.invalidResponse("invalid Ollama settings URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Ollama non-http response")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }

        if let finalPath = http.url?.path.lowercased(), finalPath.contains("/signin") {
            throw ProviderError.unauthorized
        }

        if (300...399).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location")?.lowercased(),
           location.contains("/signin") {
            throw ProviderError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Ollama http \(http.statusCode)")
        }

        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw ProviderError.invalidResponse("empty Ollama settings response")
        }

        if html.lowercased().contains("/signin") && html.lowercased().contains("<form") {
            throw ProviderError.unauthorized
        }

        return html
    }

    private func settingsURL() -> URL? {
        var base = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = "https://ollama.com"
        }
        if !base.contains("://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: base + "/settings")
    }

    private func resolveCookieHeader(forceRefresh: Bool) async throws -> BrowserCookieHeader {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .ollamaCloud)
        let service = KeychainService.defaultServiceName

        if let account = official.manualCookieAccount,
           let stored = keychain.readToken(service: service, account: account),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return BrowserCookieHeader(header: Self.normalizeManualCookieHeader(stored), source: "Manual")
        }

        guard official.webMode != .manual else {
            throw ProviderError.missingCredential(official.manualCookieAccount ?? "official/ollama/session-cookie")
        }

        guard official.webMode == .autoImport else {
            throw ProviderError.missingCredential("ollama.com __Secure-session")
        }

        let backoffKey = webReadBackoffKey(for: official)
        guard await webReadBackoff.shouldAttempt(for: backoffKey, forceRefresh: forceRefresh) else {
            throw ProviderError.missingCredential("ollama.com __Secure-session")
        }

        if let detected = browserCookieService.detectNamedCookie(name: "__Secure-session", hostContains: "ollama.com", order: nil) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(detected.header, service: service, account: account)
            }
            await webReadBackoff.clearFailure(for: backoffKey)
            return detected
        }

        if let detected = browserCookieService.detectCookieHeader(hostContains: "ollama.com", order: nil),
           Self.extractCookieValue(name: "__Secure-session", from: detected.header) != nil {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(detected.header, service: service, account: account)
            }
            await webReadBackoff.clearFailure(for: backoffKey)
            return detected
        }

        await webReadBackoff.markFailure(for: backoffKey, interval: webRetryBackoffInterval)
        throw ProviderError.missingCredential("ollama.com __Secure-session")
    }

    private func webReadBackoffKey(for official: OfficialProviderConfig) -> String {
        let account = official.manualCookieAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (account?.isEmpty == false ? account! : descriptor.id)
        return "ollama:\(normalized)"
    }

    internal static func parseSnapshot(html: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let sessionWindow = parseUsageWindow(
            html: html,
            label: "session usage",
            title: "Session",
            id: "\(descriptor.id)-session",
            kind: .session
        ) else {
            throw ProviderError.invalidResponse("missing Ollama session usage")
        }

        guard let weeklyWindow = parseUsageWindow(
            html: html,
            label: "weekly usage",
            title: "Weekly",
            id: "\(descriptor.id)-weekly",
            kind: .weekly
        ) else {
            throw ProviderError.invalidResponse("missing Ollama weekly usage")
        }

        let windows = [sessionWindow, weeklyWindow]
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let planType = parsePlanType(html: html)

        var noteParts = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
        if let planType, !planType.isEmpty {
            noteParts.insert("Plan \(planType)", at: 0)
        }

        var extras: [String: String] = [:]
        if let planType, !planType.isEmpty {
            extras["planType"] = planType
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: noteParts.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "Web",
            accountLabel: nil,
            extras: extras,
            rawMeta: [:]
        )
    }

    private static func parseUsageWindow(
        html: String,
        label: String,
        title: String,
        id: String,
        kind: UsageQuotaKind
    ) -> UsageQuotaWindow? {
        let lower = html.lowercased()
        guard let labelRange = lower.range(of: label.lowercased()) else {
            return nil
        }

        let startOffset = lower.distance(from: lower.startIndex, to: labelRange.lowerBound)
        let endOffset = min(lower.count, startOffset + 1800)
        let startIndex = html.index(html.startIndex, offsetBy: startOffset)
        let endIndex = html.index(html.startIndex, offsetBy: endOffset)
        let snippet = String(html[startIndex..<endIndex])

        guard let usedPercent = firstDoubleCapture(
            in: snippet,
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%\s*used"#
        ) else {
            return nil
        }

        let remainingPercent = max(0, min(100, 100 - usedPercent))
        let clampedUsedPercent = max(0, min(100, usedPercent))
        let resetAt = firstCapture(in: snippet, pattern: #"data-time\s*=\s*\"([^\"]+)\""#)
            .flatMap(parseDate)

        return UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: clampedUsedPercent,
            resetAt: resetAt,
            kind: kind
        )
    }

    private static func parsePlanType(html: String) -> String? {
        let pattern = #"(?is)<h2[^>]*>.*?<span[^>]*>\s*Cloud\s*Usage\s*</span>.*?<span[^>]*>\s*([^<]+?)\s*</span>.*?</h2>"#
        guard let value = firstCapture(in: html, pattern: pattern) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func firstDoubleCapture(in text: String, pattern: String) -> Double? {
        guard let raw = firstCapture(in: text, pattern: pattern) else {
            return nil
        }
        return Double(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = OfficialValueParser.isoDate(trimmed) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }

    private static func normalizeManualCookieHeader(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.isEmpty {
            return ""
        }
        if value.contains("=") {
            return value
        }
        return "__Secure-session=\(value)"
    }

    private static func extractCookieValue(name: String, from header: String) -> String? {
        let segments = header.split(separator: ";")
        for segment in segments {
            let pair = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == name {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
