import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private let configStore = ConfigStore()
    private let keychain = KeychainService()
    private let kimiCookieService = KimiBrowserCookieService()
    private let notifications = NotificationService()
    private let providerFactory: ProviderFactory

    private(set) var config: AppConfig
    private(set) var snapshots: [String: UsageSnapshot] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var lastUpdatedAt: Date?

    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var consecutiveFailures: [String: Int] = [:]
    private var activeAlerts: Set<String> = []
    private var hasStarted = false

    init() {
        self.config = (try? configStore.load()) ?? .default
        self.providerFactory = ProviderFactory(keychain: keychain, kimiCookieService: kimiCookieService)
        notifications.requestPermissionIfNeeded()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        restartPolling()
    }

    func restartPolling() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()

        for provider in config.providers where provider.enabled {
            pollTasks[provider.id] = Task { [weak self] in
                await self?.pollLoop(providerID: provider.id)
            }
        }
    }

    func refreshNow() {
        let enabled = config.providers.filter(\.enabled)
        guard !enabled.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            for descriptor in enabled {
                await self.refreshProvider(descriptor, forceRefresh: true)
            }
        }
    }

    var language: AppLanguage {
        config.language
    }

    func setLanguage(_ language: AppLanguage) {
        guard config.language != language else { return }
        config.language = language
        try? configStore.save(config)
    }

    func text(_ key: L10nKey) -> String {
        Localizer.text(key, language: config.language)
    }

    func aggregateStatusTitle(_ status: AggregateStatus) -> String {
        switch status {
        case .normal:
            return text(.statusNormal)
        case .alert:
            return text(.statusAlert)
        case .disconnected:
            return text(.statusDisconnected)
        }
    }

    func setEnabled(_ enabled: Bool, providerID: String) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
        config.providers[idx].enabled = enabled
        persistAndRestart()
    }

    func setLowThreshold(_ value: Double, providerID: String) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
        config.providers[idx].threshold.lowRemaining = value
        persistAndRestart()
    }

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return false
        }
        return keychain.readToken(service: service, account: account)?.isEmpty == false
    }

    func hasToken(auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return keychain.readToken(service: service, account: account)?.isEmpty == false
    }

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return false
        }
        return keychain.saveToken(token, service: service, account: account)
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return keychain.saveToken(token, service: service, account: account)
    }

    func addOpenRelay(name: String, baseURL: String) {
        let provider = ProviderDescriptor.makeOpenRelay(name: name, baseURL: baseURL)
        config.providers.append(provider)
        persistAndRestart()
    }

    func removeProvider(providerID: String) {
        config.providers.removeAll { $0.id == providerID }
        snapshots.removeValue(forKey: providerID)
        errors.removeValue(forKey: providerID)
        consecutiveFailures.removeValue(forKey: providerID)
        activeAlerts.remove("low:\(providerID)")
        activeAlerts.remove("fail:\(providerID)")
        activeAlerts.remove("auth:\(providerID)")
        persistAndRestart()
    }

    func updateOpenProviderSettings(
        providerID: String,
        name: String,
        baseURL: String,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              (config.providers[idx].type == .open || config.providers[idx].type == .dragon) else {
            return
        }

        var provider = config.providers[idx]
        provider.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.baseURL = normalizeBaseURL(baseURL.isEmpty ? (provider.baseURL ?? "") : baseURL)

        var openConfig = provider.openConfig ?? provider.normalized().openConfig ?? OpenProviderConfig(tokenUsageEnabled: true, accountBalance: nil)
        openConfig.tokenUsageEnabled = tokenUsageEnabled

        var accountConfig = openConfig.accountBalance ?? provider.normalized().openConfig?.accountBalance
        if accountConfig == nil {
            accountConfig = provider.normalized().openConfig?.accountBalance
        }

        if var accountConfig {
            accountConfig.enabled = accountEnabled
            accountConfig.authHeader = nonEmptyOrDefault(authHeader, fallback: "Authorization")
            accountConfig.authScheme = authScheme.trimmingCharacters(in: .whitespacesAndNewlines)
            accountConfig.userID = trimmedOrNil(userID)
            accountConfig.userIDHeader = nonEmptyOrDefault(userIDHeader, fallback: "New-Api-User")
            accountConfig.endpointPath = nonEmptyOrDefault(endpointPath, fallback: "/api/user/self")
            accountConfig.remainingJSONPath = nonEmptyOrDefault(remainingJSONPath, fallback: "data.quota")
            accountConfig.usedJSONPath = trimmedOrNil(usedJSONPath)
            accountConfig.limitJSONPath = trimmedOrNil(limitJSONPath)
            accountConfig.successJSONPath = trimmedOrNil(successJSONPath)
            accountConfig.unit = nonEmptyOrDefault(unit, fallback: "quota")
            openConfig.accountBalance = accountConfig
        }

        provider.openConfig = openConfig
        config.providers[idx] = provider
        persistAndRestart()
    }

    func updateKimiProviderSettings(
        providerID: String,
        name: String,
        authMode: KimiAuthMode,
        autoCookieEnabled: Bool
    ) {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].type == .kimi else {
            return
        }

        var provider = config.providers[idx]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            provider.name = trimmedName
        }

        var kimiConfig = provider.kimiConfig ?? KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: provider.auth.keychainAccount ?? "kimi.com/kimi-auth-manual",
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .chromium]
        )
        kimiConfig.authMode = authMode
        kimiConfig.autoCookieEnabled = autoCookieEnabled
        provider.kimiConfig = kimiConfig

        config.providers[idx] = provider
        persistAndRestart()
    }

    func saveKimiManualToken(_ token: String, providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }),
              provider.type == .kimi,
              let service = provider.auth.keychainService else {
            return false
        }
        let account = provider.kimiConfig?.manualTokenAccount ?? provider.auth.keychainAccount ?? "kimi.com/kimi-auth-manual"
        let normalized = KimiProvider.normalizeToken(token)
        guard !normalized.isEmpty else { return false }
        return keychain.saveToken(normalized, service: service, account: account)
    }

    func detectAndCacheKimiToken(providerID: String) async -> String {
        guard let provider = config.providers.first(where: { $0.id == providerID }),
              provider.type == .kimi else {
            return text(.error)
        }
        let order = provider.kimiConfig?.browserOrder ?? [.arc, .chrome, .safari, .edge, .brave, .chromium]
        guard let detected = kimiCookieService.detectKimiAuthToken(order: order) else {
            return text(.kimiAuthNotFound)
        }

        let normalized = KimiProvider.normalizeToken(detected.token)
        if normalized.isEmpty || KimiJWT.isExpired(normalized) {
            return text(.tokenInvalidOrExpired)
        }

        guard let service = provider.auth.keychainService else {
            return text(.error)
        }
        let account = "kimi.com/kimi-auth-auto"
        _ = keychain.saveToken(normalized, service: service, account: account)
        restartPolling()
        return "\(text(.kimiAuthDetected)): \(detected.source)"
    }

    var aggregateStatus: AggregateStatus {
        let enabled = config.providers.filter(\.enabled)
        if enabled.isEmpty {
            return .disconnected
        }

        let allErrored = enabled.allSatisfy { errors[$0.id] != nil }
        if allErrored {
            return .disconnected
        }

        if !activeAlerts.isEmpty || snapshots.values.contains(where: { $0.status == .warning || $0.status == .error }) {
            return .alert
        }

        return .normal
    }

    private func persistAndRestart() {
        try? configStore.save(config)
        restartPolling()
    }

    private func descriptor(for id: String) -> ProviderDescriptor? {
        config.providers.first(where: { $0.id == id })
    }

    private func pollLoop(providerID: String) async {
        while !Task.isCancelled {
            guard let descriptor = descriptor(for: providerID), descriptor.enabled else {
                return
            }

            await refreshProvider(descriptor, forceRefresh: false)

            let failureCount = consecutiveFailures[providerID, default: 0]
            let delay = BackoffPolicy.delaySeconds(baseInterval: descriptor.pollIntervalSec, consecutiveFailures: failureCount)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        let provider = providerFactory.makeProvider(for: descriptor)

        do {
            let snapshot = try await provider.fetch(forceRefresh: forceRefresh)
            snapshots[descriptor.id] = snapshot
            errors.removeValue(forKey: descriptor.id)
            consecutiveFailures[descriptor.id] = 0
            lastUpdatedAt = Date()

            if AlertEngine.shouldAlertLowRemaining(snapshot: snapshot, rule: descriptor.threshold) {
                let key = "low:\(descriptor.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.lowBalanceWarning),
                        body: Localizer.lowBalanceBody(
                            providerName: descriptor.name,
                            remaining: format(snapshot.remaining),
                            unit: snapshot.unit,
                            language: config.language
                        ),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            } else {
                activeAlerts.remove("low:\(descriptor.id)")
            }

            activeAlerts.remove("fail:\(descriptor.id)")
            activeAlerts.remove("auth:\(descriptor.id)")
        } catch {
            if isCancellationError(error) || Task.isCancelled {
                return
            }

            if isRateLimitedError(error),
               var previous = snapshots[descriptor.id] {
                previous.status = .warning
                previous.updatedAt = Date()
                previous.note = "\(previous.note) | rate limited, showing cached value"
                snapshots[descriptor.id] = previous
                errors.removeValue(forKey: descriptor.id)
                consecutiveFailures[descriptor.id] = 0
                lastUpdatedAt = Date()
                return
            }

            errors[descriptor.id] = error.localizedDescription
            consecutiveFailures[descriptor.id, default: 0] += 1

            let failureCount = consecutiveFailures[descriptor.id, default: 0]
            if AlertEngine.shouldAlertFailures(consecutiveFailures: failureCount, rule: descriptor.threshold) {
                let key = "fail:\(descriptor.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.providerUnreachable),
                        body: Localizer.providerFailedBody(
                            providerName: descriptor.name,
                            failures: failureCount,
                            language: config.language
                        ),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            }

            if descriptor.threshold.notifyOnAuthError,
               AlertEngine.isAuthError(error) {
                let key = "auth:\(descriptor.id)"
                if !activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.authError),
                        body: Localizer.authErrorBody(providerName: descriptor.name, language: config.language),
                        identifier: key
                    )
                    activeAlerts.insert(key)
                }
            }
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        return false
    }

    private func isRateLimitedError(_ error: Error) -> Bool {
        if let providerError = error as? ProviderError {
            if case .rateLimited = providerError {
                return true
            }
        }

        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        return description.contains("rate limited") || description.contains("429")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return text(.unlimited) }
        return String(format: "%.2f", value)
    }

    private func normalizeBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return "https://open.ailinyu.de"
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmptyOrDefault(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum AggregateStatus {
    case normal
    case alert
    case disconnected

    var iconName: String {
        switch self {
        case .normal:
            return "checkmark.circle.fill"
        case .alert:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "xmark.octagon.fill"
        }
    }
}
