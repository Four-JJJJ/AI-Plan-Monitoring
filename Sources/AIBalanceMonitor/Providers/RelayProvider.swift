import Foundation

final class RelayProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let keychain: KeychainService
    private let browserCredentialService: BrowserCredentialService
    private let registry: RelayAdapterRegistry

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: KeychainService,
        browserCredentialService: BrowserCredentialService = BrowserCredentialService(),
        registry: RelayAdapterRegistry = .shared
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCredentialService = browserCredentialService
        self.registry = registry
    }

    func fetch() async throws -> UsageSnapshot {
        let normalized = descriptor.normalized()
        guard let relayConfig = normalized.relayConfig else {
            throw ProviderError.unavailable("Missing relay config for \(descriptor.name)")
        }
        guard let baseURL = relayRootURL(from: relayConfig.baseURL) else {
            throw ProviderError.invalidResponse("invalid relay base URL")
        }
        let manifest = registry.manifest(for: relayConfig.baseURL, preferredID: relayConfig.adapterID)

        var firstError: Error?
        var tokenChannel: TokenChannelResult?
        var balanceChannel: AccountChannelResult?

        if relayConfig.tokenChannelEnabled, manifest.tokenRequest != nil {
            do {
                tokenChannel = try await fetchTokenUsageChannel(
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    tokenRequest: manifest.tokenRequest!
                )
            } catch {
                firstError = firstError ?? error
            }
        }

        if relayConfig.balanceChannelEnabled {
            do {
                balanceChannel = try await fetchBalanceChannel(
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    manifest: manifest
                )
            } catch {
                firstError = firstError ?? error
            }
        }

        guard tokenChannel != nil || balanceChannel != nil else {
            throw firstError ?? ProviderError.unavailable("No enabled data channel for \(descriptor.name)")
        }

        let remaining = balanceChannel?.remaining ?? tokenChannel?.remaining
        let used = balanceChannel?.used ?? tokenChannel?.used
        let limit = balanceChannel?.limit ?? tokenChannel?.limit
        let unit = balanceChannel?.unit ?? tokenChannel?.unit ?? "quota"

        let status: SnapshotStatus
        if let remaining {
            status = remaining <= descriptor.threshold.lowRemaining ? .warning : .ok
        } else {
            status = .ok
        }

        var noteParts: [String] = []
        var rawMeta: [String: String] = ["relay.adapterID": manifest.id]

        if let balanceChannel {
            noteParts.append(balanceChannel.note)
            for (key, value) in balanceChannel.rawMeta {
                rawMeta["account.\(key)"] = value
            }
        }

        if let tokenChannel {
            noteParts.append(tokenChannel.note)
            for (key, value) in tokenChannel.rawMeta {
                rawMeta["token.\(key)"] = value
            }
        }

        return UsageSnapshot(
            source: normalized.id,
            status: status,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            updatedAt: Date(),
            note: noteParts.isEmpty ? "No detail" : noteParts.joined(separator: " | "),
            quotaWindows: [],
            sourceLabel: "Third-Party",
            accountLabel: balanceChannel?.accountLabel,
            extras: [
                "relayAdapter": manifest.displayName
            ],
            rawMeta: rawMeta
        )
    }

    private func fetchTokenUsageChannel(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        tokenRequest: RelayTokenRequestManifest
    ) async throws -> TokenChannelResult {
        let host = baseURL.host?.lowercased() ?? ""
        let primaryCandidates = resolveTokenCandidates(host: host, includeBrowserFallback: false)
        let fallbackCandidates = resolveTokenCandidates(host: host, includeBrowserFallback: true)
        let candidates = primaryCandidates + fallbackCandidates.filter { fallback in
            !primaryCandidates.contains(where: { $0.token == fallback.token })
        }

        guard !candidates.isEmpty else {
            throw ProviderError.missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
        }

        var lastError: ProviderError = .missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
        for candidate in candidates {
            do {
                let tokenUsage = try await request(
                    url: relayURL(baseURL: baseURL, rawPath: tokenRequest.usagePath),
                    bearerToken: candidate.token,
                    type: OpenTokenUsageEnvelope.self
                )

                let subscription = try? await request(
                    url: relayURL(baseURL: baseURL, rawPath: tokenRequest.subscriptionPath ?? ""),
                    bearerToken: candidate.token,
                    type: OpenBillingSubscription.self
                )
                let usage = try? await request(
                    url: relayURL(baseURL: baseURL, rawPath: tokenRequest.billingUsagePath ?? ""),
                    bearerToken: candidate.token,
                    type: OpenBillingUsage.self
                )

                _ = persistTokenCandidate(candidate.token, auth: descriptor.auth)

                let unlimited = tokenUsage.data.unlimitedQuota
                let remaining = unlimited ? nil : tokenUsage.data.totalAvailable
                let used = tokenUsage.data.totalUsed
                let softLimit = subscription?.softLimitUSD ?? tokenUsage.data.totalGranted
                let hardLimit = subscription?.hardLimitUSD ?? softLimit
                let limit = unlimited ? nil : max(tokenUsage.data.totalGranted, softLimit)

                let note: String
                if unlimited {
                    if let usage {
                        note = "Token unlimited | billing usage \(String(format: "%.2f", usage.totalUsage))"
                    } else {
                        note = "Token unlimited"
                    }
                } else {
                    if let usage {
                        note = "Token remaining \(String(format: "%.2f", remaining ?? 0)) | billing usage \(String(format: "%.2f", usage.totalUsage))"
                    } else {
                        note = "Token remaining \(String(format: "%.2f", remaining ?? 0))"
                    }
                }

                var meta: [String: String] = [
                    "tokenName": tokenUsage.data.name,
                    "unlimitedQuota": String(unlimited),
                    "softLimitUsd": String(softLimit),
                    "hardLimitUsd": String(hardLimit),
                    "authSource": candidate.source
                ]
                if let usage {
                    meta["billingTotalUsage"] = String(usage.totalUsage)
                }

                return TokenChannelResult(
                    remaining: remaining,
                    used: used,
                    limit: limit,
                    unit: "quota",
                    note: note,
                    rawMeta: meta
                )
            } catch let error as ProviderError {
                switch error {
                case .unauthorized, .unauthorizedDetail, .invalidResponse:
                    lastError = error
                    continue
                default:
                    throw error
                }
            }
        }

        throw lastError
    }

    private func attemptBalanceFetch(
        candidates: [RelayCredentialCandidate],
        requests: [ResolvedRelayRequest],
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest
    ) async throws -> AccountChannelResult {
        guard !candidates.isEmpty else {
            throw ProviderError.missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")
        }

        var lastError: ProviderError = .missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")
    candidateLoop: for candidate in candidates {
            if candidate.source == "savedBearerExpired" {
                throw ProviderError.unauthorizedDetail("saved bearer token expired")
            }
            for request in requests {
                do {
                    let root = try await requestJSON(
                        url: relayURL(baseURL: baseURL, rawPath: request.path),
                        headers: candidate.headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                        method: request.method,
                        bodyJSON: request.bodyJSON
                    )

                    let extracted = try await extractAccountValues(
                        root: root,
                        baseURL: baseURL,
                        request: request,
                        manifest: manifest,
                        headers: candidate.headers,
                        candidate: candidate
                    )

                    if let persisted = candidate.persistedCredential {
                        _ = persistTokenCandidate(persisted, auth: relayConfig.balanceAuth)
                    }

                    return extracted
                } catch let error as ProviderError {
                    switch error {
                    case .invalidResponse:
                        lastError = error
                        continue
                    case .unauthorized, .unauthorizedDetail:
                        lastError = error
                        continue candidateLoop
                    default:
                        throw error
                    }
                }
            }
        }
        throw lastError
    }

    private func extractAccountValues(
        root: Any,
        baseURL: URL,
        request: ResolvedRelayRequest,
        manifest: RelayAdapterManifest,
        headers: [String: String],
        candidate: RelayCredentialCandidate
    ) async throws -> AccountChannelResult {
        if let successExpression = request.successExpression,
           let success = boolValue(for: successExpression, in: root),
           !success {
            throw ProviderError.invalidResponse("probe failed at \(successExpression)")
        }

        if manifest.id == "moonshot",
           let moonshotFallback = try? await extractMoonshotAccountValues(
            initialRoot: root,
            baseURL: baseURL,
            request: request,
            headers: headers,
            candidate: candidate
           ) {
            return moonshotFallback
        }

        guard var remaining = numericValue(for: request.remainingExpression, in: root) else {
            throw ProviderError.invalidResponse("missing remaining path \(request.remainingExpression)")
        }
        var used = request.usedExpression.flatMap { numericValue(for: $0, in: root) }
        var limit = request.limitExpression.flatMap { numericValue(for: $0, in: root) }
        if limit == nil, let used {
            limit = max(0, remaining + used)
        }

        var unit = request.unitExpression.flatMap { stringValue(for: $0, in: root) } ?? "quota"
        let accountLabel = request.accountLabelExpression.flatMap { stringValue(for: $0, in: root) }
        var extraMeta: [String: String] = [
            "endpointPath": normalizedPath(request.path),
            "requestMethod": request.method,
            "remainingPath": request.remainingExpression,
            "usedPath": request.usedExpression ?? "",
            "limitPath": request.limitExpression ?? "",
            "authSource": candidate.source
        ]
        if let userID = request.userID {
            extraMeta["userID"] = userID
        }

        if manifest.postprocessID == .quotaDisplayStatus {
            let converted = try? await convertAilinyuQuotaToDisplayAmount(
                baseURL: baseURL,
                headers: headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                quota: remaining
            )
            if let converted {
                remaining = converted.remaining
                used = used.map { $0 / converted.quotaPerUnit * converted.rate }
                limit = limit.map { $0 / converted.quotaPerUnit * converted.rate }
                unit = converted.unit
                extraMeta["displayType"] = converted.displayType
                extraMeta["quotaPerUnit"] = String(converted.quotaPerUnit)
                extraMeta["displayRate"] = String(converted.rate)
            }
        }

        let note = "Account remaining \(String(format: "%.2f", remaining))"
        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            accountLabel: accountLabel,
            note: note,
            rawMeta: extraMeta
        )
    }

    private func extractMoonshotAccountValues(
        initialRoot: Any,
        baseURL: URL,
        request: ResolvedRelayRequest,
        headers: [String: String],
        candidate: RelayCredentialCandidate
    ) async throws -> AccountChannelResult? {
        if let remaining = numericValue(for: request.remainingExpression, in: initialRoot) {
            var used = request.usedExpression.flatMap { numericValue(for: $0, in: initialRoot) }
            var limit = request.limitExpression.flatMap { numericValue(for: $0, in: initialRoot) }
            if limit == nil, let used {
                limit = max(0, remaining + used)
            }
            var normalizedRemaining = remaining
            var normalizedUsed = used
            var normalizedLimit = limit
            var extraMeta: [String: String] = [
                "endpointPath": normalizedPath(request.path),
                "requestMethod": request.method,
                "remainingPath": request.remainingExpression,
                "usedPath": request.usedExpression ?? "",
                "limitPath": request.limitExpression ?? "",
                "authSource": candidate.source
            ]
            if moonshotUsesScaledCurrencyShape(root: initialRoot) {
                normalizedRemaining = remaining / 100_000
                normalizedUsed = used.map { $0 / 100_000 }
                normalizedLimit = limit.map { $0 / 100_000 }
                extraMeta["valueScale"] = "100000"
                extraMeta["rawRemaining"] = String(remaining)
                if let used {
                    extraMeta["rawUsed"] = String(used)
                }
                if let limit {
                    extraMeta["rawLimit"] = String(limit)
                }
            }
            let unit = request.unitExpression.flatMap { stringValue(for: $0, in: initialRoot) } ?? "quota"
            let accountLabel = request.accountLabelExpression.flatMap { stringValue(for: $0, in: initialRoot) }
            return AccountChannelResult(
                remaining: normalizedRemaining,
                used: normalizedUsed,
                limit: normalizedLimit,
                unit: unit,
                accountLabel: accountLabel,
                note: "Account remaining \(String(format: "%.2f", normalizedRemaining))",
                rawMeta: extraMeta
            )
        }

        let trimmedPath = request.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.contains("endpoint=userInfo") else {
            return nil
        }

        let oidExpressions = [
            "data.organizations.0.organization.id",
            "data.organizations.0.id",
            "data.currentOrganizationId",
            "data.currentOrganization.id",
            "data.organizationId",
            "data.organization.id",
            "data.defaultOrganizationId",
            "data.defaultOrganization.id",
            "data.orgId",
            "data.org_id",
            "data.oid",
            "organizations.0.organization.id",
            "organizations.0.id",
            "currentOrganizationId",
            "organizationId",
            "orgId",
            "org_id",
            "oid"
        ]

        let organizationIDs = oidExpressions.compactMap { expression -> String? in
            guard let raw = value(at: expression, in: initialRoot) else { return nil }
            if let string = raw as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let number = raw as? NSNumber {
                return number.stringValue
            }
            return nil
        }
        for oid in organizationIDs where !oid.isEmpty {
            let path = "/api?endpoint=organizationAccountInfo&oid=\(oid)"
            let root = try await requestJSON(
                url: relayURL(baseURL: baseURL, rawPath: path),
                headers: headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                method: "GET",
                bodyJSON: nil
            )

            if let remaining = numericValue(for: "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)", in: root) {
                var used = numericValue(for: "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)", in: root)
                var limit = numericValue(for: "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)", in: root)
                if limit == nil, let used {
                    limit = max(0, remaining + used)
                }
                var normalizedRemaining = remaining
                var normalizedUsed = used
                var normalizedLimit = limit
                var extraMeta: [String: String] = [
                    "endpointPath": "/api?endpoint=organizationAccountInfo&oid=\(oid)",
                    "requestMethod": "GET",
                    "remainingPath": "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)",
                    "usedPath": "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)",
                    "limitPath": "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)",
                    "authSource": candidate.source,
                    "organizationID": oid
                ]
                if moonshotUsesScaledCurrencyShape(root: root) {
                    normalizedRemaining = remaining / 100_000
                    normalizedUsed = used.map { $0 / 100_000 }
                    normalizedLimit = limit.map { $0 / 100_000 }
                    extraMeta["valueScale"] = "100000"
                    extraMeta["rawRemaining"] = String(remaining)
                    if let used {
                        extraMeta["rawUsed"] = String(used)
                    }
                    if let limit {
                        extraMeta["rawLimit"] = String(limit)
                    }
                }
                let unit = stringValue(for: "\"CNY\"", in: root) ?? "CNY"
                let accountLabel = stringValue(for: "coalesce(data.user.nickname,data.user.nickName,data.user.name,data.nickName,data.nickname,data.userName,nickName,nickname,userName,name)", in: root)
                return AccountChannelResult(
                    remaining: normalizedRemaining,
                    used: normalizedUsed,
                    limit: normalizedLimit,
                    unit: unit,
                    accountLabel: accountLabel,
                    note: "Account remaining \(String(format: "%.2f", normalizedRemaining))",
                    rawMeta: extraMeta
                )
            }
        }

        return nil
    }

    private func moonshotUsesScaledCurrencyShape(root: Any) -> Bool {
        value(at: "data.cur", in: root) != nil ||
        value(at: "data.acc", in: root) != nil ||
        value(at: "data.use", in: root) != nil ||
        value(at: "cur", in: root) != nil ||
        value(at: "acc", in: root) != nil ||
        value(at: "use", in: root) != nil
    }

    private func resolveTokenCandidates(host: String, includeBrowserFallback: Bool) -> [RelayRawTokenCandidate] {
        var output: [RelayRawTokenCandidate] = []

        func append(token: String?, source: String) {
            guard let token else { return }
            let trimmed = normalizeBearerToken(token)
            guard !trimmed.isEmpty else { return }
            guard !isExpiredJWT(trimmed) else { return }
            if output.contains(where: { $0.token == trimmed }) {
                return
            }
            output.append(RelayRawTokenCandidate(token: trimmed, source: source))
        }

        if let service = descriptor.auth.keychainService,
           let account = descriptor.auth.keychainAccount {
            append(token: keychain.readToken(service: service, account: account), source: "saved")
        }

        if includeBrowserFallback || output.isEmpty {
            for candidate in browserCredentialService.detectBearerTokenCandidates(host: host) {
                append(token: candidate.value, source: candidate.source)
            }
        }

        return output
    }

    private func resolveBalanceCandidates(
        baseURL: URL,
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig,
        request: ResolvedRelayRequest,
        strategies: [RelayAuthStrategy],
        includeSavedCredentials: Bool,
        includeBrowserCredentials: Bool,
        includeExpiredSentinel: Bool
    ) -> [RelayCredentialCandidate] {
        let host = baseURL.host?.lowercased() ?? ""
        var candidates: [RelayCredentialCandidate] = []
        let savedRaw = readSavedCredential(auth: relayConfig.balanceAuth)
        let savedBearer = savedRaw.flatMap { raw in
            looksLikeCookieHeader(raw) ? nil : normalizeBearerToken(raw)
        }
        let savedBearerExpired = savedBearer.map(isExpiredJWT) ?? false

        func append(_ candidate: RelayCredentialCandidate?) {
            guard let candidate else { return }
            if candidates.contains(where: { $0.headers == candidate.headers }) {
                return
            }
            candidates.append(candidate)
        }

        for strategy in strategies {
            switch strategy.kind {
            case .savedBearer:
                guard includeSavedCredentials else { continue }
                guard savedBearerExpired == false else { continue }
                append(savedBearer.map {
                    buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme ?? "Bearer",
                        rawValue: $0,
                        source: "savedBearer",
                        persistedCredential: $0
                    )
                })
            case .browserBearer:
                guard includeBrowserCredentials else { continue }
                for detected in browserCredentialService.detectBearerTokenCandidates(host: host) {
                    let normalized = normalizeBearerToken(detected.value)
                    guard !normalized.isEmpty, !isExpiredJWT(normalized) else { continue }
                    append(buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme ?? "Bearer",
                        rawValue: normalized,
                        source: "browserBearer:\(detected.source)",
                        persistedCredential: normalized
                    ))
                }
            case .savedCookieHeader:
                guard includeSavedCredentials else { continue }
                if let savedRaw,
                   looksLikeCookieHeader(savedRaw) {
                    if manifest.id == "moonshot",
                       looksLikeMoonshotNonAuthCookieHeader(savedRaw) {
                        continue
                    }
                    append(
                        RelayCredentialCandidate(
                            headers: buildHeaders(
                                request: request,
                                authHeader: "Cookie",
                                authValue: savedRaw
                            ),
                            source: "savedCookieHeader",
                            persistedCredential: savedRaw
                        )
                    )
                }
            case .browserCookieHeader:
                guard includeBrowserCredentials else { continue }
                if let detected = browserCredentialService.detectCookieHeader(host: host) {
                    append(RelayCredentialCandidate(
                        headers: buildHeaders(
                            request: request,
                            authHeader: "Cookie",
                            authValue: detected.value
                        ),
                        source: "browserCookieHeader:\(detected.source)",
                        persistedCredential: detected.value
                    ))
                }
            case .namedCookie:
                guard includeBrowserCredentials else { continue }
                let name = strategy.cookieName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { continue }
                if let detected = browserCredentialService.detectNamedCookie(name: name, host: host) {
                    append(RelayCredentialCandidate(
                        headers: buildHeaders(
                            request: request,
                            authHeader: "Cookie",
                            authValue: detected.value
                        ),
                        source: "namedCookie:\(detected.source)",
                        persistedCredential: detected.value
                    ))
                }
            case .customHeader:
                guard includeSavedCredentials else { continue }
                guard savedBearerExpired == false else { continue }
                append(savedBearer.map {
                    buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme,
                        rawValue: $0,
                        source: "customHeader",
                        persistedCredential: $0
                    )
                })
            }
        }

        if candidates.isEmpty, includeExpiredSentinel, savedBearerExpired {
            candidates.append(
                RelayCredentialCandidate(
                    headers: [:],
                    source: "savedBearerExpired",
                    persistedCredential: nil
                )
            )
        }

        if includeBrowserCredentials,
           manifest.id == "deepseek",
           let cookieDetected = browserCredentialService.detectCookieHeader(host: host) {
            let bearerCandidates = candidates.filter { candidate in
                candidate.headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame } &&
                candidate.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }) == false
            }
            for candidate in bearerCandidates {
                var headers = candidate.headers
                headers["Cookie"] = cookieDetected.value
                append(
                    RelayCredentialCandidate(
                        headers: headers,
                        source: "\(candidate.source)+cookie:\(cookieDetected.source)",
                        persistedCredential: candidate.persistedCredential
                    )
                )
            }
        }

        return candidates
    }

    private func fetchBalanceChannel(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest
    ) async throws -> AccountChannelResult {
        let requests = resolveBalanceRequests(manifest: manifest, relayConfig: relayConfig)
        let credentialMode = relayConfig.balanceCredentialMode ?? .manualPreferred
        let requestForCandidates = requests.first ?? resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig)

        let primaryCandidates: [RelayCredentialCandidate]
        let fallbackCandidates: [RelayCredentialCandidate]

        switch credentialMode {
        case .manualPreferred:
            primaryCandidates = resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: true,
                includeBrowserCredentials: false,
                includeExpiredSentinel: true
            )
            fallbackCandidates = resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: true,
                includeBrowserCredentials: true,
                includeExpiredSentinel: false
            ).filter { fallback in
                !primaryCandidates.contains(where: { $0.headers == fallback.headers || $0.source == fallback.source })
            }
        case .browserPreferred:
            primaryCandidates = resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: false,
                includeBrowserCredentials: true,
                includeExpiredSentinel: false
            )
            fallbackCandidates = resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: true,
                includeBrowserCredentials: false,
                includeExpiredSentinel: true
            ).filter { fallback in
                !primaryCandidates.contains(where: { $0.headers == fallback.headers || $0.source == fallback.source })
            }
        case .browserOnly:
            primaryCandidates = resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: false,
                includeBrowserCredentials: true,
                includeExpiredSentinel: false
            )
            fallbackCandidates = []
        }
        if !primaryCandidates.isEmpty,
           let snapshot = try? await attemptBalanceFetch(
            candidates: primaryCandidates,
            requests: requests,
            baseURL: baseURL,
            relayConfig: relayConfig,
            manifest: manifest
           ) {
            return snapshot
        }

        let candidates = (primaryCandidates + fallbackCandidates).filter { candidate in
            candidate.source != "savedBearerExpired" || (primaryCandidates + fallbackCandidates).count == 1
        }
        if candidates.isEmpty,
           manifest.id == "moonshot",
           let savedRaw = readSavedCredential(auth: relayConfig.balanceAuth),
           looksLikeMoonshotNonAuthCookieHeader(savedRaw) {
            throw ProviderError.unauthorizedDetail(
                "moonshot cookie appears incomplete; paste the full Cookie header from an authenticated platform request"
            )
        }
        return try await attemptBalanceFetch(
            candidates: candidates,
            requests: requests,
            baseURL: baseURL,
            relayConfig: relayConfig,
            manifest: manifest
        )
    }

    private func resolveBalanceRequest(
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig
    ) -> ResolvedRelayRequest {
        let override = relayConfig.manualOverrides
        let request = manifest.balanceRequest
        let extract = manifest.extract
        return ResolvedRelayRequest(
            method: nonEmptyOrDefault(override?.requestMethod, fallback: request.method),
            path: applyRelayRequiredPlaceholders(
                to: nonEmptyOrDefault(override?.endpointPath, fallback: request.path),
                userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID)
            ),
            bodyJSON: applyRelayPlaceholders(
                to: trimmedOrNil(override?.requestBodyJSON) ?? trimmedOrNil(request.bodyJSON),
                userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID)
            ),
            staticHeaders: (request.headers ?? [:]).merging(override?.staticHeaders ?? [:], uniquingKeysWith: { _, rhs in rhs }),
            userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID),
            userIDHeader: nonEmptyOrDefault(override?.userIDHeader, fallback: request.userIDHeader ?? "New-Api-User"),
            authHeader: nonEmptyOrDefault(override?.authHeader, fallback: request.authHeader ?? "Authorization"),
            authScheme: override?.authScheme ?? request.authScheme ?? "Bearer",
            successExpression: trimmedOrNil(override?.successExpression) ?? trimmedOrNil(extract.success),
            remainingExpression: nonEmptyOrDefault(override?.remainingExpression, fallback: extract.remaining),
            usedExpression: trimmedOrNil(override?.usedExpression) ?? trimmedOrNil(extract.used),
            limitExpression: trimmedOrNil(override?.limitExpression) ?? trimmedOrNil(extract.limit),
            unitExpression: trimmedOrNil(override?.unitExpression) ?? trimmedOrNil(extract.unit),
            accountLabelExpression: trimmedOrNil(override?.accountLabelExpression) ?? trimmedOrNil(extract.accountLabel)
        )
    }

    private func applyRelayPlaceholders(to value: String?, userID: String?) -> String? {
        guard var value else { return nil }
        if let userID {
            value = value.replacingOccurrences(of: "{{userID}}", with: userID)
        }
        return value
    }

    private func applyRelayRequiredPlaceholders(to value: String, userID: String?) -> String {
        applyRelayPlaceholders(to: value, userID: userID) ?? value
    }

    private func resolveBalanceRequests(
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig
    ) -> [ResolvedRelayRequest] {
        let primary = resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig)
        var requests: [ResolvedRelayRequest] = [primary]

        if manifest.id == "hongmacc" {
            let manualPath = relayConfig.manualOverrides?.endpointPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if manualPath.isEmpty {
                requests.append(contentsOf: hongmaccProbeRequests(from: primary))
            }
        }
        if manifest.id == "xiaomimimo" {
            let manualPath = relayConfig.manualOverrides?.endpointPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if manualPath.isEmpty {
                requests.append(contentsOf: xiaomimimoProbeRequests(from: primary))
            }
        }
        if manifest.id == "moonshot" {
            let manualPath = relayConfig.manualOverrides?.endpointPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if manualPath.isEmpty {
                requests.append(contentsOf: moonshotProbeRequests(from: primary))
            }
        }
        if manifest.id == "minimax" {
            let manualPath = relayConfig.manualOverrides?.endpointPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if manualPath.isEmpty {
                requests.append(contentsOf: minimaxProbeRequests(from: primary))
            }
        }

        var deduped: [ResolvedRelayRequest] = []
        var seen = Set<String>()
        for request in requests {
            let key = "\(normalizedPath(request.path))|\(request.remainingExpression)|\(request.usedExpression ?? "")|\(request.limitExpression ?? "")"
            if seen.insert(key).inserted {
                deduped.append(request)
            }
        }
        return deduped
    }

    private func hongmaccProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/user/key-balance",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(quota.remainingQuota,data.quota.remainingQuota,remainingQuota,data.remainingQuota)",
                usedExpression: "coalesce(quota.usedCost,data.quota.usedCost,usedCost,data.usedCost)",
                limitExpression: "coalesce(quota.totalCostLimit,data.quota.totalCostLimit,totalCostLimit,data.totalCostLimit)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            ),
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/user/api-keys",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(sum(data.*.remainingQuota),sum(data.items.*.remainingQuota),sum(apiKeys.*.remainingQuota),sum(keys.*.remainingQuota),data.remainingQuota,remainingQuota,data.balance,balance)",
                usedExpression: "coalesce(sum(data.*.usedQuota),sum(data.items.*.usedQuota),sum(apiKeys.*.usedQuota),sum(keys.*.usedQuota),data.usedQuota,usedQuota,data.used,used)",
                limitExpression: "coalesce(sum(data.*.totalQuota),sum(data.items.*.totalQuota),sum(apiKeys.*.totalQuota),sum(keys.*.totalQuota),data.totalQuota,totalQuota,data.limit,limit)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private func xiaomimimoProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/v1/balance",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(data.balance,data.availableBalance,data.wallet.balance,data.walletBalance,data.accountBalance,balance,availableBalance,walletBalance,accountBalance)",
                usedExpression: "coalesce(data.monthlyUsage,data.monthlySpend,data.used,data.consume,monthlyUsage,monthlySpend,used,consume)",
                limitExpression: "coalesce(data.totalLimit,data.limit,totalLimit,limit)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private func moonshotProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api?endpoint=organizationAccountInfo",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)",
                usedExpression: "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)",
                limitExpression: "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private func minimaxProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        guard let groupID = base.userID?.trimmingCharacters(in: .whitespacesAndNewlines), !groupID.isEmpty else {
            return []
        }
        let expressions = (
            remaining: "coalesce(data.available_amount,data.balance,data.availableBalance,data.accountBalance,data.currentBalance,data.current_balance,data.group.balance,data.groupBalance,data.wallet.balance,data.walletBalance,data.remainBalance,data.remainingBalance,available_amount,balance,availableBalance,accountBalance,currentBalance,current_balance,groupBalance,walletBalance,remainBalance,remainingBalance)",
            used: "coalesce(data.used,data.monthlyUsage,data.monthlySpend,data.totalUsage,data.totalSpend,used,monthlyUsage,monthlySpend,totalUsage,totalSpend)",
            limit: "coalesce(data.limit,data.totalLimit,data.quota,data.totalQuota,limit,totalLimit,quota,totalQuota)"
        )
        let paths = [
            "https://www.minimaxi.com/account/query_balance?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/query_balance?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/query_balance/?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/account/query_balance?GroupId=\(groupID)",
            "https://platform.minimaxi.com/backend/query_balance?GroupId=\(groupID)"
        ]
        return paths.map { path in
            ResolvedRelayRequest(
                method: "GET",
                path: path,
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: expressions.remaining,
                usedExpression: expressions.used,
                limitExpression: expressions.limit,
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        }
    }

    private func buildHeaderCandidate(
        request: ResolvedRelayRequest,
        header: String,
        scheme: String?,
        rawValue: String,
        source: String,
        persistedCredential: String?
    ) -> RelayCredentialCandidate {
        let authValue: String
        let trimmedScheme = scheme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedScheme.isEmpty || header.caseInsensitiveCompare("Cookie") == .orderedSame {
            authValue = rawValue
        } else {
            authValue = "\(trimmedScheme) \(rawValue)"
        }
        return RelayCredentialCandidate(
            headers: buildHeaders(request: request, authHeader: header, authValue: authValue),
            source: source,
            persistedCredential: persistedCredential
        )
    }

    private func buildHeaders(
        request: ResolvedRelayRequest,
        authHeader: String,
        authValue: String
    ) -> [String: String] {
        var headers = request.staticHeaders
        headers[authHeader] = authValue
        if let userID = request.userID {
            headers[request.userIDHeader] = userID
        }
        return headers
    }

    private func persistTokenCandidate(_ token: String, auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return keychain.saveToken(token, service: service, account: account)
    }

    private func readSavedCredential(auth: AuthConfig) -> String? {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return nil
        }
        return keychain.readToken(service: service, account: account)
    }

    private func normalizeBearerToken(_ value: String) -> String {
        KimiProvider.normalizeToken(value)
    }

    private func looksLikeCookieHeader(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("Bearer ") || trimmed.hasPrefix("bearer ") {
            return false
        }
        return trimmed.contains("=")
    }

    private func looksLikeMoonshotNonAuthCookieHeader(_ value: String) -> Bool {
        let cookieNames = parseCookieNames(value).map { $0.lowercased() }
        guard !cookieNames.isEmpty else { return false }

        let knownNonAuthNames: Set<String> = [
            "ingresscookie",
            "_ga",
            "_gid",
            "_gat",
            "_clck",
            "_clsk",
            "_ga_z0zten03pz"
        ]
        let authIndicators = ["session", "sess", "auth", "token", "jwt", "login", "user", "uid", "moonshot", "kimi"]

        if cookieNames.contains(where: { name in
            authIndicators.contains(where: { name.contains($0) })
        }) {
            return false
        }

        return cookieNames.allSatisfy { name in
            knownNonAuthNames.contains(name) ||
            name.hasPrefix("_ga_") ||
            name.hasPrefix("_cl")
        }
    }

    private func parseCookieNames(_ value: String) -> [String] {
        value
            .split(separator: ";")
            .compactMap { item in
                let pair = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pair.isEmpty,
                      let equalsIndex = pair.firstIndex(of: "=") else {
                    return nil
                }
                return String(pair[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private func isExpiredJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        guard let payloadData = KimiJWT.decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              payload["exp"] != nil else {
            return false
        }
        return KimiJWT.isExpired(token)
    }

    private func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    private func relayURL(baseURL: URL, rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return baseURL.appending(path: "/")
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           let absolute = URL(string: trimmed) {
            return absolute
        }

        let normalized = normalizedPath(trimmed)
        guard let queryIndex = normalized.firstIndex(of: "?") else {
            return baseURL.appending(path: normalized)
        }

        let pathPart = String(normalized[..<queryIndex])
        let queryPart = String(normalized[normalized.index(after: queryIndex)...])
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = pathPart.isEmpty ? "/" : pathPart
        components?.percentEncodedQuery = queryPart.isEmpty ? nil : queryPart
        return components?.url ?? baseURL.appending(path: pathPart.isEmpty ? "/" : pathPart)
    }

    private func relayRootURL(from raw: String) -> URL? {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL(raw)
        guard var components = URLComponents(string: normalized),
              let host = components.host,
              !host.isEmpty else {
            return URL(string: normalized)
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url ?? URL(string: normalized)
    }

    private func requestJSON(url: URL, headers: [String: String], method: String?, bodyJSON: String?) async throws -> Any {
        var req = URLRequest(url: url)
        let normalizedMethod = (method ?? "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        req.httpMethod = normalizedMethod.isEmpty ? "GET" : normalizedMethod
        req.timeoutInterval = 15
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyJSON {
            let trimmedBody = bodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty, req.httpMethod != "GET" {
                req.httpBody = trimmedBody.data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderError.invalidResponse("account balance JSON decode failed")
        }
    }

    private func numericValue(for expression: String, in root: Any) -> Double? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("sum("), trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(4).dropLast())
            let numbers = values(at: inner, in: root).compactMap(coerceDouble)
            guard !numbers.isEmpty else { return nil }
            return numbers.reduce(0, +)
        }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = numericValue(for: argument, in: root) {
                    return value
                }
            }
            return nil
        }

        if trimmed.hasPrefix("add("), trimmed.hasSuffix(")") {
            let arguments = splitArguments(String(trimmed.dropFirst(4).dropLast()))
            guard !arguments.isEmpty else { return nil }
            var total: Double = 0
            var found = false
            for argument in arguments {
                if let value = numericValue(for: argument, in: root) {
                    total += value
                    found = true
                }
            }
            return found ? total : nil
        }

        if let literal = Double(trimmed) {
            return literal
        }

        return value(at: trimmed, in: root).flatMap(coerceDouble)
    }

    private func stringValue(for expression: String, in root: Any) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = stringValue(for: argument, in: root), !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        if let value = value(at: trimmed, in: root) {
            if let string = value as? String {
                let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return normalized
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private func boolValue(for expression: String, in root: Any) -> Bool? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = boolValue(for: argument, in: root) {
                    return value
                }
            }
            return nil
        }
        return value(at: trimmed, in: root).flatMap(coerceBool) ?? coerceBool(trimmed)
    }

    private func splitArguments(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in input {
            switch character {
            case "(":
                depth += 1
                current.append(character)
            case ")":
                depth = max(0, depth - 1)
                current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    private func value(at path: String, in root: Any) -> Any? {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return nil }
        var current: Any? = root
        for step in steps {
            if let index = Int(step), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
                continue
            }
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[step]
        }
        return current
    }

    private func values(at path: String, in root: Any) -> [Any] {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return [] }
        return collectValues(current: root, steps: steps, index: 0)
    }

    private func collectValues(current: Any, steps: [String], index: Int) -> [Any] {
        guard index < steps.count else { return [current] }
        let step = steps[index]

        if step == "*" {
            guard let array = current as? [Any] else { return [] }
            return array.flatMap { collectValues(current: $0, steps: steps, index: index + 1) }
        }

        if let i = Int(step), let array = current as? [Any], array.indices.contains(i) {
            return collectValues(current: array[i], steps: steps, index: index + 1)
        }

        guard let dict = current as? [String: Any], let next = dict[step] else {
            return []
        }
        return collectValues(current: next, steps: steps, index: index + 1)
    }

    private func coerceDouble(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func coerceBool(_ value: Any) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1", "yes", "ok", "success":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func convertAilinyuQuotaToDisplayAmount(
        baseURL: URL,
        headers: [String: String],
        quota: Double
    ) async throws -> AilinyuDisplayAmount {
        let root = try await requestJSON(
            url: baseURL.appending(path: "/api/status"),
            headers: headers,
            method: "GET",
            bodyJSON: nil
        )
        guard let quotaPerUnit = numericValue(for: "data.quota_per_unit", in: root), quotaPerUnit > 0 else {
            throw ProviderError.invalidResponse("missing data.quota_per_unit")
        }
        let displayType = stringValue(for: "data.quota_display_type", in: root)?.uppercased() ?? "USD"
        let displayRate: Double
        let unit: String
        switch displayType {
        case "CNY":
            displayRate = numericValue(for: "data.usd_exchange_rate", in: root) ?? 1
            unit = "¥"
        case "CUSTOM":
            displayRate = numericValue(for: "data.custom_currency_exchange_rate", in: root) ?? 1
            unit = stringValue(for: "data.custom_currency_symbol", in: root) ?? "¤"
        case "TOKENS":
            displayRate = 1
            unit = "tokens"
        default:
            displayRate = 1
            unit = "$"
        }

        if displayType == "TOKENS" {
            return AilinyuDisplayAmount(
                remaining: quota,
                quotaPerUnit: quotaPerUnit,
                rate: 1,
                unit: unit,
                displayType: displayType
            )
        }

        let remaining = (quota / quotaPerUnit) * displayRate
        return AilinyuDisplayAmount(
            remaining: remaining,
            quotaPerUnit: quotaPerUnit,
            rate: displayRate,
            unit: unit,
            displayType: displayType
        )
    }

    private func request<T: Decodable>(url: URL, bearerToken: String, type: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }

        if http.statusCode == 401 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.invalidResponse("decode failed for \(url.path)")
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = root["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = root["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let details = root["details"] as? String {
            return details.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmptyOrDefault(_ value: String?, fallback: String) -> String {
        trimmedOrNil(value) ?? fallback
    }
}

private struct RelayRawTokenCandidate {
    let token: String
    let source: String
}

private struct RelayCredentialCandidate {
    let headers: [String: String]
    let source: String
    let persistedCredential: String?
}

private struct ResolvedRelayRequest {
    let method: String
    let path: String
    let bodyJSON: String?
    let staticHeaders: [String: String]
    let userID: String?
    let userIDHeader: String
    let authHeader: String?
    let authScheme: String?
    let successExpression: String?
    let remainingExpression: String
    let usedExpression: String?
    let limitExpression: String?
    let unitExpression: String?
    let accountLabelExpression: String?
}

private struct AilinyuDisplayAmount {
    let remaining: Double
    let quotaPerUnit: Double
    let rate: Double
    let unit: String
    let displayType: String
}

private struct TokenChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let note: String
    let rawMeta: [String: String]
}

