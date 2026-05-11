import Foundation

struct OfficialOAuthRefreshResponse {
    let accessToken: String
    let json: [String: Any]
}

enum OfficialProviderAuthRuntime {
    static func urlEncodedFormData(_ fields: [String: String]) -> Data? {
        fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    static func requestOAuthRefresh(
        session: URLSession,
        request: URLRequest,
        invalidResponseMessage: String,
        missingAccessTokenMessage: String,
        httpErrorMessage: (Int) -> String,
        unauthorizedStatusCodes: Set<Int> = [400, 401]
    ) async throws -> OfficialOAuthRefreshResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse(invalidResponseMessage)
        }
        if unauthorizedStatusCodes.contains(http.statusCode) {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse(httpErrorMessage(http.statusCode))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(json["access_token"]) else {
            throw ProviderError.invalidResponse(missingAccessTokenMessage)
        }
        return OfficialOAuthRefreshResponse(
            accessToken: accessToken,
            json: json
        )
    }

    static func updateJSONObjectFile(
        path: String,
        mutate: (inout [String: Any]) -> Void
    ) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        mutate(&json)

        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
