import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    static func looksLikeGenericDefaultOverride(_ override: RelayManualOverride?) -> Bool {
        guard let override else { return true }

        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        let method = normalized(override.requestMethod)
        let authHeader = normalized(override.authHeader)
        let authScheme = normalized(override.authScheme)
        let endpoint = normalized(override.endpointPath)
        let remaining = normalized(override.remainingExpression)
        let used = normalized(override.usedExpression)
        let limit = normalized(override.limitExpression)
        let success = normalized(override.successExpression)
        let unit = normalized(override.unitExpression)
        let userIDHeader = normalized(override.userIDHeader)
        let userID = normalized(override.userID)
        let body = normalized(override.requestBodyJSON)
        let accountLabel = normalized(override.accountLabelExpression)
        let staticHeadersEmpty = override.staticHeaders?.isEmpty ?? true

        let isRemainingDefault = remaining.isEmpty || remaining == "data.quota" || remaining == "div(data.quota,50000)"
        let isUsedDefault = used.isEmpty || used == "data.used_quota" || used == "div(data.used_quota,50000)"
        let isLimitDefault = limit.isEmpty || limit == "data.request_quota" || limit == "add(data.quota,data.used_quota)" || limit == "div(add(data.quota,data.used_quota),50000)"
        let isUnitDefault = unit.isEmpty || unit == "quota" || unit == "usd"

        return (method.isEmpty || method == "get") &&
            (authHeader.isEmpty || authHeader == "authorization") &&
            (authScheme.isEmpty || authScheme == "bearer") &&
            (endpoint.isEmpty || endpoint == "/api/user/self") &&
            isRemainingDefault &&
            isUsedDefault &&
            isLimitDefault &&
            (success.isEmpty || success == "success") &&
            isUnitDefault &&
            (userIDHeader.isEmpty || userIDHeader == "new-api-user") &&
            userID.isEmpty &&
            body.isEmpty &&
            accountLabel.isEmpty &&
            staticHeadersEmpty
    }

    static func migrateGenericNewAPIDefaultOverride(_ override: RelayManualOverride?) -> RelayManualOverride? {
        guard var override else { return nil }

        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        let method = normalized(override.requestMethod)
        let authHeader = normalized(override.authHeader)
        let authScheme = normalized(override.authScheme)
        let endpoint = normalized(override.endpointPath)
        let success = normalized(override.successExpression)
        let userIDHeader = normalized(override.userIDHeader)
        let remaining = normalized(override.remainingExpression)
        let used = normalized(override.usedExpression)
        let limit = normalized(override.limitExpression)
        let unit = normalized(override.unitExpression)
        let staticHeadersEmpty = override.staticHeaders?.isEmpty ?? true

        let matchesLegacyGenericNewAPI =
            (method.isEmpty || method == "get") &&
            (authHeader.isEmpty || authHeader == "authorization") &&
            (authScheme.isEmpty || authScheme == "bearer") &&
            (endpoint.isEmpty || endpoint == "/api/user/self") &&
            (success.isEmpty || success == "success") &&
            (userIDHeader.isEmpty || userIDHeader == "new-api-user") &&
            staticHeadersEmpty &&
            (remaining.isEmpty || remaining == "data.quota" || remaining == "div(data.quota,50000)") &&
            (used.isEmpty || used == "data.used_quota" || used == "div(data.used_quota,50000)") &&
            (
                limit.isEmpty ||
                limit == "data.request_quota" ||
                limit == "add(data.quota,data.used_quota)" ||
                limit == "div(add(data.quota,data.used_quota),50000)"
            ) &&
            (unit.isEmpty || unit == "usd" || unit == "quota")

        guard matchesLegacyGenericNewAPI else { return override }

        override.remainingExpression = "data.quota"
        override.usedExpression = "data.used_quota"
        override.limitExpression = "add(data.quota,data.used_quota)"
        override.unitExpression = "quota"
        return override
    }

    static func looksLikeTemplateDefaultOverride(
        _ override: RelayManualOverride?,
        manifest: RelayAdapterManifest
    ) -> Bool {
        guard let override else { return true }

        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        func normalizedHeaders(_ headers: [String: String]?) -> [String: String] {
            guard let headers else { return [:] }
            return Dictionary(uniqueKeysWithValues: headers.map { key, value in
                (
                    key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            })
        }

        let request = manifest.balanceRequest
        let extract = manifest.extract

        let defaultMethod = normalized(request.method)
        let defaultAuthHeader = normalized(request.authHeader ?? "Authorization")
        let defaultAuthScheme = normalized(request.authScheme ?? "Bearer")
        let defaultEndpoint = normalized(request.path)
        let defaultRemaining = normalized(extract.remaining)
        let defaultUsed = normalized(extract.used)
        let defaultLimit = normalized(extract.limit)
        let defaultSuccess = normalized(extract.success)
        let defaultUnit = normalized(extract.unit)
        let defaultAccountLabel = normalized(extract.accountLabel)
        let defaultUserID = normalized(request.userID)
        let defaultUserIDHeader = normalized(request.userIDHeader ?? "New-Api-User")
        let defaultBody = normalized(request.bodyJSON)
        let defaultHeaders = normalizedHeaders(request.headers)

        let method = normalized(override.requestMethod)
        let authHeader = normalized(override.authHeader)
        let authScheme = normalized(override.authScheme)
        let endpoint = normalized(override.endpointPath)
        let remaining = normalized(override.remainingExpression)
        let used = normalized(override.usedExpression)
        let limit = normalized(override.limitExpression)
        let success = normalized(override.successExpression)
        let unit = normalized(override.unitExpression)
        let accountLabel = normalized(override.accountLabelExpression)
        let userID = normalized(override.userID)
        let userIDHeader = normalized(override.userIDHeader)
        let body = normalized(override.requestBodyJSON)
        let staticHeaders = normalizedHeaders(override.staticHeaders)

        return (method.isEmpty || method == defaultMethod) &&
            (authHeader.isEmpty || authHeader == defaultAuthHeader) &&
            (authScheme.isEmpty || authScheme == defaultAuthScheme) &&
            (endpoint.isEmpty || endpoint == defaultEndpoint) &&
            (remaining.isEmpty || remaining == defaultRemaining) &&
            (used.isEmpty || used == defaultUsed) &&
            (limit.isEmpty || limit == defaultLimit) &&
            (success.isEmpty || success == defaultSuccess) &&
            (unit.isEmpty || unit == defaultUnit) &&
            (accountLabel.isEmpty || accountLabel == defaultAccountLabel) &&
            (userID.isEmpty || userID == defaultUserID) &&
            (userIDHeader.isEmpty || userIDHeader == defaultUserIDHeader) &&
            (body.isEmpty || body == defaultBody) &&
            (staticHeaders.isEmpty || staticHeaders == defaultHeaders)
    }
}