private struct AccountChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let accountLabel: String?
    let note: String
    let rawMeta: [String: String]
}

struct OpenTokenUsageEnvelope: Decodable {
    struct TokenUsage: Decodable {
        let expiresAt: Int?
        let name: String
        let object: String?
        let totalAvailable: Double
        let totalGranted: Double
        let totalUsed: Double
        let unlimitedQuota: Bool

        enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case name
            case object
            case totalAvailable = "total_available"
            case totalGranted = "total_granted"
            case totalUsed = "total_used"
            case unlimitedQuota = "unlimited_quota"
        }
    }

    let code: Bool?
    let message: String?
    let data: TokenUsage
}

struct OpenBillingSubscription: Decodable {
    let object: String
    let hasPaymentMethod: Bool
    let softLimitUSD: Double
    let hardLimitUSD: Double
    let systemHardLimitUSD: Double
    let accessUntil: Int

    enum CodingKeys: String, CodingKey {
        case object
        case hasPaymentMethod = "has_payment_method"
        case softLimitUSD = "soft_limit_usd"
        case hardLimitUSD = "hard_limit_usd"
        case systemHardLimitUSD = "system_hard_limit_usd"
        case accessUntil = "access_until"
    }
}

struct OpenBillingUsage: Decodable {
    let object: String
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case object
        case totalUsage = "total_usage"
    }
}
